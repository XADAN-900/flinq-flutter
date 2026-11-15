import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import '../widgets/feed_video.dart';
import '../widgets/post_card.dart';
import 'create_post_screen.dart';
import 'explore_screen.dart';
import 'notifications_screen.dart';
import 'post_detail_screen.dart';
import 'profile_screen.dart';
import 'reels_screen.dart';
import 'story_viewer.dart';

void openNotificationTarget(BuildContext context, NotificationItem n) {
  final app = context.read<AppState>();
  if (!n.read) app.markNotificationRead(n.id);
  if (n.postId.isNotEmpty) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: n.postId, openComments: n.commentId.isNotEmpty)));
  } else if (n.from.isNotEmpty && n.from != app.uid) {
    openProfile(context, n.from);
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  StreamSubscription<NotificationItem>? _sub;
  final _feedKey = GlobalKey<FeedScreenState>();

  @override
  void initState() {
    super.initState();
    _sub = context.read<AppState>().openRequests.stream.listen((n) {
      if (mounted) openNotificationTarget(context, n);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    final posted = await Navigator.push<bool>(
        context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => const CreatePostScreen()));
    if (posted == true) {
      setState(() => _tab = 0);
      _feedKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pages = [
      FeedScreen(key: _feedKey),
      const ExploreScreen(),
      const SizedBox.shrink(),
      ReelsScreen(active: _tab == 3),
      ProfileScreen(uid: app.uid ?? '', isTab: true),
    ];
    return Scaffold(
      body: Column(
        children: [
          if (!app.connected)
            Material(
              color: FColors.danger,
              child: SafeArea(
                bottom: false,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 5),
                  child: Center(
                    child: Text('İnternet bağlantısı yok',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
          Expanded(child: IndexedStack(index: _tab, children: pages)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        height: 62,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        indicatorColor: Colors.transparent,
        onDestinationSelected: (i) {
          if (i == 2) {
            _create();
            return;
          }
          if (i == 0 && _tab == 0) _feedKey.currentState?.scrollToTop();
          if (i != _tab) FeedVideoState.pauseAll();
          setState(() => _tab = i);
        },
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.home_outlined, size: 28), selectedIcon: Icon(Icons.home_rounded, size: 28), label: 'Ana sayfa'),
          const NavigationDestination(
              icon: Icon(Icons.search_rounded, size: 28),
              selectedIcon: Icon(Icons.manage_search_rounded, size: 28),
              label: 'Keşfet'),
          NavigationDestination(
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(gradient: FColors.brand, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
            ),
            label: 'Oluştur',
          ),
          const NavigationDestination(
              icon: Icon(Icons.slow_motion_video_rounded, size: 28),
              selectedIcon: Icon(Icons.video_library_rounded, size: 28),
              label: 'Reels'),
          NavigationDestination(
            icon: FAvatar(name: app.username, photo: app.me?.photo, size: 28),
            selectedIcon: Container(
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(width: 2, color: Theme.of(context).colorScheme.onSurface)),
              child: FAvatar(name: app.username, photo: app.me?.photo, size: 26),
            ),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}

// ==========================================================================
// AKIŞ
// ==========================================================================

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => FeedScreenState();
}

class FeedScreenState extends State<FeedScreen> {
  final _scroll = ScrollController();
  List<Post> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _followingOnly = false;
  int _limit = 25;
  bool _end = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 800) _more();
    });
    refresh();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void scrollToTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
    }
  }

  Future<void> refresh() async {
    _limit = 25;
    _end = false;
    await _load();
  }

  Future<void> _load() async {
    try {
      final list = await context.read<AppState>().loadFeed(limit: _limit);
      if (!mounted) return;
      setState(() {
        if (list.length < _limit) _end = true;
        _posts = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    if (_loadingMore || _end || _loading) return;
    setState(() => _loadingMore = true);
    _limit += 20;
    await _load();
    if (mounted) setState(() => _loadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final posts = _followingOnly
        ? _posts.where((p) => app.following.contains(p.uid) || p.uid == app.uid).toList()
        : _posts;
    final unread = app.unreadCount;
    return Scaffold(
      appBar: AppBar(
        title: const GradientText('FlinQ', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -1)),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const Icon(Icons.favorite_border_rounded, size: 28),
            ),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            const SliverToBoxAdapter(child: StoriesBar()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Sana özel'),
                      selected: !_followingOnly,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _followingOnly = false),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Takip ettiklerin'),
                      selected: _followingOnly,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _followingOnly = true),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: Divider()),
            if (_loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (posts.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: _followingOnly ? Icons.people_outline : Icons.photo_camera_outlined,
                  title: _followingOnly ? 'Takip ettiklerinden gönderi yok' : 'Henüz gönderi yok',
                  subtitle: _followingOnly ? 'Keşfet\'ten yeni insanlar bul.' : 'İlk paylaşımı sen yap!',
                ),
              )
            else
              SliverList.builder(
                itemCount: posts.length + 1,
                itemBuilder: (_, i) {
                  if (i == posts.length) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: _end
                            ? Text('Hepsi bu kadar ✨', style: TextStyle(color: Theme.of(context).hintColor))
                            : const CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final p = posts[i];
                  return PostCard(
                    key: ValueKey(p.id),
                    post: p,
                    onDeleted: () => setState(() => _posts.removeWhere((x) => x.id == p.id)),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class StoriesBar extends StatelessWidget {
  const StoriesBar({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final owners = app.storyOwners();
    final mineHas = app.stories.containsKey(app.uid);
    app.warmUsers(owners);
    return SizedBox(
      height: 108,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          if (!mineHas)
            _StoryItem(
              name: 'Hikayen',
              photo: app.me?.photo,
              ring: StoryRing.none,
              add: true,
              onTap: () => addStoryFlow(context),
            ),
          for (final o in owners)
            _StoryItem(
              name: o == app.uid ? 'Hikayen' : (app.cachedUser(o)?.username ?? '…'),
              photo: app.cachedUser(o)?.photo,
              ring: app.hasUnseenStory(o) ? StoryRing.unseen : StoryRing.seen,
              add: o == app.uid,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => StoryViewer(owners: owners, startIndex: owners.indexOf(o)),
                ),
              ),
              onAdd: o == app.uid ? () => addStoryFlow(context) : null,
            ),
        ],
      ),
    );
  }
}

class _StoryItem extends StatelessWidget {
  final String name;
  final String? photo;
  final StoryRing ring;
  final bool add;
  final VoidCallback onTap;
  final VoidCallback? onAdd;
  const _StoryItem({
    required this.name,
    required this.photo,
    required this.ring,
    required this.onTap,
    this.add = false,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 80,
        child: Column(
          children: [
            const SizedBox(height: 6),
            Stack(
              children: [
                FAvatar(name: name, photo: photo, size: 64, ring: ring == StoryRing.none ? StoryRing.none : ring),
                if (add)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: onAdd ?? onTap,
                      child: Container(
                        decoration: BoxDecoration(
                          color: FColors.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2.5),
                        ),
                        child: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
