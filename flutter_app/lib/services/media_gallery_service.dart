import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/media_item.dart';

/// 媒体库管理服务
class MediaGalleryService extends ChangeNotifier {
  final List<MediaItem> _items = [];
  List<MediaItem> get items => List.unmodifiable(_items);
  int get count => _items.length;

  /// 添加媒体项
  void add(MediaItem item) {
    _items.insert(0, item);
    notifyListeners();
  }

  /// 删除媒体项。
  /// 先更新内存列表并通知 UI，再尽力删除磁盘文件；
  /// 即使文件删除失败（已不存在/无权限），列表也已移除，保证界面即时刷新。
  Future<void> delete(String id) async {
    var idx = _items.indexWhere((m) => m.id == id);
    // 兜底：万一 id 匹配不上，再按文件路径找一次。
    if (idx == -1) {
      idx = _items.indexWhere((m) => m.filePath == id);
    }
    if (idx == -1) return;

    final item = _items[idx];
    _items.removeAt(idx);
    notifyListeners();

    try {
      final file = File(item.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // 文件删除失败不影响列表移除，忽略。
    }
  }

  /// 清空媒体库
  Future<void> clearAll() async {
    for (final item in _items) {
      final file = File(item.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    _items.clear();
    notifyListeners();
  }

  /// 按 ID 查找
  MediaItem? findById(String id) {
    try {
      return _items.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 把媒体文件另存到本机公共目录（照片 → Pictures、视频 → Movies），
  /// 这样系统相册 / 文件管理器就能看到，即“持久化到本地”。
  /// 注意：media_store_plus 的 saveFile 会删除传入的临时文件，
  /// 所以这里先复制原文件再传入，避免误删 App 内部的原始文件。
  bool _mediaStoreReady = false;
  Future<bool> saveToLocal(MediaItem item) async {
    try {
      // 懒初始化 MediaStore（仅首次保存时），避免影响 App 启动。
      if (!_mediaStoreReady) {
        MediaStore.appFolder = 'USB_Camera';
        await MediaStore.ensureInitialized();
        _mediaStoreReady = true;
      }

      final original = File(item.filePath);
      if (!await original.exists()) return false;

      final tempDir = await getTemporaryDirectory();
      final tempFile =
          await original.copy(p.join(tempDir.path, 'export_${item.fileName}'));

      final dirType =
          item.type == MediaType.video ? DirType.video : DirType.photo;
      final dirName =
          item.type == MediaType.video ? DirName.movies : DirName.pictures;

      final info = await MediaStore().saveFile(
        tempFilePath: tempFile.path,
        dirType: dirType,
        dirName: dirName,
      );
      return info != null;
    } catch (_) {
      return false;
    }
  }
}
