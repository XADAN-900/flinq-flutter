import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';

/// Gönderi fotoğrafı: medya ancak ekranda gösterileceği zaman indirilir.
class PostImage extends StatefulWidget {
  final String postId;
  final BoxFit fit;
  final int? cacheWidth;
  const PostImage({super.key, required this.postId, this.fit = BoxFit.cover, this.cacheWidth});

  @override
  State<PostImage> createState() => _PostImageState();
}

class _PostImageState extends State<PostImage> {
  late Future<Uint8List?> _f = context.read<AppState>().postImage(widget.postId);

  @override
  void didUpdateWidget(covariant PostImage old) {
    super.didUpdateWidget(old);
    if (old.postId != widget.postId) _f = context.read<AppState>().postImage(widget.postId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _f,
      builder: (context, snap) {
        final b = snap.data;
        if (b != null) {
          return Image.memory(
            b,
            fit: widget.fit,
            gaplessPlayback: true,
            cacheWidth: widget.cacheWidth,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => _box(const Icon(Icons.broken_image_outlined, color: Colors.white54)),
          );
        }
        if (snap.connectionState == ConnectionState.done) {
          return _box(const Icon(Icons.broken_image_outlined, color: Colors.white54));
        }
        return _box(const SizedBox(
            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38)));
      },
    );
  }

  Widget _box(Widget child) => Container(
        color: const Color(0xFF1B1F2A),
        alignment: Alignment.center,
        child: child,
      );
}
