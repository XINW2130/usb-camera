import 'dart:io' show Platform;
import '../models/usb_device_info.dart';

/// USB 设备检测服务
/// Android: 通过 usb_serial 检测 USB 设备
/// iOS: 有限支持（系统限制较多）
class USBService {
  List<USBDeviceInfo> _devices = [];
  List<USBDeviceInfo> get devices => _devices;
  bool _isScanning = false;
  bool get isScanning => _isScanning;

  /// 检测已连接的 USB 设备
  Future<List<USBDeviceInfo>> detectUSBDevices() async {
    _isScanning = true;
    _devices = [];

    try {
      if (Platform.isAndroid) {
        // Android 上尝试通过 usb_serial 检测
        // 实际集成时需要 platform channel 配合
        _devices = await _detectAndroidUSB();
      } else if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
        _devices = await _detectDesktopUSB();
      }
      // iOS 不支持底层 USB 访问
    } catch (e) {
      // 静默处理 - USB 检测是增强功能，不影响核心摄像头操作
      _devices = [];
    }

    _isScanning = false;
    return _devices;
  }

  /// Android USB 检测（简化实现）
  Future<List<USBDeviceInfo>> _detectAndroidUSB() async {
    // Android 完整的 USB 检测需要 platform channel
    // 此处返回空列表，实际项目需通过 MethodChannel 调用 Android USB API
    return [];
  }

  /// 桌面端 USB 检测（简化实现）
  Future<List<USBDeviceInfo>> _detectDesktopUSB() async {
    // 桌面端 USB 检测需要 platform channel 或原生 FFI
    return [];
  }

  /// 将 USB 设备与摄像头设备交叉匹配
  void matchUSBToCameras(List<dynamic> cameras) {
    if (_devices.isEmpty) return;

    for (final usbDev in _devices) {
      if (!usbDev.isLikelyCamera) continue;

      final usbNames = [
        usbDev.manufacturerName.toLowerCase(),
        usbDev.productName.toLowerCase(),
        USBDeviceInfo.vendorNameForId(usbDev.vendorId).toLowerCase(),
      ].where((s) => s.length > 1).toList();

      for (final cam in cameras) {
        if (cam.usbConfirmed) continue;

        final camLabel = (cam.label as String).toLowerCase();
        final matched = usbNames.any(
          (name) => name.length > 2 && camLabel.contains(name),
        );

        if (matched) {
          cam.usbConfirmed = true;
          cam.usbVendor =
              usbDev.manufacturerName.isNotEmpty ? usbDev.manufacturerName : USBDeviceInfo.vendorNameForId(usbDev.vendorId);
          cam.usbProduct = usbDev.productName;
          break;
        }
      }
    }
  }
}
