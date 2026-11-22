import 'dart:async';
import 'package:flinq/core/i18n.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import '../widgets/preview_video.dart';
import 'story_camera_screen.dart';
import 'profile_screen.dart';

/// Hikaye videosu en fazla 30 sn ve 15 MB (veritabanında saklandığı için).
const int _maxStoryVideoBytes = 15 * 1024 * 1024;

Future<void> addStoryFlow(BuildContext context) async {
  final fromCamera = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: T('Hikaye ekle', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        ),
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: const T('Kamera'),
          subtitle: const T('Fotoğraf için dokun, video için basılı tut'),
          onTap: () => Navigator.pop(ctx, true),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const T('Galeri'),
          subtitle: const T('Fotoğraflar ve videolar'),
          onTap: () => Navigator.pop(ctx, false),
        ),
      ]),
    ),
  );
  if (fromCamera == null || !context.mounted) return;
  XFile? x;
  bool isVideo;
  if (fromCamera) {
    final r = await Navigator.of(context).push<(XFile, bool)>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const StoryCameraScreen()),
    );
    if (r == null) return;
    x = r.$1;
    isVideo = r.$2;
  } else {
    x = await ImagePicker().pickMedia(maxWidth: 1080, maxHeight: 1920, imageQuality: 80);
    if (x == null) return;
    final mt = x.mimeType ?? '';
    final n = x.name.toLowerCase();
    isVideo = mt.startsWith('video/') ||
        const ['.mp4', '.mov', '.webm', '.3gp', '.mkv', '.m4v'].any(n.endsWith);
  }
  if (!context.mounted) return;
  if (isVideo && await x.length() > _maxStoryVideoBytes) {
    if (context.mounted) {
      showSnack(context, tr('Video çok büyük (en fazla 15 MB). Daha kısa bir video seç.'), error: true);
    }
    return;
  }
  final bytes = await x.readAsBytes();
  if (!context.mounted) return;
  var mime = 'image/jpeg';
  if (isVideo) {
    final mt = x.mimeType;
    final name = x.name.toLowerCase();
    mime = (mt != null && mt.startsWith('video/'))
        ? mt
        : name.endsWith('.webm')
            ? 'video/webm'
            : name.endsWith('.3gp')
                ? 'video/3gpp'
                : name.endsWith('.mov')
                    ? 'video/quicktime'
                    : 'video/mp4';
  }
  if (!isVideo && bytes.length > 3 * 1024 * 1024) {
    if (context.mounted) showSnack(context, tr('Fotoğraf çok büyük.'), error: true);
    return;
  }
  final dataUrl = toDataUrl(bytes, mime);
  final filePath = x.path;
  final caption = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final c = TextEditingController();
      return AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: isVideo
                  ? SizedBox(
                      height: 300,
                      width: double.infinity,
                      child: PreviewVideo(path: filePath),
                    )
                  : Image.memory(bytes, height: 300, fit: BoxFit.cover),
            ),
            const SizedBox(height: 10),
            TextField(controller: c, decoration: InputDecoration(hintText: tr('Bir şey yaz… (isteğe bağlı)'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const T('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const T('Paylaş')),
        ],
      );
    },
  );
  if (caption == null || !context.mounted) return;
  if (isVideo) showSnack(context, tr('Hikaye yükleniyor…'));
  final err = await context
      .read<AppState>()
      .addStory(dataUrl, caption: caption, type: isVideo ? 'video' : 'image');
  if (context.mounted) showSnack(context, err ?? 'Hikayen paylaşıldı ✨', error: err != null);
}

/// Hikaye videosu: hazır olunca süresini bildirir, tam ekran oynatır.
class _StoryVideo extends StatefulWidget {
  final Future<String?> source;
  final bool paused;
  final ValueChanged<Duration> onReady;
  final VoidCallback onError;
  const _StoryVideo({super.key, required this.source, required this.paused, required this.onReady, required this.onError});

  @override
  State<_StoryVideo> createState() => _StoryVideoState();
}

class _StoryVideoState extends State<_StoryVideo> {
  VideoPlayerController? _c;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final data = await widget.source;
    if (!mounted) return;
    final path = await MediaCache.file(data);
    if (!mounted) return;
    if (path == null) {
      setState(() => _failed = true);
      widget.onError();
      return;
    }
    final c = VideoPlayerController.file(File(path));
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      if (mounted) {
        setState(() => _failed = true);
        widget.onError();
      }
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    await c.setVolume(1);
    setState(() => _c = c);
    widget.onReady(c.value.duration);
    if (!widget.paused) await c.play();
  }

  @override
  void didUpdateWidget(covariant _StoryVideo old) {
    super.didUpdateWidget(old);
    final c = _c;
    if (c == null || old.paused == widget.paused) return;
    widget.paused ? c.pause() : c.play();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (_failed) {
      return const Center(child: T('Video açılamadı', style: TextStyle(color: Colors.white70)));
    }
    if (c == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4));
    }
    return Center(
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio == 0 ? 9 / 16 : c.value.aspectRatio,
        child: VideoPlayer(c),
      ),
    );
  }
}

class StoryViewer extends StatefulWidget {
  final List<String> owners;
  final int startIndex;
  const StoryViewer({super.key, required this.owners, this.startIndex = 0});

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> with SingleTickerProviderStateMixin {
  late int _owner = widget.startIndex < 0 ? 0 : widget.startIndex;
  int _index = 0;
  bool _paused = false;
  String? _videoId; // hazır olması beklenen hikaye videosu
  late final AnimationController _progress =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _next();
        });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCurrent(first: true));
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  List<Story> get _stories => context.read<AppState>().stories[widget.owners[_owner]] ?? const [];

  void _startCurrent({bool first = false}) {
    final list = _stories;
    if (list.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    if (first) {
      final app = context.read<AppState>();
      final firstUnseen = list.indexWhere((s) => !s.viewers.contains(app.uid));
      _index = firstUnseen < 0 ? 0 : firstUnseen;
    }
    if (_index >= list.length) _index = list.length - 1;
    final s = list[_index];
    context.read<AppState>().markStorySeen(s);
    if (s.isVideo) {
      // Video hazır olunca süresi kadar ilerler.
      _videoId = s.id;
      _progress.stop();
      _progress.value = 0;
    } else {
      _videoId = null;
      _progress.duration = const Duration(seconds: 6);
      _progress.forward(from: 0);
    }
    setState(() {});
  }

  void _next() {
    final list = _stories;
    if (_index < list.length - 1) {
      _index++;
      _startCurrent();
    } else if (_owner < widget.owners.length - 1) {
      _owner++;
      _index = 0;
      _startCurrent(first: true);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _prev() {
    if (_index > 0) {
      _index--;
      _startCurrent();
    } else if (_owner > 0) {
      _owner--;
      _index = 0;
      _startCurrent();
    } else {
      _progress.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final list = app.stories[widget.owners[_owner]] ?? const <Story>[];
    if (list.isEmpty) {
      return const Scaffold(backgroundColor: Colors.black);
    }
    final i = _index.clamp(0, list.length - 1).toInt();
    final s = list[i];
    final u = app.cachedUser(s.uid);
    final bytes = s.isVideo ? null : MediaCache.bytes(s.url);
    final mine = s.uid == app.uid;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          d.globalPosition.dx < w / 3 ? _prev() : _next();
        },
        onLongPressStart: (_) {
          _progress.stop();
          setState(() => _paused = true);
        },
        onLongPressEnd: (_) {
          setState(() => _paused = false);
          if (_videoId == null || _progress.value > 0) _progress.forward();
        },
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 300) Navigator.of(context).maybePop();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (s.isVideo)
              _StoryVideo(
                key: ValueKey('sv_${s.id}'),
                source: app.storyMediaUrl(s),
                paused: _paused,
                onReady: (d) {
                  if (!mounted || _videoId != s.id) return;
                  final ms = d.inMilliseconds.clamp(1000, 60000).toInt();
                  _progress.duration = Duration(milliseconds: ms);
                  if (!_paused) _progress.forward(from: 0);
                },
                onError: () {
                  if (!mounted || _videoId != s.id) return;
                  _progress.duration = const Duration(seconds: 3);
                  _progress.forward(from: 0);
                },
              )
            else if (bytes != null)
              Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        for (var k = 0; k < list.length; k++)
                          Expanded(
                            child: Container(
                              height: 2.6,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: Colors.white30,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: k < i
                                  ? Container(color: Colors.white)
                                  : k == i
                                      ? AnimatedBuilder(
                                          animation: _progress,
                                          builder: (_, __) => FractionallySizedBox(
                                            alignment: Alignment.centerLeft,
                                            widthFactor: _progress.value,
                                            child: Container(color: Colors.white),
                                          ),
                                        )
                                      : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            final nav = Navigator.of(context);
                            nav.pop();
                            nav.push(MaterialPageRoute(builder: (_) => ProfileScreen(uid: s.uid)));
                          },
                          child: FAvatar(name: u?.username ?? '', photo: u?.photo, size: 34),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(u?.username ?? '',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 8),
                        Text(timeAgo(s.timestamp), style: const TextStyle(color: Colors.white70)),
                        const Spacer(),
                        if (mine)
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                            onPressed: () async {
                              _progress.stop();
                              final ok = await confirmDialog(context,
                                  title: 'Hikayeyi sil', message: 'Bu hikaye silinsin mi?', confirmText: 'Sil', destructive: true);
                              if (ok) {
                                await app.deleteStory(s);
                                if (mounted) Navigator.of(context).maybePop();
                              } else {
                                _progress.forward();
                              }
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (s.caption.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.all(20),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(14)),
                      child: Text(s.caption,
                          textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 17)),
                    ),
                  if (mine)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.visibility_outlined, color: Colors.white, size: 18),
                          const SizedBox(width: 6),
                          Text('${s.viewers.length} görüntülenme', style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
