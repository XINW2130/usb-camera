import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';
import '../models/media_item.dart';

/// 媒体预览（Lightbox）
class LightboxView extends StatefulWidget {
  final MediaItem item;

  const LightboxView({super.key, required this.item});

  @override
  State<LightboxView> createState() => _LightboxViewState();
}

class _LightboxViewState extends State<LightboxView> {
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    if (widget.item.type == MediaType.video) {
      _videoController = VideoPlayerController.file(File(widget.item.filePath))
        ..initialize().then((_) => setState(() {}))
        ..play()
        ..setLooping(true);
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.item.fileName,
          style: const TextStyle(fontSize: 14, color: AppTheme.text2),
        ),
      ),
      body: Center(
        child: widget.item.type == MediaType.photo
            ? InteractiveViewer(
                child: Image.file(
                  File(widget.item.filePath),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image,
                    size: 64,
                    color: AppTheme.text2,
                  ),
                ),
              )
            : _videoController != null && _videoController!.value.isInitialized
                ? AspectRatio(
                    aspectRatio: _videoController!.value.aspectRatio,
                    child: VideoPlayer(_videoController!),
                  )
                : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
