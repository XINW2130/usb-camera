/// 媒体文件数据模型
enum MediaType { photo, video }

class MediaItem {
  final String id;
  final MediaType type;
  final String filePath;
  final int timestamp;
  final int? fileSize;
  String? mimeType;

  MediaItem({
    required this.id,
    required this.type,
    required this.filePath,
    required this.timestamp,
    this.fileSize,
    this.mimeType,
  });

  String get extension {
    if (type == MediaType.video) {
      return (mimeType != null && mimeType!.contains('mp4')) ? 'mp4' : 'webm';
    }
    return 'jpg';
  }

  String get fileName =>
      'USB_Cam_${DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}.$extension';

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'filePath': filePath,
        'timestamp': timestamp,
        'fileSize': fileSize,
        'mimeType': mimeType,
      };

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
        id: json['id'] as String,
        type: json['type'] == 'video' ? MediaType.video : MediaType.photo,
        filePath: json['filePath'] as String,
        timestamp: json['timestamp'] as int,
        fileSize: json['fileSize'] as int?,
        mimeType: json['mimeType'] as String?,
      );
}
