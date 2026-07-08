import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 拍照/录像控制按钮组。
/// 改为回调方式，由父组件（CameraScreen）决定走 Camera2 还是 UVC 管线。
class ControlsBar extends StatefulWidget {
  final bool cameraReady;
  final bool isRecording;
  final bool recordingSupported;
  final VoidCallback? onTakePhoto;
  final VoidCallback? onToggleRecord;

  const ControlsBar({
    super.key,
    required this.cameraReady,
    required this.isRecording,
    this.recordingSupported = true,
    this.onTakePhoto,
    this.onToggleRecord,
  });

  @override
  State<ControlsBar> createState() => _ControlsBarState();
}

class _ControlsBarState extends State<ControlsBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _recPulseController;

  @override
  void initState() {
    super.initState();
    _recPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void didUpdateWidget(covariant ControlsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording != oldWidget.isRecording) {
      if (widget.isRecording) {
        _recPulseController.repeat(reverse: true);
      } else {
        _recPulseController.stop();
      }
    }
  }

  @override
  void dispose() {
    _recPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photoDisabled = !widget.cameraReady;
    final recordDisabled = !widget.recordingSupported ||
        (!widget.cameraReady && !widget.isRecording);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(width: 20),
        // 拍照按钮
        GestureDetector(
          onTap: photoDisabled ? null : widget.onTakePhoto,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                color: photoDisabled ? AppTheme.border : AppTheme.surface2,
                width: 4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: photoDisabled ? 0.05 : 0.15),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Icon(
              Icons.camera_alt,
              size: 22,
              color: photoDisabled ? AppTheme.text2 : Colors.black87,
            ),
          ),
        ),
        const SizedBox(width: 24),
        // 录像按钮
        GestureDetector(
          onTap: recordDisabled ? null : widget.onToggleRecord,
          child: AnimatedBuilder(
            animation: _recPulseController,
            builder: (context, child) {
              final pulseValue = widget.isRecording
                  ? 1.0 + _recPulseController.value * 0.3
                  : 1.0;
              return Transform.scale(
                scale: pulseValue,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isRecording
                        ? Colors.white
                        : AppTheme.danger,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.danger.withValues(
                          alpha: recordDisabled ? 0.1 : 0.4,
                        ),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.isRecording ? Icons.stop : Icons.fiber_manual_record,
                    size: 30,
                    color: widget.isRecording ? AppTheme.danger : Colors.white,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 20),
      ],
    );
  }
}
