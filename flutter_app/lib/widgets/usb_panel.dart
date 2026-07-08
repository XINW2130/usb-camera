import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/locale_service.dart';
import '../services/usb_host_service.dart';

/// USB 设备检测面板 — 通过 Android USB Manager 检测 UVC 摄像头
class USBPanel extends StatefulWidget {
  const USBPanel({super.key});

  @override
  State<USBPanel> createState() => _USBPanelState();
}

class _USBPanelState extends State<USBPanel> {
  final _usbHostService = UsbHostService();
  bool _isScanning = false;
  int _usbDeviceCount = 0;
  int _uvcDeviceCount = 0;
  int _cameraDeviceCount = 0;
  bool _hasPermissionIssue = false;
  String? _deviceNameToRequest;

  List<UsbDeviceInfo> _allDevices = [];
  AndroidDeviceInfo? _deviceInfo;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
    // 进入 app 时预先执行一次 USB 检测，无需用户手动点按钮。
    _scanUSB();
  }

  Future<void> _loadDeviceInfo() async {
    final info = await _usbHostService.getDeviceInfo();
    if (mounted) setState(() => _deviceInfo = info);
  }

  Future<void> _scanUSB() async {
    setState(() => _isScanning = true);

    // 检测 USB 设备
    final devices = await _usbHostService.detectUsbDevices();

    if (!mounted) return;

    final uvcDevices = devices.where((d) => d.isUvc).toList();
    final cameraDevices = devices.where((d) => d.isCamera).toList();
    final needsPermission = devices.where((d) => d.isCamera && !d.hasPermission).toList();

    setState(() {
      _isScanning = false;
      _allDevices = devices;
      _usbDeviceCount = devices.length;
      _uvcDeviceCount = uvcDevices.length;
      _cameraDeviceCount = cameraDevices.length;
      _hasPermissionIssue = needsPermission.isNotEmpty;
      _deviceNameToRequest = needsPermission.isNotEmpty ? needsPermission.first.deviceName : null;
    });
  }

  Future<void> _requestPermission() async {
    if (_deviceNameToRequest == null) return;
    setState(() => _isScanning = true);

    final granted = await _usbHostService.requestUsbPermission(_deviceNameToRequest!);
    if (!mounted) return;

    // 权限请求后重新扫描
    final devices = await _usbHostService.detectUsbDevices();
    if (!mounted) return;

    final cameraDevices = devices.where((d) => d.isCamera).toList();

    setState(() {
      _isScanning = false;
      _allDevices = devices;
      _usbDeviceCount = devices.length;
      _cameraDeviceCount = cameraDevices.length;
      _hasPermissionIssue = !granted && cameraDevices.any((d) => !d.hasPermission);
      _deviceNameToRequest = _hasPermissionIssue && cameraDevices.isNotEmpty
          ? cameraDevices.firstWhere((d) => !d.hasPermission, orElse: () => cameraDevices.first).deviceName
          : null;
    });

    if (granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('USB permission granted — please rescan cameras'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  Color _getBorderColor() {
    if (_uvcDeviceCount > 0) return AppTheme.success;
    if (_cameraDeviceCount > 0) return AppTheme.warning;
    if (_usbDeviceCount > 0) return AppTheme.accent2;
    return AppTheme.border;
  }

  Color _getBgColor() {
    if (_uvcDeviceCount > 0) return AppTheme.success.withValues(alpha: 0.08);
    if (_cameraDeviceCount > 0) return AppTheme.warning.withValues(alpha: 0.08);
    if (_usbDeviceCount > 0) return AppTheme.accent.withValues(alpha: 0.06);
    return AppTheme.surface2;
  }

  String _statusText(LocaleService l) {
    if (_isScanning) return l.t('usb_scanning');
    if (_hasPermissionIssue) {
      return l.isZh ? '需授权 USB 设备访问' : 'USB permission needed';
    }
    if (_uvcDeviceCount > 0) {
      return l.t('usb_confirmed',
          params: {'n': _uvcDeviceCount.toString()});
    }
    if (_cameraDeviceCount > 0) {
      return l.isZh
          ? '发现 $_cameraDeviceCount 个摄像头设备(UVC=$_uvcDeviceCount)'
          : '$_cameraDeviceCount cam device(s) (UVC=$_uvcDeviceCount)';
    }
    if (_usbDeviceCount > 0) {
      return l.t('usb_no_match',
          params: {'n': _usbDeviceCount.toString()});
    }
    return l.t('usb_not_detected');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleService>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _getBgColor(),
        border: Border.all(color: _getBorderColor()),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        children: [
          // 状态图标
          Icon(
            _hasPermissionIssue
                ? Icons.lock
                : _uvcDeviceCount > 0
                    ? Icons.check_circle
                    : _cameraDeviceCount > 0
                        ? Icons.warning_amber_rounded
                        : _usbDeviceCount > 0
                            ? Icons.usb
                            : Icons.search,
            size: 16,
            color: _hasPermissionIssue
                ? AppTheme.warning
                : _uvcDeviceCount > 0
                    ? AppTheme.success
                    : _cameraDeviceCount > 0
                        ? AppTheme.warning
                        : AppTheme.text2,
          ),
          const SizedBox(width: 6),
          // 状态文本
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusText(l),
                  style: TextStyle(
                    fontSize: 13,
                    color: _hasPermissionIssue
                        ? AppTheme.warning
                        : _uvcDeviceCount > 0
                            ? AppTheme.success
                            : _cameraDeviceCount > 0
                                ? AppTheme.warning
                                : AppTheme.text2,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
                // 设备诊断信息
                if (_deviceInfo != null)
                  Text(
                    '${_deviceInfo!.brand} ${_deviceInfo!.model} | '
                    'SDK ${_deviceInfo!.sdkVersion} | '
                    'USB Host: ${_deviceInfo!.hasUsbHost ? "✓" : "✗"} | '
                    'ExtCam: ${_deviceInfo!.hasCameraExternal ? "✓" : "✗"}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.text2,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
              ],
            ),
          ),
          // 按钮
          if (_hasPermissionIssue)
            InkWell(
              onTap: _isScanning ? null : _requestPermission,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.warning,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  l.isZh ? '授权' : 'Grant',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            InkWell(
              onTap: _isScanning ? null : _scanUSB,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: _isScanning
                      ? [
                          BoxShadow(
                            color: AppTheme.accent.withValues(alpha: 0.4),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  _isScanning ? l.t('usb_scanning_btn') : l.t('detection'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _isScanning ? Colors.white70 : Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
