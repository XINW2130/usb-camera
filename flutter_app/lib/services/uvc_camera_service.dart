import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' hide log;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ffi_uvc/flutter_ffi_uvc.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/camera_device.dart';
import '../models/media_item.dart';

/// UVC 直连摄像头服务。
///
/// 绕过 Camera2 API，直接通过 libuvc 打开 USB 摄像头并把帧渲染到 Flutter
/// Texture（含拍照编码为 JPG）。用于系统相机 API 不枚举外接 USB 摄像头的场景。
class UvcCameraService {
  final UvcCamera _uvc = uvcCamera;

  /// 与 Android 原生编码器通信（JPEG 序列 -> H.264 MP4，零第三方依赖）。
  static const MethodChannel _encoderChannel =
      MethodChannel('com.example.usb_camera_monitor/encoder');

  int? _textureId;
  UvcCameraMode? _activeMode;
  UvcUsbDevice? _activeDevice;

  /// 实时诊断信息（直接显示在预览画面上，无需 adb）。
  final ValueNotifier<String> diagnostics = ValueNotifier<String>('');
  Timer? _diagTimer;

  // —— 录像状态（UVC 无原生录像，采用轮询取帧 + ffmpeg 编码）——
  bool _isRecording = false;
  bool get isRecording => _isRecording;
  Timer? _recTimer;
  bool _recBusy = false;
  Directory? _recDir;
  int _recFrameCount = 0;
  int? _lastRecSeq;
  DateTime? _recStart;
  static const int _recTargetFps = 24;

  /// 当前设备支持的所有预览模式（open 时缓存，供 UI 模式下拉选择清晰度/帧率）。
  List<UvcCameraMode> _modes = [];
  List<UvcCameraMode> get supportedModesList => _modes;

  int? get textureId => _textureId;
  bool get isPreviewing => _uvc.isPreviewing;
  UvcCameraMode? get activeMode => _activeMode;
  double get previewAspectRatio {
    final m = _activeMode;
    if (m == null || m.width <= 0 || m.height <= 0) return 0.0;
    return m.width / m.height;
  }
  String get activeModeLabel => _activeMode?.label ?? '';
  UvcUsbDevice? get activeDevice => _activeDevice;

  /// 列出系统枚举到的 UVC 摄像头（USB 层，与 Camera2 无关）
  Future<List<CameraDevice>> listDevices() async {
    try {
      _uvc.setLogLevel(UvcLogLevel.debug);
      final devices = await _uvc.listUsbDevices();
      return devices.map((d) {
        return CameraDevice(
          deviceId: 'uvc_${d.deviceId}',
          label: d.displayName,
          isBuiltin: false,
          isExternal: true,
          usbConfirmed: true,
          source: 'uvc',
          uvcDeviceId: d.deviceId,
        );
      }).toList();
    } catch (e) {
      log('[UvcCameraService] listDevices error: $e');
      return [];
    }
  }

  Future<bool> _ensurePermission() async {
    try {
      return await _uvc.ensureCameraPermission();
    } catch (e) {
      log('[UvcCameraService] ensureCameraPermission error: $e');
      return false;
    }
  }

  Future<void> _ensureTexture() async {
    if (_textureId != null) return;
    _textureId = await _uvc.createPreviewTexture();
  }

  /// 打开指定 UVC 设备并启动预览（自动协商最佳可工作模式）。
  Future<void> open(CameraDevice device) async {
    if (device.uvcDeviceId == null) {
      throw Exception('Invalid UVC device');
    }
    // 重新打开设备前，若仍在录像则先取消（避免旧取帧定时器引用已失效的预览）。
    if (_isRecording) {
      await _cancelRecording();
    }
    // 全程开启 native debug 日志，便于在 logcat 中排查黑屏。
    _uvc.setLogLevel(UvcLogLevel.debug);
    if (!await _ensurePermission()) {
      throw Exception('Camera permission denied');
    }
    await _ensureTexture();

    // 关闭之前可能打开的设备/预览
    await _uvc.closeUsbDevice();

    final openResult = await _uvc.openUsbDevice(device.uvcDeviceId!);
    if (openResult != 0) {
      throw Exception('openUsbDevice failed: ${_uvc.lastError}');
    }
    _activeDevice = await _currentUvcDevice(device.uvcDeviceId!);

    // 在 startPreview 之前先把纹理与首个候选模式尺寸绑定，
    // 确保 native 预览渲染进这个 Flutter texture（文档要求 attach 在
    // startPreview 之前）。
    final modes = _uvc.supportedModes();
    if (modes.isEmpty) {
      throw Exception('No supported camera modes were found');
    }
    _modes = modes; // 缓存，供 UI 模式下拉选择清晰度/帧率
    if (_textureId != null) {
      final first = modes.first;
      await _uvc.attachPreviewTexture(
        _textureId!,
        width: first.width,
        height: first.height,
      );
    }

    // 默认优先协商最高分辨率/帧率的模式（quality）。
    // reliability 会优先低分辨率保稳定，导致预览清晰度被压低；
    // quality 先试高分辨率，失败会自动回退到次优候选，仍稳定。
    final UvcAutoPreviewResult auto = await _uvc.startPreviewAuto(
      preference: UvcAutoPreviewPreference.quality,
      perModeTimeout: const Duration(seconds: 3),
      maxCandidates: 8,
    );
    _activeMode = auto.mode;

    // 用实际选定的模式尺寸再次绑定，保证与协议宽高一致。
    if (_activeMode != null && _textureId != null) {
      await _uvc.attachPreviewTexture(
        _textureId!,
        width: _activeMode!.width,
        height: _activeMode!.height,
      );
    }

    if (_activeMode == null) {
      throw Exception('No working UVC mode found');
    }

    log('[UVC] open succeeded: isPreviewing=${_uvc.isPreviewing} '
        'mode=${_activeMode?.label} '
        'textureId=$_textureId');
    _startDiagTimer();
  }

  /// 在已打开设备的前提下手动切换预览模式（选清晰度/帧率）。
  /// 流程：停止当前预览 → 按新模式尺寸重新绑定纹理 → 启动并验证出帧；
  /// 若新模式下无法出帧，自动回退到切换前的模式，保证预览不黑屏。
  Future<void> switchMode(UvcCameraMode mode) async {
    if (_textureId == null || !_uvc.isPreviewing) {
      throw Exception('预览未就绪，无法切换模式');
    }
    final prev = _activeMode;
    _uvc.stopPreview();
    try {
      if (_textureId != null) {
        await _uvc.attachPreviewTexture(
          _textureId!,
          width: mode.width,
          height: mode.height,
        );
      }
      final result = await _uvc.startPreview(mode);
      if (!result.success) {
        throw Exception('模式启动失败: ${result.lastError ?? "未知错误"}');
      }
      _activeMode = mode;
      log('[UVC] switched mode -> ${mode.label}');
    } catch (e) {
      // 回退到切换前的模式，避免预览黑屏。
      if (prev != null && _textureId != null) {
        try {
          await _uvc.attachPreviewTexture(
            _textureId!,
            width: prev.width,
            height: prev.height,
          );
          final r = await _uvc.startPreview(prev);
          if (r.success) _activeMode = prev;
        } catch (_) {
          // 回退也失败，交由上层提示。
        }
      }
      rethrow;
    } finally {
      _logDiagnostics();
    }
  }

  /// 启动实时诊断采样（每 500ms 刷新一次，结果同时写入 [diagnostics] 与 log）。
  void _startDiagTimer() {
    _stopDiagTimer();
    _logDiagnostics();
    _diagTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _logDiagnostics(),
    );
  }

  void _stopDiagTimer() {
    _diagTimer?.cancel();
    _diagTimer = null;
  }

  /// 读取 native 层诊断信息，帮助判断黑屏是出帧问题还是显示问题。
  void _logDiagnostics() {
    try {
      final seq = _uvc.latestFrameSequence();
      final stats = _uvc.getStreamStats();
      final buf = StringBuffer();
      buf.writeln('prev=${_uvc.isPreviewing} seq=$seq');
      buf.writeln(
          'in=${stats.inputFrameCount} deliv=${stats.deliveredFrameCount} '
          'fps=${stats.deliveredFps.toStringAsFixed(1)}');
      buf.writeln(
          'decFail=${stats.decodeFailureCount} '
          'surfFail=${stats.previewSurfaceFailureCount} '
          'convFail=${stats.conversionFailureCount}');
      buf.writeln(
          'under=${stats.undersizedFrameCount} '
          'mjpeg=${stats.invalidMjpegCount} '
          'bufFail=${stats.bufferAllocationFailureCount}');
      buf.writeln('mode=${_activeMode?.label ?? '-'}');
      final err = _uvc.lastError;
      buf.writeln('err=${err.isEmpty ? '(none)' : err}');
      final text = buf.toString().trim();
      diagnostics.value = text;
      log('[UVC][diag] $text');
    } catch (e) {
      diagnostics.value = 'diag error: $e';
      log('[UVC][diag] error reading diagnostics: $e');
    }
  }

  Future<UvcUsbDevice?> _currentUvcDevice(int deviceId) async {
    try {
      final devices = await _uvc.listUsbDevices();
      final match = devices.where((d) => d.deviceId == deviceId);
      return match.isEmpty ? null : match.first;
    } catch (_) {
      return null;
    }
  }

  /// 抓取当前预览帧并编码为 JPG 文件，返回媒体项。
  Future<MediaItem?> capturePhoto() async {
    final frame = _uvc.copyLatestFrame();
    if (frame == null) return null;

    final image = img.Image.fromBytes(
      width: frame.width,
      height: frame.height,
      bytes: frame.rgbaBytes.buffer,
      format: img.Format.uint8,
      numChannels: 4,
    );
    final jpgBytes = img.encodeJpg(image, quality: 90);

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = p.join(dir.path, 'uvc_photo_$timestamp.jpg');
    final file = File(filePath);
    await file.writeAsBytes(jpgBytes);

    return MediaItem(
      id: 'uvc_photo_$timestamp',
      type: MediaType.photo,
      filePath: filePath,
      timestamp: timestamp,
      fileSize: await file.length(),
      mimeType: 'image/jpeg',
    );
  }

  /// 开始录像：定时抓取预览帧（RGBA）编码为 JPEG 序列，停止时由 ffmpeg 合成为 MP4。
  /// UVC 插件没有原生录像能力，这里用 copyLatestFrame 轮询取帧实现。
  Future<void> startRecording() async {
    if (_isRecording) return;
    if (_textureId == null || !_uvc.isPreviewing) {
      throw Exception('预览未就绪，无法录像');
    }

    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(
      base.path,
      'uvc_rec_${DateTime.now().millisecondsSinceEpoch}',
    ));
    await dir.create(recursive: true);

    _recDir = dir;
    _recFrameCount = 0;
    _lastRecSeq = null;
    _recStart = DateTime.now();
    _isRecording = true;

    _recTimer = Timer.periodic(
      Duration(milliseconds: (1000 / _recTargetFps).round()),
      _captureRecFrame,
    );
    log('[UVC] recording started -> ${dir.path}');
  }

  void _captureRecFrame(Timer timer) {
    if (!_isRecording || _recBusy || _recDir == null) return;
    _recBusy = true;
    // 在微任务外异步执行，避免阻塞定时器回调链。
    Future(() async {
      try {
        final seq = _uvc.latestFrameSequence();
        if (seq == _lastRecSeq) return; // 没有新帧，跳过重复帧
        _lastRecSeq = seq;

        final frame = _uvc.copyLatestFrame();
        if (frame == null) return;

        final image = img.Image.fromBytes(
          width: frame.width,
          height: frame.height,
          bytes: frame.rgbaBytes.buffer,
          format: img.Format.uint8,
          numChannels: 4,
        );
        final jpg = img.encodeJpg(image, quality: 80);

        final name = 'frame_${_recFrameCount.toString().padLeft(6, '0')}.jpg';
        final file = File(p.join(_recDir!.path, name));
        await file.writeAsBytes(jpg);
        _recFrameCount++;
      } catch (e) {
        log('[UVC] captureRecFrame error: $e');
      } finally {
        _recBusy = false;
      }
    });
  }

  /// 停止录像并将 JPEG 序列合成为 MP4，返回媒体项；若未录到任何帧返回 null。
  Future<MediaItem?> stopRecording() async {
    if (!_isRecording) return null;
    _isRecording = false;
    _recTimer?.cancel();
    _recTimer = null;

    final dir = _recDir;
    final start = _recStart;
    _recDir = null;
    _recStart = null;

    if (dir == null || _recFrameCount == 0) {
      _cleanupRecDir(dir);
      return null;
    }

    // 用实际抓帧数换算输入帧率，保证回放速度接近真实时长。
    final realSecs = start != null
        ? max(0.1, DateTime.now().difference(start).inMilliseconds / 1000)
        : 1.0;
    final fps = (_recFrameCount / realSecs).clamp(1, _recTargetFps * 1.5);

    final outDir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final outPath = p.join(outDir.path, 'uvc_video_$ts.mp4');

    log('[UVC] recording encode (native): framesDir=${dir.path} '
        'fps=${fps.toStringAsFixed(2)} -> $outPath');
    try {
      await _encoderChannel.invokeMethod('encode', {
        'framesDir': dir.path,
        'outputPath': outPath,
        'fps': fps.round(),
      });
      final outFile = File(outPath);
      if (!await outFile.exists()) {
        throw Exception('编码完成但未生成视频文件');
      }
      return MediaItem(
        id: 'uvc_video_$ts',
        type: MediaType.video,
        filePath: outPath,
        timestamp: ts,
        fileSize: await outFile.length(),
        mimeType: 'video/mp4',
      );
    } catch (e) {
      final outFile = File(outPath);
      if (await outFile.exists()) await outFile.delete();
      log('[UVC] stopRecording error: $e');
      rethrow;
    } finally {
      _cleanupRecDir(dir);
    }
  }

  Future<void> _cancelRecording() async {
    _isRecording = false;
    _recTimer?.cancel();
    _recTimer = null;
    final dir = _recDir;
    _recDir = null;
    _recStart = null;
    _cleanupRecDir(dir);
  }

  Future<void> _cleanupRecDir(Directory? dir) async {
    if (dir == null) return;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      log('[UVC] cleanupRecDir error: $e');
    }
  }

  /// 停止预览并关闭 USB 设备
  Future<void> close() async {
    if (_isRecording) await _cancelRecording();
    _stopDiagTimer();
    try {
      _uvc.stopPreview();
      await _uvc.closeUsbDevice();
    } catch (e) {
      log('[UvcCameraService] close error: $e');
    }
    _activeMode = null;
    _activeDevice = null;
    diagnostics.value = '';
  }

  /// 释放所有资源（纹理、USB 连接）
  Future<void> dispose() async {
    await close();
    if (_textureId != null) {
      try {
        await _uvc.disposePreviewTexture(_textureId!);
      } catch (e) {
        log('[UvcCameraService] disposeTexture error: $e');
      }
      _textureId = null;
    }
  }
}
