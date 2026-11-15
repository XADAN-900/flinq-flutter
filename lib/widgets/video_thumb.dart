import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/utils.dart';

/// Videonun ilk karesini küçük resim olarak gösterir (ızgaralar, sohbet).
/// Aynı anda en fazla 3 video çözülür; ekrandan çıkan küçük resim kaynağını bırakır.
class VideoThumb extends StatefulWidget {
  final String dataUrl;
  final bool showPlayIcon;
  const VideoThumb({super.key, required this.dataUrl, this.showPlayIcon = false});

  @override
  State<VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<VideoThumb> {
  static int _active = 0;
  static final List<Completer<void>> _waiting = [];

  VideoPlayerController? _c;
  bool _failed = false;

  static Future<void> _acquire() async {
    if (_active < 3) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    await c.future;
    _active++;
  }

  static void _release() {
    _active--;
    if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _acquire();
    VideoPlayerController? c;
    try {
      if (!mounted) return;
      final path = await MediaCache.file(widget.dataUrl);
      if (path == null || !mounted) {
        if (mounted) setState(() => _failed = true);
        return;
      }
      c = VideoPlayerController.file(File(path));
      await c.initialize();
      await c.setVolume(0);
      await c.seekTo(const Duration(milliseconds: 300));
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _c = c);
    } catch (_) {
      await c?.dispose();
      if (mounted) setState(() => _failed = true);
    } finally {
      _release();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    Widget child;
    if (c != null && c.value.isInitialized && c.value.size.width > 0) {
      child = FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
      );
    } else {
      child = Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF1B1F2A), Color(0xFF2E3445)]),
        ),
        child: Center(
          child: _failed
              ? const Icon(Icons.videocam_off_rounded, color: Colors.white38, size: 28)
              : const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38)),
        ),
      );
    }
    if (!widget.showPlayIcon) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        const Center(
          child: CircleAvatar(
            radius: 22,
            backgroundColor: Colors.black38,
            child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
          ),
        ),
      ],
    );
  }
}
