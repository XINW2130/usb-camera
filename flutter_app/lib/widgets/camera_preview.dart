import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart' as cam;
import '../theme/app_theme.dart';
import '../models/camera_device.dart';
import '../services/locale_service.dart';

/// 摄像头视频预览组件
class CameraPreviewPanel extends StatelessWidget {
  final cam.CameraController? controller;
  final CameraDevice? activeCamera;
  final bool isInitialized;
  final bool isRecording;
  final Duration? recordingDuration;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;

  /// UVC 直连纹理 id（当 isUvc 为 true 且已打开时有效）
  final int? uvcTextureId;
  final bool isUvc;
  final double uvcAspectRatio;

  /// UVC 实时诊断信息（直接画在预览上，无需 adb 调试）
  final ValueListenable<String>? uvcDiag;

  const CameraPreviewPanel({
    super.key,
    required this.controller,
    this.activeCamera,
    required this.isInitialized,
    required this.isRecording,
    this.recordingDuration,
    this.isFullscreen = false,
    this.onToggleFullscreen,
    this.uvcTextureId,
    this.isUvc = false,
    this.uvcAspectRatio = 0.0,
    this.uvcDiag,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleService>();
    final radius = isFullscreen ? 0.0 : AppTheme.radius;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(radius),
        border: isFullscreen
            ? Border.all(color: Colors.transparent, width: 0)
            : Border.all(color: AppTheme.border),
        boxShadow: isFullscreen
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 视频预览
            if (isUvc && uvcTextureId != null)
              _UvcVideoPreview(
                textureId: uvcTextureId!,
                isFullscreen: isFullscreen,
                aspectRatio: uvcAspectRatio,
              )
            else if (isInitialized && controller != null)
              _CameraVideoPreview(controller: controller!, isFullscreen: isFullscreen)
            else
              _buildNoCameraOverlay(l),

            // UVC 诊断：左下角感叹号按钮切换调试面板显示/隐藏
            if (isUvc && uvcTextureId != null && uvcDiag != null)
              _UvcDiagToggle(diag: uvcDiag!, isFullscreen: isFullscreen),

            // 录像指示器
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              top: isRecording ? (isFullscreen ? 40 : 16) : 0,
              right: 16,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: isRecording ? 1.0 : 0.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PulsingDot(),
                      const SizedBox(width: 8),
                      const Text(
                        'REC',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 全屏按钮
            Positioned(
              bottom: isFullscreen ? 24 : 16,
              right: isFullscreen ? 24 : 16,
              child: _FullscreenButton(
                isFullscreen: isFullscreen,
                onTap: onToggleFullscreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoCameraOverlay(LocaleService l) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam, size: 64, color: AppTheme.text2),
          const SizedBox(height: 16),
          Text(
            l.t('no_camera_title'),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.accent2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l.t('no_camera_desc'),
            style: const TextStyle(fontSize: 13, color: AppTheme.text2),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 录像闪烁红点
class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.danger,
          boxShadow: [
            BoxShadow(
              color: AppTheme.danger.withValues(alpha: 0.6),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}

/// 相机预览 Widget
class _CameraVideoPreview extends StatelessWidget {
  final cam.CameraController controller;
  final bool isFullscreen;

  const _CameraVideoPreview({required this.controller, this.isFullscreen = false});

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    if (isFullscreen) {
      // 全屏时视频填满整个区域
      return Positioned.fill(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.previewSize?.width ?? 640,
            height: controller.value.previewSize?.height ?? 480,
            child: cam.CameraPreview(controller),
          ),
        ),
      );
    }
    // 非全屏：contain 完整显示画面、不裁切，超出部分 letterbox 留黑边。
    final ar = controller.value.aspectRatio;
    return FittedBox(
      fit: BoxFit.contain,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: ar > 0 ? 1000 : null,
        height: ar > 0 ? 1000 / ar : null,
        child: cam.CameraPreview(controller),
      ),
    );
  }
}

/// UVC 直连预览 Widget（原生 Texture 渲染）
class _UvcVideoPreview extends StatelessWidget {
  final int textureId;
  final bool isFullscreen;
  final double aspectRatio;

  const _UvcVideoPreview({
    required this.textureId,
    this.isFullscreen = false,
    this.aspectRatio = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final texture = Texture(
      textureId: textureId,
      filterQuality: FilterQuality.none,
    );
    final hasRatio = aspectRatio > 0;
    if (isFullscreen) {
      // 全屏时用 cover 填满区域（避免纹理拉伸变形）
      return Positioned.fill(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: hasRatio ? 1000 : null,
            height: hasRatio ? 1000 / aspectRatio : null,
            child: texture,
          ),
        ),
      );
    }
    if (hasRatio) {
      // contain：完整显示画面、不裁切，超出部分 letterbox 留黑边（上下或左右）。
      return FittedBox(
        fit: BoxFit.contain,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 1000,
          height: 1000 / aspectRatio,
          child: texture,
        ),
      );
    }
    return SizedBox.expand(child: texture);
  }
}

/// UVC 诊断浮层：左下角感叹号按钮点击切换显示/隐藏调试面板。
class _UvcDiagToggle extends StatefulWidget {
  final ValueListenable<String> diag;
  final bool isFullscreen;

  const _UvcDiagToggle({required this.diag, this.isFullscreen = false});

  @override
  State<_UvcDiagToggle> createState() => _UvcDiagToggleState();
}

class _UvcDiagToggleState extends State<_UvcDiagToggle> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final double baseBottom = widget.isFullscreen ? 16 : 8;
    return Stack(
      children: [
        if (_show)
          Positioned(
            left: 8,
            right: widget.isFullscreen ? 16 : null,
            bottom: baseBottom + 44,
            child: ValueListenableBuilder<String>(
              valueListenable: widget.diag,
              builder: (_, text, __) => Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints: const BoxConstraints(maxWidth: 340),
                child: Text(
                  text.isEmpty ? 'UVC: waiting…' : text,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: 8,
          bottom: baseBottom,
          child: GestureDetector(
            onTap: () => setState(() => _show = !_show),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _show
                    ? AppTheme.accent.withValues(alpha: 0.8)
                    : Colors.black.withValues(alpha: 0.55),
                border: Border.all(
                  color: _show
                      ? AppTheme.accent
                      : Colors.white.withValues(alpha: 0.15),
                ),
              ),
              child: const Icon(
                Icons.error_outline,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 全屏切换按钮
class _FullscreenButton extends StatelessWidget {
  final bool isFullscreen;
  final VoidCallback? onTap;

  const _FullscreenButton({required this.isFullscreen, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isFullscreen
              ? AppTheme.accent.withValues(alpha: 0.6)
              : Colors.black.withValues(alpha: 0.55),
          border: Border.all(
            color: isFullscreen
                ? AppTheme.accent
                : Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Icon(
          isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}
