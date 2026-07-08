import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import '../theme/app_theme.dart';
import '../models/camera_device.dart';
import 'package:flutter_ffi_uvc/flutter_ffi_uvc.dart' show UvcCameraMode;
import '../services/camera_service.dart';
import '../services/uvc_camera_service.dart';
import '../services/media_gallery_service.dart';
import '../services/locale_service.dart';
import '../widgets/camera_preview.dart';
import '../widgets/controls_bar.dart';
import '../widgets/camera_selector.dart';
import '../widgets/usb_panel.dart';
import '../widgets/media_gallery.dart';

/// 主摄像头页面
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final CameraService _cameraService = CameraService();
  final UvcCameraService _uvcService = UvcCameraService();
  List<CameraDevice> _cameras = [];
  int? _activeCameraIndex;
  bool _isScanning = false;
  String _statusKey = 'init_status';
  Map<String, String>? _statusParams;
  String _statusType = 'loading';
  bool _isFullscreen = false;
  bool _isRecording = false;
  bool _isSwitchingMode = false;
  ResolutionPreset _currentPreset = ResolutionPreset.high;

  LocaleService get l10n => context.watch<LocaleService>();
  String get statusText => l10n.t(_statusKey, params: _statusParams);

  String _presetLabel(ResolutionPreset p) {
    switch (p) {
      case ResolutionPreset.low:
        return '360p';
      case ResolutionPreset.medium:
        return '480p';
      case ResolutionPreset.high:
        return '720p';
      case ResolutionPreset.veryHigh:
        return '1080p';
      case ResolutionPreset.ultraHigh:
        return '4K';
      case ResolutionPreset.max:
        return 'Max';
    }
  }

  @override
  void initState() {
    super.initState();
    _initCameras();
  }

  Future<void> _initCameras() async {
    await scanCameras();
  }

  Future<void> scanCameras() async {
    setState(() {
      _isScanning = true;
      _statusKey = 'status_scanning';
      _statusParams = null;
      _statusType = 'loading';
    });

    try {
      // 1) Camera2 层：仅列出外接摄像头（内置不列出）
      final allCam2 = await _cameraService.scanCameras();
      final externalCam2 = allCam2.where((c) => !c.isBuiltin).toList();

      // 2) UVC 直连层：USB 摄像头（绕过 Camera2，能真正出图）
      final uvcDevices = await _uvcService.listDevices();

      final combined = <CameraDevice>[...externalCam2, ...uvcDevices];
      setState(() {
        _cameras = combined;
        _isScanning = false;
      });

      if (combined.isEmpty) {
        setState(() {
          _statusKey = 'status_no_camera';
          _statusParams = null;
          _statusType = 'error';
        });
        return;
      }

      setState(() {
        _statusKey = 'status_cameras_ready';
        _statusParams = {'n': combined.length.toString()};
        _statusType = 'active';
      });

      // 自动优先选择 UVC 直连摄像头（能真正出图），否则第一个外接摄像头
      CameraDevice? preferred;
      for (final c in combined) {
        if (c.isUvc) { preferred = c; break; }
      }
      preferred ??= combined.first;
      final idx = _cameras.indexOf(preferred);
      if (idx != -1 && idx != _activeCameraIndex) {
        await _selectCamera(idx);
      }
    } catch (e) {
      setState(() {
        _isScanning = false;
        _statusKey = 'status_scan_failed';
        _statusParams = null;
        _statusType = 'error';
      });
    }
  }

  Future<void> _selectCamera(int index) async {
    if (index < 0 || index >= _cameras.length) return;
    final device = _cameras[index];

    setState(() {
      _activeCameraIndex = index;
      _statusType = 'loading';
      _statusKey = 'status_connecting';
      _statusParams = null;
    });

    try {
      if (device.isUvc) {
        // UVC 直连：绕过 Camera2，重建 USB 视频流
        await _uvcService.open(device);
        setState(() {
          _statusKey = 'uvc_connected';
          _statusParams = {'label': device.label};
          _statusType = 'active';
        });
      } else {
        // Camera2 路径：先关闭可能的 UVC 会话，再以新分辨率重建流
        await _uvcService.close();
        await _cameraService.startCamera(
          device.cam2Index!,
          preset: _currentPreset,
        );
        final cam = _cameras[index];
        setState(() {
          _statusKey = 'camera_connected';
          _statusParams = {'tag': l10n.t(cam.tagKey), 'label': cam.label};
          _statusType = 'active';
        });
      }
    } catch (e) {
      setState(() {
        _statusKey = device.isUvc ? 'uvc_open_failed' : 'status_conn_failed';
        _statusParams = null;
        _statusType = 'error';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ ${device.label}: $e')),
        );
      }
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _onTakePhoto() async {
    final device = _activeCamera;
    if (device == null) return;
    try {
      final item = device.isUvc
          ? await _uvcService.capturePhoto()
          : await _cameraService.takePhoto();
      if (item != null) {
        context.read<MediaGalleryService>().add(item);
        _snack(l10n.t('photo_captured'));
      } else {
        _snack(l10n.t('photo_failed'));
      }
    } catch (e) {
      _snack(l10n.t(device.isUvc ? 'uvc_capture_failed' : 'photo_failed'));
    }
  }

  Future<void> _onToggleRecord() async {
    final device = _activeCamera;
    if (device == null) return;
    try {
      if (device.isUvc) {
        // UVC 直连：走自实现的取帧录像
        if (_uvcService.isRecording) {
          final item = await _uvcService.stopRecording();
          setState(() => _isRecording = false);
          if (item != null) {
            context.read<MediaGalleryService>().add(item);
            _snack(l10n.t('video_saved'));
          } else {
            _snack(l10n.t('recording_stop_failed'));
          }
        } else {
          await _uvcService.startRecording();
          setState(() => _isRecording = true);
          _snack(l10n.t('recording_started'));
        }
      } else {
        if (_cameraService.isRecording) {
          final item = await _cameraService.stopRecording();
          setState(() => _isRecording = false);
          context.read<MediaGalleryService>().add(item);
          _snack(l10n.t('video_saved'));
        } else {
          await _cameraService.startRecording();
          setState(() => _isRecording = true);
          _snack(l10n.t('recording_started'));
        }
      }
    } catch (e) {
      final stillRecording =
          device.isUvc ? _uvcService.isRecording : _cameraService.isRecording;
      setState(() => _isRecording = stillRecording);
      _snack(l10n.t(
        stillRecording ? 'recording_stop_failed' : 'recording_failed',
      ));
    }
  }

  Future<void> _changeResolution(ResolutionPreset preset) async {
    if (_currentPreset == preset) return;
    final label = _presetLabel(preset);
    setState(() => _currentPreset = preset);
    if (_activeCameraIndex != null) {
      // 已连接摄像头：重建视频流（自动以新分辨率重新初始化）
      await _selectCamera(_activeCameraIndex!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.t('resolution_set', params: {'r': label}))),
        );
      }
    } else {
      // 未连接摄像头：仅记录目标分辨率，待摄像头连接后自动应用
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.t('resolution_no_camera', params: {'r': label})),
          ),
        );
      }
    }
  }

  /// 只返回外接（USB）摄像头
  List<CameraDevice> get _externalCameras =>
      _cameras.where((c) => !c.isBuiltin).toList();

  CameraDevice? get _activeCamera {
    if (_activeCameraIndex == null || _activeCameraIndex! >= _cameras.length) {
      return null;
    }
    return _cameras[_activeCameraIndex!];
  }

  @override
  void dispose() {
    _uvcService.dispose();
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: CameraPreviewPanel(
            controller: _cameraService.controller,
            activeCamera: _activeCamera,
            isInitialized: _cameraService.isInitialized,
            isRecording: _isRecording,
            isFullscreen: true,
            isUvc: _activeCamera?.isUvc ?? false,
            uvcTextureId: _activeCamera?.isUvc ?? false
                ? _uvcService.textureId
                : null,
            uvcAspectRatio: _uvcService.previewAspectRatio,
            uvcDiag: _uvcService.diagnostics,
            onToggleFullscreen: () => setState(() => _isFullscreen = false),
          ),
        ),
      );
    }

    final externalCameras = _externalCameras;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(externalCameras),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 900;
                  return isWide
                      ? _buildWideLayout(externalCameras)
                      : _buildNarrowLayout(externalCameras);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(List<CameraDevice> externalCameras) {
    final l = l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Logo
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.accent, AppTheme.accent2],
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: const Icon(Icons.videocam, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'USB Camera',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.text,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _statusType == 'active'
                            ? AppTheme.success
                            : _statusType == 'error'
                                ? AppTheme.danger
                                : AppTheme.text2,
                        boxShadow: _statusType == 'active'
                            ? [BoxShadow(color: AppTheme.success, blurRadius: 6)]
                            : _statusType == 'error'
                                ? [BoxShadow(color: AppTheme.danger, blurRadius: 6)]
                                : null,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      statusText,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.text2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 设备数量
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.surface2,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              l.t('header_usb_count', params: {
                'n': externalCameras.length.toString(),
                'total': _cameras.length.toString(),
              }),
              style: const TextStyle(fontSize: 11, color: AppTheme.text2),
            ),
          ),
          const SizedBox(width: 6),
          // 语言切换按钮
          Tooltip(
            message: l.isZh ? 'English' : '中文',
            child: InkWell(
              onTap: () => l.toggle(),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.language,
                  size: 18,
                  color: AppTheme.accent2,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 清空按钮
          Consumer<MediaGalleryService>(
            builder: (_, gallery, __) => TextButton(
              onPressed:
                  gallery.count > 0 ? () => _clearGallery(gallery) : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                foregroundColor: AppTheme.text2,
                textStyle: const TextStyle(fontSize: 11),
              ),
              child: Text(l.t('clear')),
            ),
          ),
        ],
      ),
    );
  }

  void _clearGallery(MediaGalleryService gallery) async {
    final l = l10n;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(l.t('clear_title')),
        content: Text(l.t('clear_content',
            params: {'n': gallery.count.toString()})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.t('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                Text(l.t('confirm'), style: const TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await gallery.clearAll();
    }
  }

  Widget _buildWideLayout(List<CameraDevice> externalCameras) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildVideoPanel(externalCameras)),
          const SizedBox(width: 20),
          const SizedBox(width: 360, child: MediaGallery()),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout(List<CameraDevice> externalCameras) {
    return Column(
      children: [
        Expanded(flex: 3, child: _buildVideoPanel(externalCameras)),
        const Divider(height: 1, color: AppTheme.border),
        const Expanded(flex: 2, child: MediaGallery()),
      ],
    );
  }

  Widget _buildVideoPanel(List<CameraDevice> externalCameras) {
    return Column(
      children: [
        // 摄像头选择器
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: CameraSelector(
            cameras: externalCameras,
            activeIndex: _activeCameraIndex,
            isScanning: _isScanning,
            onSelect: _selectCamera,
            onRefresh: scanCameras,
          ),
        ),
        // 分辨率选择 + USB 检测面板（窄屏上下堆叠，宽屏并排）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final resolution = _buildResolutionSelector();
              const usb = USBPanel();
              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    resolution,
                    const SizedBox(height: 10),
                    usb,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: resolution),
                  const SizedBox(width: 10),
                  Expanded(flex: 3, child: usb),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // 视频预览
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: CameraPreviewPanel(
              controller: _cameraService.controller,
              activeCamera: _activeCamera,
              isInitialized: _cameraService.isInitialized,
              isRecording: _isRecording,
              isUvc: _activeCamera?.isUvc ?? false,
              uvcTextureId: _activeCamera?.isUvc ?? false
                  ? _uvcService.textureId
                  : null,
              uvcAspectRatio: _uvcService.previewAspectRatio,
              uvcDiag: _uvcService.diagnostics,
              onToggleFullscreen: () => setState(() => _isFullscreen = true),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ControlsBar(
          cameraReady: _activeCamera?.isUvc ?? false
              ? _uvcService.isPreviewing
              : _cameraService.isInitialized,
          isRecording: _isRecording,
          recordingSupported: _activeCamera != null,
          onTakePhoto: _onTakePhoto,
          onToggleRecord: _onToggleRecord,
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildResolutionSelector() {
    final uvcActive = _activeCamera?.isUvc ?? false;
    if (uvcActive) {
      // UVC 直连：列出设备真实支持的模式，用户手动选清晰度/帧率。
      return UvcModeSelector(
        modes: _uvcService.supportedModesList,
        current: _uvcService.activeMode,
        enabled: _uvcService.isPreviewing && !_isSwitchingMode,
        isLoading: _isSwitchingMode,
        onChanged: _changeUvcMode,
      );
    }
    return ResolutionSelector(
      value: _currentPreset,
      onChanged: _changeResolution,
      enabled: true,
    );
  }

  Future<void> _changeUvcMode(UvcCameraMode mode) async {
    if (_isSwitchingMode) return;
    setState(() => _isSwitchingMode = true);
    try {
      await _uvcService.switchMode(mode);
      setState(() {
        _statusKey = 'uvc_connected';
        _statusParams = {'label': _activeCamera?.label ?? ''};
        _statusType = 'active';
      });
      _snack('${l10n.t('uvc_mode')}: ${mode.label}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ ${l10n.t('uvc_mode_switch_failed')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSwitchingMode = false);
    }
  }
}

/// 分辨率下拉选择器。
/// 独立为 StatefulWidget 并给 DropdownButton 绑定稳定 GlobalKey，
/// 避免父组件因语言切换（notifyListeners）重建后 DropdownButton 内部
/// LayerLink 失稳、导致切换中文后首次点击无响应的经典问题。
class ResolutionSelector extends StatefulWidget {
  final ResolutionPreset value;
  final ValueChanged<ResolutionPreset> onChanged;
  final bool enabled;
  final String? disabledText;

  const ResolutionSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.disabledText,
  });

  @override
  State<ResolutionSelector> createState() => _ResolutionSelectorState();
}

class _ResolutionSelectorState extends State<ResolutionSelector> {
  final GlobalKey _dropdownKey = GlobalKey();

  static const _options = <ResolutionPreset>[
    ResolutionPreset.low,
    ResolutionPreset.medium,
    ResolutionPreset.high,
    ResolutionPreset.veryHigh,
    ResolutionPreset.ultraHigh,
    ResolutionPreset.max,
  ];

  String _label(ResolutionPreset p) {
    switch (p) {
      case ResolutionPreset.low:
        return '360p';
      case ResolutionPreset.medium:
        return '480p';
      case ResolutionPreset.high:
        return '720p';
      case ResolutionPreset.veryHigh:
        return '1080p';
      case ResolutionPreset.ultraHigh:
        return '4K';
      case ResolutionPreset.max:
        return 'Max';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleService>();
    final enabled = widget.enabled;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Text(
            l.t('resolution'),
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.accent2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ResolutionPreset>(
                key: _dropdownKey,
                isExpanded: true,
                value: enabled ? widget.value : null,
                dropdownColor: AppTheme.surface2,
                icon: const Icon(Icons.arrow_drop_down,
                    color: AppTheme.text2, size: 20),
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                hint: enabled
                    ? null
                    : (widget.disabledText != null
                        ? Text(
                            widget.disabledText!,
                            style: const TextStyle(
                              color: AppTheme.text2,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        : null),
                items: enabled
                    ? _options.map((p) {
                        return DropdownMenuItem<ResolutionPreset>(
                          value: p,
                          child: Text(_label(p)),
                        );
                      }).toList()
                    : null,
                onChanged: enabled
                    ? (preset) {
                        if (preset != null) widget.onChanged(preset);
                      }
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// UVC 预览模式（清晰度/帧率）下拉选择器。
/// 把设备真实支持的模式按分辨率×帧率降序排列，用户可手动权衡画质与流畅度。
class UvcModeSelector extends StatefulWidget {
  final List<UvcCameraMode> modes;
  final UvcCameraMode? current;
  final ValueChanged<UvcCameraMode> onChanged;
  final bool enabled;
  final bool isLoading;

  const UvcModeSelector({
    super.key,
    required this.modes,
    this.current,
    required this.onChanged,
    this.enabled = true,
    this.isLoading = false,
  });

  @override
  State<UvcModeSelector> createState() => _UvcModeSelectorState();
}

class _UvcModeSelectorState extends State<UvcModeSelector> {
  late List<UvcCameraMode> _sorted;

  @override
  void initState() {
    super.initState();
    _sort();
  }

  @override
  void didUpdateWidget(covariant UvcModeSelector old) {
    super.didUpdateWidget(old);
    if (old.modes != widget.modes || old.current != widget.current) _sort();
  }

  void _sort() {
    _sorted = List<UvcCameraMode>.from(widget.modes);
    _sorted.sort((a, b) {
      final pa = a.width * a.height;
      final pb = b.width * b.height;
      if (pa != pb) return pb.compareTo(pa);
      return b.fps.compareTo(a.fps);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleService>();
    final enabled = widget.enabled && !widget.isLoading;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Text(
            l.t('uvc_mode'),
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.accent2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: widget.isLoading
                ? const SizedBox(
                    height: 20,
                    child: Center(
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<UvcCameraMode>(
                      isExpanded: true,
                      value: widget.current != null &&
                              _sorted.contains(widget.current)
                          ? widget.current
                          : null,
                      dropdownColor: AppTheme.surface2,
                      icon: const Icon(Icons.arrow_drop_down,
                          color: AppTheme.text2, size: 20),
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      hint: Text(
                        l.t('uvc_resolution_auto'),
                        style: const TextStyle(
                          color: AppTheme.text2,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      items: _sorted.map((m) {
                        return DropdownMenuItem<UvcCameraMode>(
                          value: m,
                          child: Text(m.label),
                        );
                      }).toList(),
                      onChanged: enabled
                          ? (m) {
                              if (m != null) widget.onChanged(m);
                            }
                          : null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
