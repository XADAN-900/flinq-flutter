import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'profile_screen.dart';

Future<void> addStoryFlow(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Hikaye ekle', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Galeriden seç'),
          onTap: () => Navigator.pop(ctx, ImageSource.gallery),
        ),
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: const Text('Fotoğraf çek'),
          onTap: () => Navigator.pop(ctx, ImageSource.camera),
        ),
      ]),
    ),
  );
  if (source == null || !context.mounted) return;
  final x = await ImagePicker().pickImage(source: source, maxWidth: 900, maxHeight: 1600, imageQuality: 72);
  if (x == null || !context.mounted) return;
  final bytes = await x.readAsBytes();
  if (!context.mounted) return;
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
              child: Image.memory(bytes, height: 300, fit: BoxFit.cover),
            ),
            const SizedBox(height: 10),
            TextField(controller: c, decoration: const InputDecoration(hintText: 'Bir şey yaz… (isteğe bağlı)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Paylaş')),
        ],
      );
    },
  );
  if (caption == null || !context.mounted) return;
  final err = await context.read<AppState>().addStory(toDataUrl(bytes, 'image/jpeg'), caption: caption);
  if (context.mounted) showSnack(context, err ?? 'Hikayen paylaşıldı ✨', error: err != null);
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
    context.read<AppState>().markStorySeen(list[_index]);
    _progress.forward(from: 0);
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
    final bytes = MediaCache.bytes(s.url);
    final mine = s.uid == app.uid;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          d.globalPosition.dx < w / 3 ? _prev() : _next();
        },
        onLongPressStart: (_) => _progress.stop(),
        onLongPressEnd: (_) => _progress.forward(),
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 300) Navigator.of(context).maybePop();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null) Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
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
