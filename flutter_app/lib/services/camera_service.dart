import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/camera_device.dart';
import '../models/media_item.dart';

/// 摄像头管理服务
class CameraService {
  List<CameraDescription> _descriptions = [];
  CameraController? _controller;
  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isRecording => _controller?.value.isRecordingVideo ?? false;

  List<CameraDevice> get cameras {
    return _descriptions.asMap().entries.map((e) {
      final desc = e.value;
      debugPrint('[CameraService] Cam #${e.key}: '
          'name="${desc.name}" '
          'lensDirection=${desc.lensDirection.name} '
          'sensorOrientation=${desc.sensorOrientation}');
      return CameraDevice.fromMap({
        'deviceId': '${desc.lensDirection.name}_${e.key}',
        'label': desc.name,
        'index': e.key + 1,
        'facingMode': desc.lensDirection.name,
        'cam2Index': e.key,
      });
    }).toList();
  }

  /// 扫描可用摄像头
  Future<List<CameraDevice>> scanCameras() async {
    try {
      _descriptions = await availableCameras();
      debugPrint('[CameraService] ========================================');
      debugPrint('[CameraService] Total cameras detected: ${_descriptions.length}');
      for (var i = 0; i < _descriptions.length; i++) {
        final d = _descriptions[i];
        debugPrint('[CameraService] [$i] name="${d.name}"');
        debugPrint('[CameraService]     lensDirection=${d.lensDirection.name}');
        debugPrint('[CameraService]     sensorOrientation=${d.sensorOrientation}');
      }
      debugPrint('[CameraService] ========================================');
      if (_descriptions.isEmpty) {
        debugPrint('[CameraService] ⚠️ No cameras found! Possible causes:');
        debugPrint('[CameraService]   1. Phone does not have UVC kernel driver');
        debugPrint('[CameraService]   2. USB camera not plugged in or not powered');
        debugPrint('[CameraService]   3. Camera permission not granted');
        debugPrint('[CameraService]   4. OTG cable issue');
      }
    } catch (e) {
      debugPrint('[CameraService] Scan failed: $e');
      _descriptions = [];
    }
    return cameras;
  }

  /// 启动指定摄像头预览
  Future<void> startCamera(int index, {ResolutionPreset preset = ResolutionPreset.high}) async {
    await dispose();

    if (index < 0 || index >= _descriptions.length) {
      throw Exception('摄像头索引无效: $index');
    }

    _controller = CameraController(
      _descriptions[index],
      preset,
      imageFormatGroup: ImageFormatGroup.jpeg,
      enableAudio: false,
    );

    await _controller!.initialize();
  }

  /// 拍照
  Future<MediaItem> takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw Exception('摄像头未就绪');
    }

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = p.join(dir.path, 'photo_$timestamp.jpg');

    final xFile = await _controller!.takePicture();
    final file = File(xFile.path);
    await file.copy(filePath);

    return MediaItem(
      id: 'photo_$timestamp',
      type: MediaType.photo,
      filePath: filePath,
      timestamp: timestamp,
      fileSize: await file.length(),
      mimeType: 'image/jpeg',
    );
  }

  /// 开始录像
  Future<void> startRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw Exception('摄像头未就绪');
    }

    if (_controller!.value.isRecordingVideo) {
      throw Exception('已在录像中');
    }

    await _controller!.startVideoRecording();
  }

  /// 停止录像并返回媒体项
  Future<MediaItem> stopRecording() async {
    if (_controller == null || !_controller!.value.isRecordingVideo) {
      throw Exception('未在录像');
    }

    final xFile = await _controller!.stopVideoRecording();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final dir = await getApplicationDocumentsDirectory();
    final filePath = p.join(dir.path, 'video_$timestamp.mp4');
    final file = File(xFile.path);
    await file.copy(filePath);

    return MediaItem(
      id: 'video_$timestamp',
      type: MediaType.video,
      filePath: filePath,
      timestamp: timestamp,
      fileSize: await File(filePath).length(),
      mimeType: 'video/mp4',
    );
  }

  /// 释放资源
  Future<void> dispose() async {
    if (_controller != null) {
      if (_controller!.value.isRecordingVideo) {
        await _controller!.stopVideoRecording();
      }
      await _controller!.dispose();
      _controller = null;
    }
  }
}
