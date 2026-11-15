import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/utils.dart';

/// Akıştaki video: ekranda görünür olunca (otomatik oynatma açıksa) oynar,
/// görünmez olunca durur. Aynı anda tek video çalar.
/// Yeni sayfa açılınca akıştaki videoyu durdurur.
class VideoPauseObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => FeedVideoState.pauseAll();
}

class FeedVideo extends StatefulWidget {
  final String dataUrl;
  final bool autoplay;
  final bool muted;
  final ValueChanged<bool>? onMuteChanged;
  final bool fill;
  final bool loop;

  const FeedVideo({
    super.key,
    required this.dataUrl,
    this.autoplay = true,
    this.muted = true,
    this.onMuteChanged,
    this.fill = false,
    this.loop = true,
  });

  @override
  State<FeedVideo> createState() => FeedVideoState();
}

class FeedVideoState extends State<FeedVideo> {
  static FeedVideoState? _playing;

  /// Sekme / sayfa değişince çalan videoyu durdurur.
  static void pauseAll() => _playing?.pause();

  VideoPlayerController? _c;
  bool _loading = false;
  bool _failed = false;
  bool _muted = true;
  bool _visible = false;
  ScrollPosition? _pos;

  @override
  void initState() {
    super.initState();
    _muted = widget.muted;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisible());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = Scrollable.maybeOf(context)?.position;
    if (p != _pos) {
      _pos?.removeListener(_checkVisible);
      _pos = p;
      _pos?.addListener(_checkVisible);
    }
  }

  @override
  void didUpdateWidget(covariant FeedVideo old) {
    super.didUpdateWidget(old);
    if (old.muted != widget.muted) {
      _muted = widget.muted;
      _c?.setVolume(_muted ? 0 : 1);
    }
  }

  void _checkVisible() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final center = top + box.size.height / 2;
    final h = MediaQuery.of(context).size.height;
    final visible = center > 60 && center < h - 60;
    if (visible == _visible) return;
    _visible = visible;
    if (visible && widget.autoplay) {
      play();
    } else if (visible) {
      _ensure(); // otomatik oynatma kapalıysa da ilk kareyi (önizleme) göster
    } else {
      pause();
    }
  }

  Future<void> _ensure() async {
    if (_c != null || _loading || _failed) return;
    setState(() => _loading = true);
    final path = await MediaCache.file(widget.dataUrl);
    if (!mounted) return;
    if (path == null) {
      setState(() {
        _failed = true;
        _loading = false;
      });
      return;
    }
    final c = VideoPlayerController.file(File(path));
    try {
      await c.initialize();
      await c.setLooping(widget.loop);
      await c.setVolume(_muted ? 0 : 1);
      await c.seekTo(const Duration(milliseconds: 200)); // ilk kare görünsün
      if (!mounted) {
        c.dispose();
        return;
      }
      c.addListener(_onTick);
      setState(() {
        _c = c;
        _loading = false;
      });
    } catch (_) {
      c.dispose();
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<void> play() async {
    await _ensure();
    final c = _c;
    if (c == null || !mounted) return;
    if (_playing != null && _playing != this) _playing!.pause();
    _playing = this;
    await c.play();
  }

  void pause() {
    _c?.pause();
    if (_playing == this) _playing = null;
  }

  void toggleMute() {
    setState(() => _muted = !_muted);
    _c?.setVolume(_muted ? 0 : 1);
    widget.onMuteChanged?.call(_muted);
  }

  @override
  void dispose() {
    _pos?.removeListener(_checkVisible);
    if (_playing == this) _playing = null;
    _c?.removeListener(_onTick);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final ready = c != null && c.value.isInitialized;
    final ratio = ready && c!.value.aspectRatio > 0 ? c!.value.aspectRatio : 4 / 5;
    final video = ready
        ? (widget.fill
            ? FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(width: c!.value.size.width, height: c!.value.size.height, child: VideoPlayer(c!)),
              )
            : AspectRatio(aspectRatio: ratio, child: VideoPlayer(c!)))
        : AspectRatio(
            aspectRatio: widget.fill ? 9 / 16 : 4 / 5,
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: _failed
                  ? const Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 48)
                  : _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 64),
            ),
          );
    return GestureDetector(
      onTap: () {
        if (!ready) {
          play();
        } else if (c!.value.isPlaying) {
          pause();
          setState(() {});
        } else {
          play();
        }
      },
      child: Stack(
        fit: widget.fill ? StackFit.expand : StackFit.loose,
        alignment: Alignment.center,
        children: [
          video,
          if (ready && !c!.value.isPlaying)
            const IgnorePointer(
              child: CircleAvatar(
                radius: 30,
                backgroundColor: Colors.black38,
                child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
              ),
            ),
          if (ready)
            Positioned(
              right: 10,
              bottom: 10,
              child: GestureDetector(
                onTap: toggleMute,
                child: CircleAvatar(
                  radius: 15,
                  backgroundColor: Colors.black54,
                  child: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      color: Colors.white, size: 16),
                ),
              ),
            ),
          if (ready && !widget.fill)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(c!, allowScrubbing: false,
                  padding: EdgeInsets.zero,
                  colors: const VideoProgressColors(playedColor: Colors.white70, backgroundColor: Colors.white12)),
            ),
        ],
      ),
    );
  }
}
