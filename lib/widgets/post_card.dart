import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../screens/comments_sheet.dart';
import '../screens/dm_screens.dart';
import '../screens/explore_screen.dart';
import '../screens/profile_screen.dart';
import '../services/app_state.dart';
import 'report_sheet.dart';
import 'common.dart';
import 'feed_video.dart';
import 'post_image.dart';

void openProfile(BuildContext context, String uid) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: uid)));
}

Future<void> openProfileByUsername(BuildContext context, String username) async {
  final app = context.read<AppState>();
  final s = await app.db.ref('usernames/${username.toLowerCase()}').get();
  final uid = asStr(asMap(s.value)['uid']);
  if (!context.mounted) return;
  if (uid.isEmpty) {
    showSnack(context, '@$username bulunamadı.', error: true);
    return;
  }
  openProfile(context, uid);
}

void openHashtag(BuildContext context, String tag) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => HashtagScreen(tag: tag)));
}

class PostCard extends StatefulWidget {
  final Post post;
  final VoidCallback? onDeleted;
  const PostCard({super.key, required this.post, this.onDeleted});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with SingleTickerProviderStateMixin {
  late Post _p = widget.post;
  late bool _liked;
  late int _likes;
  bool _showHeart = false;
  late final AnimationController _heart =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant PostCard old) {
    super.didUpdateWidget(old);
    if (old.post != widget.post) {
      _p = widget.post;
      _sync();
    }
  }

  void _sync() {
    final uid = context.read<AppState>().uid;
    _liked = _p.likedBy.contains(uid);
    _likes = _p.likes;
  }

  @override
  void dispose() {
    _heart.dispose();
    super.dispose();
  }

  Future<void> _toggleLike({bool forceLike = false}) async {
    final app = context.read<AppState>();
    if (forceLike && _liked) return;
    HapticFeedback.lightImpact();
    setState(() {
      _liked = !_liked;
      _likes += _liked ? 1 : -1;
      if (_likes < 0) _likes = 0;
    });
    try {
      final current = Post(
        id: _p.id,
        uid: _p.uid,
        username: _p.username,
        url: _p.url,
        caption: _p.caption,
        type: _p.type,
        likes: _likes,
        likedBy: _liked ? (_p.likedBy.difference({app.uid})) : {..._p.likedBy, if (app.uid != null) app.uid!},
      );
      await app.toggleLike(current);
      final fresh = await app.loadPost(_p.id);
      if (fresh != null && mounted) {
        setState(() {
          _p = fresh;
          _sync();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _liked = !_liked;
          _likes += _liked ? 1 : -1;
        });
        showSnack(context, 'Beğeni kaydedilemedi.', error: true);
      }
    }
  }

  void _doubleTap() {
    setState(() => _showHeart = true);
    _heart.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _showHeart = false);
    });
    _toggleLike(forceLike: true);
  }

  Future<void> _openComments() async {
    await showCommentsSheet(context, _p.id);
    final fresh = await context.read<AppState>().loadPost(_p.id);
    if (fresh != null && mounted) setState(() => _p = fresh);
  }

  void _menu() {
    final app = context.read<AppState>();
    final mine = _p.uid == app.uid;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mine)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Açıklamayı düzenle'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final v = await promptText(context, title: 'Açıklama', initial: _p.caption, maxLines: 5);
                  if (v == null) return;
                  await app.editPost(_p.id, v.trim());
                  final fresh = await app.loadPost(_p.id);
                  if (fresh != null && mounted) setState(() => _p = fresh);
                },
              ),
            if (_p.caption.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Metni kopyala'),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: _p.caption));
                  showSnack(context, 'Kopyalandı');
                },
              ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text('@${_p.username} profiline git'),
              onTap: () {
                Navigator.pop(ctx);
                openProfile(context, _p.uid);
              },
            ),
            if (!mine)
              ListTile(
                leading: Icon(app.following.contains(_p.uid) ? Icons.person_remove_outlined : Icons.person_add_alt),
                title: Text(app.following.contains(_p.uid) ? 'Takibi bırak' : 'Takip et'),
                onTap: () {
                  Navigator.pop(ctx);
                  app.toggleFollow(_p.uid);
                },
              ),
            if (!mine)
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: FColors.danger),
                title: const Text('Şikayet et', style: TextStyle(color: FColors.danger)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final reason = await pickReportReason(context, title: 'Gönderiyi şikayet et');
                  if (reason == null) return;
                  await app
                      .report(type: 'post', targetUid: _p.uid, path: 'posts/${_p.id}', preview: _p.caption, reason: reason)
                      .catchError((_) {});
                  if (mounted) showSnack(context, 'Şikayetin yöneticiye iletildi. Teşekkürler.');
                },
              ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: FColors.danger),
                title: const Text('Gönderiyi sil', style: TextStyle(color: FColors.danger)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await confirmDialog(context,
                      title: 'Gönderiyi sil', message: 'Bu gönderi kalıcı olarak silinecek.', confirmText: 'Sil', destructive: true);
                  if (!ok) return;
                  await app.deletePost(_p.id);
                  widget.onDeleted?.call();
                  if (mounted) showSnack(context, 'Gönderi silindi.');
                },
              ),
          ],
        ),
      ),
    );
  }

  void _share() {
    final text = _p.type == 'text'
        ? '"${_p.caption}" — @${_p.username} FlinQ\'da'
        : '@${_p.username} FlinQ\'da bir gönderi paylaştı${_p.caption.isNotEmpty ? ': ${_p.caption}' : ''}';
    Share.share(text);
  }

  // Fly (metin gönderisi) için üstteki çift dokunuşla beğeni, gövde tweet gibi sola yaslı.

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final author = app.cachedUser(_p.uid);
    final theme = Theme.of(context);
    final saved = app.me?.saved.contains(_p.id) ?? false;
    final hasStory = app.stories.containsKey(_p.uid);
    final media = _p.type == 'video'
        ? FeedVideo(
            postId: _p.id,
            autoplay: app.autoplay,
            muted: app.feedMuted,
            onMuteChanged: (m) => app.setPref('feedMuted', m),
          )
        : _p.type == 'text'
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
                alignment: Alignment.centerLeft,
                child: RichCaption(
                  text: _p.caption,
                  style: const TextStyle(fontSize: 18, height: 1.4),
                  trimAt: 1200,
                  onHashtag: (t) => openHashtag(context, t),
                  onMention: (u) => openProfileByUsername(context, u),
                ),
              )
            : _image();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => openProfile(context, _p.uid),
                child: FAvatar(
                  name: _p.username,
                  photo: author?.photo,
                  size: 34,
                  ring: hasStory
                      ? (app.hasUnseenStory(_p.uid) ? StoryRing.unseen : StoryRing.seen)
                      : StoryRing.none,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => openProfile(context, _p.uid),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      UserName(author?.username ?? _p.username, verified: author?.verified ?? false),
                      Text(timeAgo(_p.timestamp),
                          style: TextStyle(fontSize: 12, color: theme.hintColor)),
                    ],
                  ),
                ),
              ),
              if (_p.uid != app.uid && !app.following.contains(_p.uid))
                TextButton(
                  onPressed: () => app.toggleFollow(_p.uid),
                  child: const Text('Takip et', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              IconButton(icon: const Icon(Icons.more_horiz_rounded), onPressed: _menu),
            ],
          ),
        ),
        GestureDetector(
          onDoubleTap: _doubleTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(width: double.infinity, child: media),
              if (_showHeart)
                IgnorePointer(
                  child: ScaleTransition(
                    scale: CurvedAnimation(parent: _heart, curve: Curves.elasticOut),
                    child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 110,
                        shadows: [Shadow(color: Colors.black38, blurRadius: 20)]),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
          child: Row(
            children: [
              IconButton(
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                  child: Icon(
                    _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    key: ValueKey(_liked),
                    color: _liked ? FColors.like : null,
                    size: 27,
                  ),
                ),
                onPressed: () => _toggleLike(),
              ),
              IconButton(icon: const Icon(Icons.mode_comment_outlined, size: 25), onPressed: _openComments),
              IconButton(icon: const Icon(Icons.send_outlined, size: 24), onPressed: () => sharePostSheet(context, _p)),
              const Spacer(),
              IconButton(
                icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 27),
                onPressed: () {
                  app.toggleSave(_p.id);
                  showSnack(context, saved ? 'Kaydedilenlerden çıkarıldı' : 'Kaydedildi');
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_likes > 0)
                Text('${compactCount(_likes)} beğenme', style: const TextStyle(fontWeight: FontWeight.w700)),
              if (_p.caption.isNotEmpty && _p.type != 'text')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: RichCaption(
                    prefix: _p.username,
                    onPrefix: () => openProfile(context, _p.uid),
                    text: _p.caption,
                    onHashtag: (t) => openHashtag(context, t),
                    onMention: (u) => openProfileByUsername(context, u),
                  ),
                ),
              if (_p.commentCount > 0)
                GestureDetector(
                  onTap: _openComments,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${_p.commentCount} yorumun tümünü gör',
                        style: TextStyle(color: theme.hintColor)),
                  ),
                ),
              if (_p.comments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: RichCaption(
                    prefix: _p.comments.last.username,
                    onPrefix: () => openProfileByUsername(context, _p.comments.last.username),
                    text: _p.comments.last.text,
                    trimAt: 80,
                    onHashtag: (t) => openHashtag(context, t),
                    onMention: (u) => openProfileByUsername(context, u),
                  ),
                ),
              if (_p.edited)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('düzenlendi', style: TextStyle(fontSize: 11, color: theme.hintColor)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _image() {
    final w = MediaQuery.of(context).size.width;
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: PostImage(
        postId: _p.id,
        cacheWidth: (w * MediaQuery.of(context).devicePixelRatio).round().clamp(320, 1440).toInt(),
      ),
    );
  }
}
