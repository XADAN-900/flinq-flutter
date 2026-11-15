import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/utils.dart';

/// Videonun bir karesini küçük resim olarak gösterir (ızgaralar, sohbet, akış posteri).
/// Kare Android'in MediaMetadataRetriever'ı ile alınır (video oynatıcı açılmaz, hafif)
/// ve diske önbelleklenir; bir kez üretilen küçük resim bir daha hesaplanmaz.
class VideoThumb extends StatefulWidget {
  final String dataUrl;
  final bool showPlayIcon;
  final BoxFit fit;
  const VideoThumb({super.key, required this.dataUrl, this.showPlayIcon = false, this.fit = BoxFit.cover});

  @override
  State<VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<VideoThumb> {
  static const MethodChannel _ch = MethodChannel('flinq/video_thumb');
  static final Map<int, Uint8List> _mem = {};
  static final List<int> _order = [];
  static final Map<int, Future<Uint8List?>> _pending = {};
  static int _active = 0;
  static final List<Completer<void>> _waiting = [];

  Uint8List? _img;
  bool _failed = false;

  int get _key => Object.hash(widget.dataUrl.length, widget.dataUrl.hashCode);

  @override
  void initState() {
    super.initState();
    final hit = _mem[_key];
    if (hit != null) {
      _img = hit;
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant VideoThumb old) {
    super.didUpdateWidget(old);
    if (old.dataUrl != widget.dataUrl) {
      _img = _mem[_key];
      _failed = false;
      if (_img == null) _load();
    }
  }

  static Future<void> _acquire() async {
    if (_active < 2) {
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

  static Future<Uint8List?> _generate(int key, String dataUrl) {
    return _pending.putIfAbsent(key, () async {
      await _acquire();
      try {
        final path = await MediaCache.file(dataUrl);
        if (path == null) return null;
        final thumbFile = File('$path.thumb.jpg');
        Uint8List? bytes;
        if (thumbFile.existsSync() && thumbFile.lengthSync() > 0) {
          bytes = await thumbFile.readAsBytes();
        } else {
          bytes = await _ch.invokeMethod<Uint8List>('frame', {'path': path, 'maxWidth': 480});
          if (bytes != null && bytes.isNotEmpty) await thumbFile.writeAsBytes(bytes, flush: true);
        }
        if (bytes == null || bytes.isEmpty) return null;
        _mem[key] = bytes;
        _order.add(key);
        while (_order.length > 80) {
          _mem.remove(_order.removeAt(0));
        }
        return bytes;
      } catch (_) {
        return null;
      } finally {
        _release();
        _pending.remove(key);
      }
    });
  }

  Future<void> _load() async {
    final b = await _generate(_key, widget.dataUrl);
    if (!mounted) return;
    setState(() {
      _img = b;
      _failed = b == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final img = _img;
    Widget child;
    if (img != null) {
      child = Image.memory(img, fit: widget.fit, gaplessPlayback: true, width: double.infinity, height: double.infinity);
    } else {
      child = Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF1B1F2A), Color(0xFF2E3445)]),
        ),
        child: Center(
          child: _failed
              ? const Icon(Icons.play_arrow_rounded, color: Colors.white54, size: 34)
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
            radius: 24,
            backgroundColor: Colors.black38,
            child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
          ),
        ),
      ],
    );
  }
}
