import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// USB 设备信息模型
class UsbDeviceInfo {
  final String deviceName;
  final int vendorId;
  final int productId;
  final String manufacturerName;
  final String productName;
  final String serialNumber;
  final int deviceClass;
  final int deviceSubclass;
  final int interfaceCount;
  final bool isUvc;
  final bool isCamera;
  final bool hasPermission;
  final List<UsbInterfaceInfo> interfaces;

  UsbDeviceInfo({
    required this.deviceName,
    required this.vendorId,
    required this.productId,
    required this.manufacturerName,
    required this.productName,
    required this.serialNumber,
    required this.deviceClass,
    required this.deviceSubclass,
    required this.interfaceCount,
    required this.isUvc,
    required this.isCamera,
    required this.hasPermission,
    required this.interfaces,
  });

  factory UsbDeviceInfo.fromMap(Map<String, dynamic> map) {
    final ifaces = (map['interfaces'] as List<dynamic>?)
            ?.map((e) => UsbInterfaceInfo.fromMap(Map.from(e)))
            .toList() ??
        [];

    return UsbDeviceInfo(
      deviceName: map['deviceName'] as String? ?? '',
      vendorId: map['vendorId'] as int? ?? 0,
      productId: map['productId'] as int? ?? 0,
      manufacturerName: map['manufacturerName'] as String? ?? 'Unknown',
      productName: map['productName'] as String? ?? 'Unknown',
      serialNumber: map['serialNumber'] as String? ?? 'N/A',
      deviceClass: map['deviceClass'] as int? ?? 0,
      deviceSubclass: map['deviceSubclass'] as int? ?? 0,
      interfaceCount: map['interfaceCount'] as int? ?? 0,
      isUvc: map['isUvc'] as bool? ?? false,
      isCamera: map['isCamera'] as bool? ?? false,
      hasPermission: map['hasPermission'] as bool? ?? false,
      interfaces: ifaces,
    );
  }

  String get vendorHex => '0x${vendorId.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  String get productHex => '0x${productId.toRadixString(16).toUpperCase().padLeft(4, '0')}';

  @override
  String toString() => '$productName ($vendorHex:$productHex) [UVC=$isUvc]';
}

class UsbInterfaceInfo {
  final int index;
  final int interfaceClass;
  final int interfaceSubclass;
  final int interfaceProtocol;

  UsbInterfaceInfo({
    required this.index,
    required this.interfaceClass,
    required this.interfaceSubclass,
    required this.interfaceProtocol,
  });

  factory UsbInterfaceInfo.fromMap(Map<String, dynamic> map) {
    return UsbInterfaceInfo(
      index: map['index'] as int? ?? 0,
      interfaceClass: map['interfaceClass'] as int? ?? 0,
      interfaceSubclass: map['interfaceSubclass'] as int? ?? 0,
      interfaceProtocol: map['interfaceProtocol'] as int? ?? 0,
    );
  }
}

/// 设备信息模型
class AndroidDeviceInfo {
  final int sdkVersion;
  final String manufacturer;
  final String model;
  final String brand;
  final String device;
  final bool hasUsbHost;
  final bool hasUsbAccessory;
  final bool hasCamera;
  final bool hasCameraExternal;

  AndroidDeviceInfo({
    required this.sdkVersion,
    required this.manufacturer,
    required this.model,
    required this.brand,
    required this.device,
    required this.hasUsbHost,
    required this.hasUsbAccessory,
    required this.hasCamera,
    required this.hasCameraExternal,
  });

  factory AndroidDeviceInfo.fromMap(Map<String, dynamic> map) {
    return AndroidDeviceInfo(
      sdkVersion: map['sdkVersion'] as int? ?? 0,
      manufacturer: map['manufacturer'] as String? ?? 'Unknown',
      model: map['model'] as String? ?? 'Unknown',
      brand: map['brand'] as String? ?? 'Unknown',
      device: map['device'] as String? ?? 'Unknown',
      hasUsbHost: map['hasUsbHost'] as bool? ?? false,
      hasUsbAccessory: map['hasUsbAccessory'] as bool? ?? false,
      hasCamera: map['hasCamera'] as bool? ?? false,
      hasCameraExternal: map['hasCameraExternal'] as bool? ?? false,
    );
  }
}

/// USB 设备检测服务 — 通过平台通道与 Android USB Manager 通信
class UsbHostService {
  static const _channel = MethodChannel('com.example.usb_camera_monitor/usb');

  /// 扫描所有已连接的 USB 设备
  Future<List<UsbDeviceInfo>> detectUsbDevices() async {
    try {
      final result = await _channel.invokeMethod('detectUsbDevices');
      if (result == null) return [];
      final list = result as List<dynamic>;
      return list
          .map((e) => UsbDeviceInfo.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('[UsbHostService] detectUsbDevices error: $e');
      return [];
    }
  }

  /// 请求 USB 设备权限
  Future<bool> requestUsbPermission(String deviceName) async {
    try {
      final result = await _channel.invokeMethod('requestUsbPermission', {
        'deviceName': deviceName,
      });
      return result.toString().startsWith('granted') ||
          result.toString().startsWith('already_granted');
    } catch (e) {
      debugPrint('[UsbHostService] requestUsbPermission error: $e');
      return false;
    }
  }

  /// 请求摄像头权限
  Future<bool> requestCameraPermission() async {
    try {
      final result = await _channel.invokeMethod('requestCameraPermission');
      return result == true;
    } catch (e) {
      debugPrint('[UsbHostService] requestCameraPermission error: $e');
      return false;
    }
  }

  /// 获取 Android 设备信息
  Future<AndroidDeviceInfo?> getDeviceInfo() async {
    try {
      final result = await _channel.invokeMethod('getDeviceInfo');
      if (result == null) return null;
      return AndroidDeviceInfo.fromMap(Map<String, dynamic>.from(result));
    } catch (e) {
      debugPrint('[UsbHostService] getDeviceInfo error: $e');
      return null;
    }
  }
}
