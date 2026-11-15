import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import '../widgets/post_card.dart';

/// Üç sütunlu gönderi ızgarası (keşfet, profil, etiket).
class PostGrid extends StatelessWidget {
  final List<Post> posts;
  final bool shrinkWrap;
  const PostGrid({super.key, required this.posts, this.shrinkWrap = false});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 1.5,
        crossAxisSpacing: 1.5,
      ),
      itemCount: posts.length,
      itemBuilder: (_, i) => PostThumb(
        post: posts[i],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PostListScreen(posts: posts, initialIndex: i)),
        ),
      ),
    );
  }
}

class PostThumb extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;
  const PostThumb({super.key, required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (post.type == 'text') {
      child = TextPostCard(text: post.caption, seed: post.id, small: true);
    } else if (post.type == 'video') {
      child = Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF1B1F2A), Color(0xFF2E3445)]),
        ),
        child: const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 38)),
      );
    } else {
      final b = MediaCache.bytes(post.url);
      child = b == null
          ? Container(color: Colors.black12)
          : Image.memory(b, fit: BoxFit.cover, cacheWidth: 360, gaplessPlayback: true);
    }
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (post.type == 'video')
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(Icons.slow_motion_video_rounded, color: Colors.white, size: 18),
            ),
          if (post.likes > 0)
            Positioned(
              left: 6,
              bottom: 4,
              child: Row(
                children: [
                  const Icon(Icons.favorite_rounded, color: Colors.white, size: 13,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                  const SizedBox(width: 2),
                  Text(compactCount(post.likes),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Izgaradan açılan dikey gönderi listesi.
class PostListScreen extends StatefulWidget {
  final List<Post> posts;
  final int initialIndex;
  final String title;
  const PostListScreen({super.key, required this.posts, this.initialIndex = 0, this.title = 'Gönderiler'});

  @override
  State<PostListScreen> createState() => _PostListScreenState();
}

class _PostListScreenState extends State<PostListScreen> {
  late final List<Post> _posts = List.of(widget.posts);
  final _keys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialIndex <= 0 || widget.initialIndex >= _posts.length) return;
      final ctx = _keys[_posts[widget.initialIndex].id]?.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SingleChildScrollView(
        child: Column(
          children: [
            for (final p in _posts)
              KeyedSubtree(
                key: _keys.putIfAbsent(p.id, () => GlobalKey()),
                child: PostCard(
                  post: p,
                  onDeleted: () => setState(() => _posts.removeWhere((x) => x.id == p.id)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _q = TextEditingController();
  List<Post> _posts = [];
  List<FUser> _users = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final posts = await app.loadFeed(limit: 150);
    final users = await app.allUsers(refresh: true);
    if (!mounted) return;
    // Keşfet: medya gönderilerini beğeni + tazeliğe göre sırala.
    final now = DateTime.now().millisecondsSinceEpoch;
    double score(Post p) {
      final ageH = (now - p.timestamp) / 3600000.0;
      return (p.likes * 2 + p.commentCount * 3 + 1) / ((ageH + 2) * (ageH + 2) / 50 + 1);
    }

    posts.sort((a, b) => score(b).compareTo(score(a)));
    setState(() {
      _posts = posts;
      _users = users;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final searching = q.isNotEmpty;
    final tagMode = q.startsWith('#');
    final userResults = searching && !tagMode
        ? _users.where((u) => u.username.toLowerCase().contains(q.replaceFirst('@', ''))).take(30).toList()
        : const <FUser>[];
    final tags = <String, int>{};
    if (searching) {
      final needle = tagMode ? q.substring(1) : q;
      for (final p in _posts) {
        for (final m in RegExp(r'#([\wığüşöçİĞÜŞÖÇ]+)').allMatches(p.caption)) {
          final t = m.group(1)!.toLowerCase();
          if (t.contains(needle)) tags[t] = (tags[t] ?? 0) + 1;
        }
      }
    }
    final tagList = tags.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: TextField(
          controller: _q,
          onChanged: (v) => setState(() => _query = v.trim()),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Kişi veya #etiket ara',
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _q.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : searching
              ? ListView(
                  children: [
                    for (final e in tagList.take(10))
                      ListTile(
                        leading: const CircleAvatar(child: Text('#', style: TextStyle(fontSize: 20))),
                        title: Text('#${e.key}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${e.value} gönderi'),
                        onTap: () => openHashtag(context, e.key),
                      ),
                    for (final u in userResults)
                      ListTile(
                        leading: FAvatar(name: u.username, photo: u.photo, size: 44),
                        title: UserName(u.username, verified: u.verified),
                        subtitle: u.bio.isEmpty ? null : Text(u.bio, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => openProfile(context, u.uid),
                      ),
                    if (tagList.isEmpty && userResults.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 60),
                        child: EmptyState(icon: Icons.search_off_rounded, title: 'Sonuç bulunamadı'),
                      ),
                  ],
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _posts.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 80),
                          EmptyState(icon: Icons.explore_outlined, title: 'Keşfedilecek gönderi yok'),
                        ])
                      : PostGrid(posts: _posts),
                ),
    );
  }
}

class HashtagScreen extends StatefulWidget {
  final String tag;
  const HashtagScreen({super.key, required this.tag});

  @override
  State<HashtagScreen> createState() => _HashtagScreenState();
}

class _HashtagScreenState extends State<HashtagScreen> {
  List<Post>? _posts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await context.read<AppState>().loadFeed(limit: 400);
    final re = RegExp('#${RegExp.escape(widget.tag)}(?![\\wığüşöçİĞÜŞÖÇ])', caseSensitive: false);
    if (!mounted) return;
    setState(() => _posts = all.where((p) => re.hasMatch(p.caption)).toList());
  }

  @override
  Widget build(BuildContext context) {
    final posts = _posts;
    return Scaffold(
      appBar: AppBar(title: Text('#${widget.tag}')),
      body: posts == null
          ? const Center(child: CircularProgressIndicator())
          : posts.isEmpty
              ? const EmptyState(icon: Icons.tag_rounded, title: 'Bu etiketle gönderi yok')
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Theme.of(context).dividerColor, width: 1.5),
                            ),
                            child: const Text('#', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w300)),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('#${widget.tag}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                              Text('${posts.length} gönderi', style: TextStyle(color: Theme.of(context).hintColor)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: PostGrid(posts: posts)),
                  ],
                ),
    );
  }
}
