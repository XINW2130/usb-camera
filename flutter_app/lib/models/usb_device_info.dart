/// USB 设备数据模型
class USBDeviceInfo {
  final int vendorId;
  final int productId;
  final String productName;
  final String manufacturerName;
  final String? serialNumber;
  final bool isLikelyCamera;

  USBDeviceInfo({
    required this.vendorId,
    required this.productId,
    required this.productName,
    required this.manufacturerName,
    this.serialNumber,
    this.isLikelyCamera = false,
  });

  /// 常见的 USB 摄像头厂商
  static String vendorNameForId(int vid) {
    const vendors = <int, String>{
      0x046d: 'Logitech', 0x045e: 'Microsoft', 0x0bda: 'Realtek',
      0x04f2: 'Chicony', 0x17ef: 'Lenovo', 0x05a3: 'ARC',
      0x041e: 'Creative', 0x04e8: 'Samsung', 0x093a: 'Pixart',
      0x1bcf: 'Sunplus', 0x05ac: 'Apple', 0x04ca: 'Lite-On',
      0x2232: 'Silicon Motion', 0x058f: 'Alcor', 0x1908: 'GEMBIRD',
      0x1e4e: 'Cubeternet', 0x0c45: 'Microdia', 0x05a9: 'OmniVision',
      0xeb1a: 'eMPIA', 0x06f8: 'Guillemot', 0x0ac8: 'Z-Star',
      0x0c76: 'JMTek', 0x1b3f: 'Generalplus', 0x0b05: 'ASUS',
      0x056e: 'Elecom', 0x03f0: 'HP', 0x2bd9: 'Anker',
      0x32ed: 'AverMedia', 0x1532: 'Razer', 0x18a5: 'Verenatech',
      0x32f0: 'NexiGo', 0x328f: 'DEPSTECH', 0x2b16: 'OBSBOT',
      0x152d: 'JMicron', 0x04b4: 'Cypress', 0x05e3: 'Genesys Logic',
    };
    return vendors[vid] ?? '';
  }
}
