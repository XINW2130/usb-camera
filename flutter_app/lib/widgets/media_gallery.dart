import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/media_gallery_service.dart';
import '../services/locale_service.dart';
import '../models/media_item.dart';
import 'lightbox_view.dart';

/// 媒体库侧面板
class MediaGallery extends StatelessWidget {
  const MediaGallery({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleService>();
    return Consumer<MediaGalleryService>(
      builder: (context, gallery, _) {
        return Container(
          margin: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppTheme.border, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l.t('gallery_title'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.text,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.surface2,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${gallery.count}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.text2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 内容
              Expanded(
                child: gallery.count == 0
                    ? _buildEmptyState(context)
                    : _buildGrid(gallery, context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l = context.watch<LocaleService>();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_open, size: 48, color: AppTheme.text2),
          const SizedBox(height: 10),
          Text(
            l.t('gallery_empty'),
            style: const TextStyle(color: AppTheme.text2, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(MediaGalleryService gallery, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 4 / 3,
        ),
        itemCount: gallery.count,
        itemBuilder: (context, index) {
          final item = gallery.items[index];
          return _GalleryItem(
            key: ValueKey(item.id),
            item: item,
            onTap: () => _openItem(context, item),
            onDelete: () => _deleteItem(context, gallery, item),
            onSave: () => _saveToLocal(context, gallery, item),
          );
        },
      ),
    );
  }

  void _openItem(BuildContext context, MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LightboxView(item: item),
      ),
    );
  }

  void _saveToLocal(
      BuildContext context, MediaGalleryService gallery, MediaItem item) async {
    final l = context.read<LocaleService>();
    try {
      final ok = await gallery.saveToLocal(item);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? l.t('saved_local') : l.t('save_failed')),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l.t('save_failed')}: $e')),
        );
      }
    }
  }

  void _deleteItem(BuildContext context, MediaGalleryService gallery, MediaItem item) async {
    final l = context.read<LocaleService>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(l.t('delete_confirm_title')),
        content: Text(l.t('delete_confirm_content')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.t('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.t('delete'),
                style: const TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await gallery.delete(item.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.t('deleted'))),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l.t('delete_failed')}: $e')),
          );
        }
      }
    }
  }
}

/// 库中的单个媒体项
class _GalleryItem extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onSave;

  const _GalleryItem({
    super.key,
    required this.item,
    required this.onTap,
    required this.onDelete,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleService>();
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 仅"预览区"可点击打开大图（不与底部操作栏的手势冲突）
            Positioned.fill(
              child: GestureDetector(
                onTap: onTap,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 缩略图
                    item.type == MediaType.photo
                        ? Image.file(
                            File(item.filePath),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image, color: AppTheme.text2),
                            ),
                          )
                        : Container(
                            color: Colors.black,
                            child: const Center(
                              child: Icon(
                                Icons.play_circle_fill,
                                size: 48,
                                color: AppTheme.text2,
                              ),
                            ),
                          ),
                    // 类型标签
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: item.type == MediaType.video
                              ? AppTheme.danger.withValues(alpha: 0.85)
                              : Colors.black54,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          item.type == MediaType.photo ? '📷' : '🎬',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 底部操作栏（独立节点，点击删除/分享不会被父级"打开大图"手势吞掉）
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.black54,
                child: Row(
                  children: [
                    Expanded(
                      child: IconButton(
                        icon: const Icon(Icons.download,
                            size: 18, color: Colors.white70),
                        tooltip: l.t('save_local'),
                        onPressed: onSave,
                      ),
                    ),
                    Expanded(
                      child: IconButton(
                        icon: const Icon(Icons.delete,
                            size: 18, color: AppTheme.danger2),
                        tooltip: l.t('delete'),
                        onPressed: onDelete,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
