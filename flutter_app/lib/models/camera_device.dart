/// 摄像头设备数据模型
class CameraDevice {
  final String deviceId;
  final String label;
  final bool isBuiltin;
  final bool isExternal;
  bool usbConfirmed;
  String? usbVendor;
  String? usbProduct;
  String? facingMode;

  /// 视频源类型：'camera2' = 系统 Camera2 API（内置/外接）；'uvc' = UVC 直连（绕过 Camera2）
  final String source;

  /// UVC 源对应的原生 USB 设备 id（仅在 source=='uvc' 时有效）
  final int? uvcDeviceId;

  /// camera2 源对应的原生 CameraDescription 索引（仅在 source=='camera2' 时有效）
  final int? cam2Index;

  CameraDevice({
    required this.deviceId,
    required this.label,
    this.isBuiltin = false,
    this.isExternal = true,
    this.usbConfirmed = false,
    this.usbVendor,
    this.usbProduct,
    this.facingMode,
    this.source = 'camera2',
    this.uvcDeviceId,
    this.cam2Index,
  });

  /// 设备类型标识符，用于在 UI 层通过 LocaleService 翻译
  String get tagKey {
    if (usbConfirmed) return 'device_usb';
    if (isBuiltin) return 'device_builtin';
    if (isExternal) return 'device_external';
    return 'device_unknown';
  }

  String get tag {
    if (usbConfirmed) return '✅ USB';
    if (isBuiltin) return '💻 Built-in';
    if (isExternal) return '🔌 External';
    return '📷 Camera';
  }

  bool get isUvc => source == 'uvc';

  factory CameraDevice.fromMap(Map<String, dynamic> map) {
    final label = map['label'] as String? ?? '';
    final l = label.toLowerCase();
    final facingMode = map['facingMode'] as String?;

    // UVC / USB 摄像头关键词（优先级最高）
    final usbKeywords = [
      'usb', 'uvc', 'external', '外接',
      'lifecam', 'brio', 'c920', 'c930', 'c922', 'c270', 'c310', 'c525',
      'obsbot', 'insta360', 'elgato', 'avermedia',
    ];
    final isUsbByName = usbKeywords.any((k) => l.contains(k));

    // lens_direction 优先判断
    final isExternalByLens = facingMode == 'external';
    final isFrontOrBack = facingMode == 'front' || facingMode == 'back';

    // 内置摄像头关键词
    final builtinKeywords = [
      'facetime', 'isight', 'integrated webcam',
      'iphone', 'ipad', 'continuity', '内建', '内置',
    ];
    final isBuiltinByName = builtinKeywords.any((k) => l.contains(k));

    // USB 关键词 或 external lens → 肯定是外接
    // front/back lens 且不是 USB 名称 → 内置
    // 其他情况按名称判断
    final isUsb = isExternalByLens || isUsbByName;
    final isBuiltin = isUsb
        ? false
        : (isFrontOrBack || isBuiltinByName);

    return CameraDevice(
      deviceId: map['deviceId'] as String,
      label: label.isNotEmpty ? label : 'Camera ${map['index'] ?? '?'}',
      isBuiltin: isBuiltin,
      isExternal: !isBuiltin,
      facingMode: facingMode,
      usbConfirmed: isUsb,
      cam2Index: map['cam2Index'] as int?,
    );
  }

  @override
  String toString() => '$tag $label';
}
