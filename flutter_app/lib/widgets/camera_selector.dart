import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/camera_device.dart';
import '../services/locale_service.dart';

/// 摄像头选择器组件（仅显示外接摄像头）
class CameraSelector extends StatefulWidget {
  final List<CameraDevice> cameras;
  final int? activeIndex;
  final bool isScanning;
  final ValueChanged<int> onSelect;
  final VoidCallback onRefresh;

  const CameraSelector({
    super.key,
    required this.cameras,
    required this.activeIndex,
    required this.isScanning,
    required this.onSelect,
    required this.onRefresh,
  });

  @override
  State<CameraSelector> createState() => _CameraSelectorState();
}

class _CameraSelectorState extends State<CameraSelector> {
  final GlobalKey _dropdownKey = GlobalKey();
  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleService>();

    return Row(
      children: [
        Text(
          l.t('camera_label'),
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.accent2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppTheme.surface2,
              border: Border.all(color: AppTheme.accent),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                key: _dropdownKey,
                isExpanded: true,
                value: widget.activeIndex != null &&
                        widget.activeIndex! < widget.cameras.length
                    ? widget.activeIndex
                    : null,
                hint: Text(
                  widget.isScanning ? l.t('scanning') : l.t('select_camera'),
                  style: const TextStyle(
                    color: AppTheme.text2,
                    fontSize: 14,
                  ),
                ),
                dropdownColor: AppTheme.surface2,
                icon: const Icon(Icons.arrow_drop_down, color: AppTheme.text2),
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                items: widget.cameras.asMap().entries.map((entry) {
                  final cam = entry.value;
                  return DropdownMenuItem<int>(
                    value: entry.key,
                    child: Text(
                      '${l.t(cam.tagKey)} ${cam.label}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (index) {
                  if (index != null) widget.onSelect(index);
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // 刷新按钮
        _SmallButton(
          icon: Icons.refresh,
          onTap: widget.isScanning ? null : widget.onRefresh,
          tooltip: l.t('refresh_tooltip'),
        ),
      ],
    );
  }
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback? onTap;
  final String tooltip;

  const _SmallButton({
    required this.icon,
    this.isActive = false,
    this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isActive ? AppTheme.accent : AppTheme.surface2,
            border: Border.all(
              color: isActive ? AppTheme.accent : AppTheme.border,
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Icon(icon, size: 18, color: AppTheme.text),
        ),
      ),
    );
  }
}
