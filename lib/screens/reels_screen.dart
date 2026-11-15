import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import '../widgets/feed_video.dart';
import '../widgets/post_card.dart';
import 'comments_sheet.dart';
import 'dm_screens.dart';

/// Tam ekran, dikey kaydırmalı video akışı.
class ReelsScreen extends StatefulWidget {
  final bool active;
  const ReelsScreen({super.key, required this.active});

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  List<Post>? _videos;

  @override
  void didUpdateWidget(covariant ReelsScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && _videos == null) _load();
  }

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
  }

  Future<void> _load() async {
    final all = await context.read<AppState>().loadFeed(limit: 250);
    if (!mounted) return;
    setState(() => _videos = all.where((p) => p.type == 'video' && p.url.isNotEmpty).toList());
  }

  @override
  Widget build(BuildContext context) {
    final v = _videos;
    return Scaffold(
      backgroundColor: Colors.black,
      body: !widget.active
          ? const SizedBox.shrink()
          : v == null
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : v.isEmpty
                  ? Theme(
                      data: ThemeData.dark(),
                      child: const EmptyState(
                        icon: Icons.slow_motion_video_rounded,
                        title: 'Henüz video yok',
                        subtitle: 'İlk videoyu sen paylaş!',
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: PageView.builder(
                        scrollDirection: Axis.vertical,
                        itemCount: v.length,
                        itemBuilder: (_, i) => _Reel(key: ValueKey(v[i].id), post: v[i]),
                      ),
                    ),
    );
  }
}

class _Reel extends StatefulWidget {
  final Post post;
  const _Reel({super.key, required this.post});

  @override
  State<_Reel> createState() => _ReelState();
}

class _ReelState extends State<_Reel> {
  late Post _p = widget.post;
  bool _heart = false;

  Future<void> _like({bool force = false}) async {
    final app = context.read<AppState>();
    final liked = _p.likedBy.contains(app.uid);
    if (force && liked) return;
    await app.toggleLike(_p);
    final fresh = await app.loadPost(_p.id);
    if (fresh != null && mounted) setState(() => _p = fresh);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final author = app.cachedUser(_p.uid);
    final liked = _p.likedBy.contains(app.uid);
    final saved = app.me?.saved.contains(_p.id) ?? false;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onDoubleTap: () {
            setState(() => _heart = true);
            Future.delayed(const Duration(milliseconds: 700), () {
              if (mounted) setState(() => _heart = false);
            });
            _like(force: true);
          },
          child: FeedVideo(dataUrl: _p.url, fill: true, muted: false, autoplay: true),
        ),
        if (_heart)
          const Center(
            child: IgnorePointer(
              child: Icon(Icons.favorite_rounded, color: Colors.white, size: 120,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 24)]),
            ),
          ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54],
              ),
            ),
          ),
        ),
        Positioned(
          right: 8,
          bottom: 40,
          child: Column(
            children: [
              _Side(
                icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: liked ? FColors.like : Colors.white,
                label: compactCount(_p.likes),
                onTap: _like,
              ),
              _Side(
                icon: Icons.mode_comment_outlined,
                label: compactCount(_p.commentCount),
                onTap: () async {
                  await showCommentsSheet(context, _p.id);
                  final fresh = await app.loadPost(_p.id);
                  if (fresh != null && mounted) setState(() => _p = fresh);
                },
              ),
              _Side(
                icon: Icons.send_outlined,
                label: 'Paylaş',
                onTap: () => sharePostSheet(context, _p),
              ),
              _Side(
                icon: saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                label: 'Kaydet',
                onTap: () => app.toggleSave(_p.id),
              ),
            ],
          ),
        ),
        Positioned(
          left: 14,
          right: 80,
          bottom: 28,
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => openProfile(context, _p.uid),
                      child: FAvatar(name: _p.username, photo: author?.photo, size: 34),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: GestureDetector(
                        onTap: () => openProfile(context, _p.uid),
                        child: UserName(author?.username ?? _p.username, verified: author?.verified ?? false),
                      ),
                    ),
                    if (_p.uid != app.uid && !app.following.contains(_p.uid)) ...[
                      const SizedBox(width: 10),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                          minimumSize: const Size(0, 30),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: () => app.toggleFollow(_p.uid),
                        child: const Text('Takip et'),
                      ),
                    ],
                  ],
                ),
                if (_p.caption.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  RichCaption(
                    text: _p.caption,
                    trimAt: 90,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    onHashtag: (t) => openHashtag(context, t),
                    onMention: (u) => openProfileByUsername(context, u),
                  ),
                ],
                const SizedBox(height: 4),
                Text(timeAgo(_p.timestamp), style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Side extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _Side({required this.icon, required this.label, required this.onTap, this.color = Colors.white});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            children: [
              Icon(icon, color: color, size: 32, shadows: const [Shadow(color: Colors.black45, blurRadius: 8)]),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}
