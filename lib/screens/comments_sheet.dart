import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import '../widgets/post_card.dart';

Future<void> showCommentsSheet(BuildContext context, String postId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => CommentsSheet(postId: postId),
  );
}

class CommentsSheet extends StatefulWidget {
  final String postId;
  const CommentsSheet({super.key, required this.postId});

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  Comment? _replyTo;
  bool _sending = false;
  List<FUser> _suggest = const [];
  List<FUser>? _allUsers;
  final Set<String> _openReplies = {};
  late final Stream<Post?> _stream = context.read<AppState>().watchPost(widget.postId);

  @override
  void initState() {
    super.initState();
    _input.addListener(_onText);
  }

  Future<void> _onText() async {
    final t = _input.text;
    final m = RegExp(r'@([\wığüşöçİĞÜŞÖÇ]*)$').firstMatch(t);
    if (m == null) {
      if (_suggest.isNotEmpty) setState(() => _suggest = const []);
      return;
    }
    _allUsers ??= await context.read<AppState>().allUsers();
    final q = m.group(1)!.toLowerCase();
    final list = _allUsers!
        .where((u) => u.username.toLowerCase().startsWith(q))
        .take(6)
        .toList();
    if (mounted) setState(() => _suggest = list);
  }

  void _pickMention(FUser u) {
    final t = _input.text;
    final i = t.lastIndexOf('@');
    final next = '${t.substring(0, i)}@${u.username} ';
    _input.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: next.length));
    setState(() => _suggest = const []);
  }

  Future<void> _send(Post p) async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await context.read<AppState>().addComment(p, text, replyTo: _replyTo);
      if (_replyTo != null) _openReplies.add(_replyTo!.id);
      _input.clear();
      setState(() => _replyTo = null);
    } catch (_) {
      if (mounted) showSnack(context, 'Yorum gönderilemedi.', error: true);
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final theme = Theme.of(context);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.82,
      child: StreamBuilder<Post?>(
        stream: _stream,
        builder: (context, snap) {
          final p = snap.data;
          if (snap.connectionState == ConnectionState.waiting && p == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (p == null) return const Center(child: Text('Gönderi bulunamadı'));
          app.warmUsers(p.comments.map((c) => c.uid));
          return Column(
            children: [
              const Text('Yorumlar', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              const Divider(),
              Expanded(
                child: p.comments.isEmpty
                    ? const EmptyState(
                        icon: Icons.mode_comment_outlined,
                        title: 'Henüz yorum yok',
                        subtitle: 'Sohbeti sen başlat.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: p.comments.length,
                        itemBuilder: (_, i) {
                          final c = p.comments[i];
                          final open = _openReplies.contains(c.id);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _CommentTile(
                                post: p,
                                uid: c.uid,
                                username: c.username,
                                text: c.text,
                                timestamp: c.timestamp,
                                likes: c.likedBy.length,
                                liked: c.likedBy.contains(app.uid),
                                onLike: () => app.toggleCommentLike(p.id, c),
                                onReply: () {
                                  setState(() => _replyTo = c);
                                  _input.text = '@${c.username} ';
                                  _input.selection = TextSelection.collapsed(offset: _input.text.length);
                                  _focus.requestFocus();
                                },
                                onDelete: (c.uid == app.uid || p.uid == app.uid)
                                    ? () => app.deleteComment(p.id, c.id)
                                    : null,
                              ),
                              if (c.replies.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 62),
                                  child: GestureDetector(
                                    onTap: () => setState(() => open ? _openReplies.remove(c.id) : _openReplies.add(c.id)),
                                    child: Row(
                                      children: [
                                        Container(width: 24, height: 1, color: theme.hintColor),
                                        const SizedBox(width: 8),
                                        Text(
                                          open ? 'Yanıtları gizle' : '${c.replies.length} yanıtı gör',
                                          style: TextStyle(
                                              color: theme.hintColor, fontWeight: FontWeight.w600, fontSize: 12.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (open)
                                for (final r in c.replies)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 44),
                                    child: _CommentTile(
                                      post: p,
                                      uid: r.uid,
                                      username: r.username,
                                      text: r.text,
                                      timestamp: r.timestamp,
                                      small: true,
                                      onReply: () {
                                        setState(() => _replyTo = c);
                                        _input.text = '@${r.username} ';
                                        _input.selection = TextSelection.collapsed(offset: _input.text.length);
                                        _focus.requestFocus();
                                      },
                                      onDelete: (r.uid == app.uid || p.uid == app.uid)
                                          ? () => app.deleteComment(p.id, c.id, replyId: r.id)
                                          : null,
                                    ),
                                  ),
                            ],
                          );
                        },
                      ),
              ),
              if (_suggest.isNotEmpty)
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final u in _suggest)
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: ActionChip(
                            avatar: FAvatar(name: u.username, photo: u.photo, size: 22),
                            label: Text('@${u.username}'),
                            onPressed: () => _pickMention(u),
                          ),
                        ),
                    ],
                  ),
                ),
              if (_replyTo != null)
                Container(
                  color: theme.brightness == Brightness.dark ? FColors.darkCard : const Color(0xFFF1F2F5),
                  padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('@${_replyTo!.username} kişisine yanıt veriliyor',
                            style: TextStyle(color: theme.hintColor)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          setState(() => _replyTo = null);
                          _input.clear();
                        },
                      ),
                    ],
                  ),
                ),
              const Divider(),
              Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 8, 8 + MediaQuery.of(context).viewInsets.bottom),
                child: Row(
                  children: [
                    FAvatar(name: app.username, photo: app.me?.photo, size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: '${p.username} için yorum ekle…',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                          enabledBorder:
                              OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    _sending
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : TextButton(
                            onPressed: () => _send(p),
                            child: const Text('Paylaş', style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Post post;
  final String uid;
  final String username;
  final String text;
  final int timestamp;
  final int likes;
  final bool liked;
  final bool small;
  final VoidCallback? onLike;
  final VoidCallback onReply;
  final VoidCallback? onDelete;

  const _CommentTile({
    required this.post,
    required this.uid,
    required this.username,
    required this.text,
    required this.timestamp,
    required this.onReply,
    this.likes = 0,
    this.liked = false,
    this.small = false,
    this.onLike,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final u = app.cachedUser(uid);
    final theme = Theme.of(context);
    return InkWell(
      onLongPress: onDelete == null
          ? null
          : () async {
              final ok = await confirmDialog(context,
                  title: 'Yorumu sil', message: 'Bu yorum silinsin mi?', confirmText: 'Sil', destructive: true);
              if (ok) onDelete!();
            },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => openProfile(context, uid),
              child: FAvatar(name: username, photo: u?.photo, size: small ? 28 : 36),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: UserName(u?.username ?? username, verified: u?.verified ?? false, fontSize: 13)),
                      const SizedBox(width: 6),
                      Text(timeAgo(timestamp), style: TextStyle(fontSize: 12, color: theme.hintColor)),
                      if (uid == post.uid)
                        Text(' · Yazar', style: TextStyle(fontSize: 12, color: theme.hintColor)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  RichCaption(
                    text: text,
                    onMention: (n) => openProfileByUsername(context, n),
                    onHashtag: (t) => openHashtag(context, t),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: onReply,
                        child: Text('Yanıtla',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: theme.hintColor)),
                      ),
                      if (onDelete != null) ...[
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () async {
                            final ok = await confirmDialog(context,
                                title: 'Yorumu sil',
                                message: 'Bu yorum silinsin mi?',
                                confirmText: 'Sil',
                                destructive: true);
                            if (ok) onDelete!();
                          },
                          child: Text('Sil',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: theme.hintColor)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (onLike != null)
              Column(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        size: 16, color: liked ? FColors.like : theme.hintColor),
                    onPressed: onLike,
                  ),
                  if (likes > 0) Text('$likes', style: TextStyle(fontSize: 11, color: theme.hintColor)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
