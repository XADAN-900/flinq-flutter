import 'package:flutter/material.dart';
import 'package:flinq/core/i18n.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/report_sheet.dart';
import '../widgets/common.dart';
import '../widgets/post_card.dart';
import 'dm_screens.dart';
import 'edit_profile_screen.dart';
import 'explore_screen.dart';
import 'settings_screen.dart';
import 'story_viewer.dart';

class ProfileScreen extends StatefulWidget {
  final String uid;
  final bool isTab;
  const ProfileScreen({super.key, required this.uid, this.isTab = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  FUser? _user;
  List<Post>? _posts;
  List<Post>? _saved;
  int _followers = 0;
  int _following = 0;
  bool _loading = true;
  bool _followsMe = false;
  bool _savedLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.uid.isEmpty) return;
    final app = context.read<AppState>();
    final results = await Future.wait([
      app.userById(widget.uid, refresh: true),
      app.loadUserPosts(widget.uid),
      app.followersOf(widget.uid),
      app.followingOf(widget.uid),
    ]);
    if (!mounted) return;
    setState(() {
      _user = results[0] as FUser?;
      _posts = results[1] as List<Post>;
      _followers = (results[2] as Set<String>).length;
      _following = (results[3] as Set<String>).length;
      _followsMe = (results[3] as Set<String>).contains(app.uid);
      _loading = false;
    });
  }

  Future<void> _loadSaved() async {
    if (_savedLoading) return;
    _savedLoading = true;
    final app = context.read<AppState>();
    final ids = app.me?.saved.toList() ?? const <String>[];
    final posts = await Future.wait(ids.map(app.loadPost));
    _savedLoading = false;
    if (!mounted) return;
    setState(() => _saved = posts.whereType<Post>().toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp)));
  }

  Future<void> _toggleFollow(AppState app) async {
    final was = app.following.contains(widget.uid);
    setState(() => _followers += was ? -1 : 1);
    await app.toggleFollow(widget.uid);
  }

  void _openList(bool followers) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FollowListScreen(uid: widget.uid, followers: followers)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final mine = widget.uid == app.uid;
    final u = mine ? (app.me ?? _user) : _user;
    final theme = Theme.of(context);
    final hasStory = app.stories.containsKey(widget.uid);
    final isFollowing = app.following.contains(widget.uid);
    final blocked = !mine && app.isBlocked(widget.uid);

    if (_loading && u == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    if (u == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.person_off_outlined, title: 'Kullanıcı bulunamadı'));
    }

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: hasStory
                    ? () {
                        final owners = app.storyOwners();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            fullscreenDialog: true,
                            builder: (_) => StoryViewer(owners: owners, startIndex: owners.indexOf(widget.uid)),
                          ),
                        );
                      }
                    : (mine ? () => addStoryFlow(context) : null),
                child: FAvatar(
                  name: u.username,
                  photo: u.photo,
                  size: 86,
                  ring: hasStory
                      ? (app.hasUnseenStory(widget.uid) ? StoryRing.unseen : StoryRing.seen)
                      : StoryRing.none,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Count(n: _posts?.length ?? 0, label: 'gönderi'),
                    _Count(n: _followers, label: 'takipçi', onTap: () => _openList(true)),
                    _Count(n: _following, label: 'takip', onTap: () => _openList(false)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          UserName(u.username, verified: u.verified, fontSize: 15),
          if (u.bio.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: RichCaption(
                text: u.bio,
                trimAt: 300,
                onHashtag: (t) => openHashtag(context, t),
                onMention: (n) => openProfileByUsername(context, n),
              ),
            ),
          if (!mine && _followsMe)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: T('Seni takip ediyor', style: TextStyle(color: theme.hintColor, fontSize: 12.5)),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (mine) ...[
                Expanded(
                  child: _Btn(
                    label: 'Profili düzenle',
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen()));
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _Btn(
                    label: 'Profili paylaş',
                    onTap: () => Share.share('FlinQ\'da beni takip et: @${u.username}'),
                  ),
                ),
              ] else if (blocked) ...[
                Expanded(
                  child: _Btn(
                    label: 'Engeli kaldır',
                    primary: true,
                    onTap: () async {
                      await app.setBlocked(widget.uid, false);
                      _load();
                    },
                  ),
                ),
              ] else ...[
                Expanded(
                  child: _Btn(
                    label: isFollowing ? 'Takiptesin' : 'Takip et',
                    primary: !isFollowing,
                    onTap: () => _toggleFollow(app),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _Btn(label: 'Mesaj', onTap: () => openDm(context, widget.uid)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _Btn(
                    label: 'Paylaş',
                    onTap: () => Share.share('FlinQ\'da @${u.username} hesabına göz at!'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );

    // Profil grid'inde yalnızca fotoğraf ve videolar yer alır; Fly (metin) gönderileri burada gösterilmez.
    final gridPosts = (_posts ?? const <Post>[]).where((p) => p.type != 'text').toList();
    final postsTab = blocked
        ? const EmptyState(
            icon: Icons.block_rounded,
            title: 'Bu hesabı engelledin',
            subtitle: 'Engeli kaldırırsan gönderilerini tekrar görebilirsin.',
          )
        : _posts == null
        ? const Center(child: CircularProgressIndicator())
        : gridPosts.isEmpty
            ? EmptyState(
                icon: Icons.photo_camera_outlined,
                title: mine ? 'İlk gönderini paylaş' : 'Henüz gönderi yok',
                subtitle: mine ? 'Paylaştığın fotoğraf ve videolar burada görünür.' : null,
              )
            : PostGrid(posts: gridPosts);

    final tabs = <Widget>[
      const Tab(icon: Icon(Icons.grid_on_rounded)),
      const Tab(icon: Icon(Icons.bolt_rounded)),
      if (mine) const Tab(icon: Icon(Icons.bookmark_border_rounded)),
    ];
    // İkinci sekme: kullanıcının Fly (metin) gönderileri, tweet gibi liste halinde.
    final flies = (_posts ?? const <Post>[]).where((p) => p.type == 'text').toList();
    final views = <Widget>[
      postsTab,
      flies.isEmpty
          ? EmptyState(
              icon: Icons.bolt_rounded,
              title: mine ? 'İlk Fly’ını paylaş' : 'Henüz Fly yok',
              subtitle: mine ? 'Paylaştığın Fly’lar burada görünür.' : null,
            )
          : ListView.builder(
              padding: const EdgeInsets.only(top: 6),
              itemCount: flies.length,
              itemBuilder: (_, i) => PostCard(post: flies[i]),
            ),
      if (mine)
        Builder(builder: (_) {
          if (_saved == null) {
            _loadSaved();
            return const Center(child: CircularProgressIndicator());
          }
          return _saved!.isEmpty
              ? const EmptyState(
                  icon: Icons.bookmark_border_rounded,
                  title: 'Kaydedilenler',
                  subtitle: 'Kaydettiğin gönderiler sadece sana görünür.',
                )
              : PostGrid(posts: _saved!);
        }),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.isTab,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mine) const Icon(Icons.lock_outline_rounded, size: 18),
              if (mine) const SizedBox(width: 4),
              Flexible(child: UserName(u.username, verified: u.verified, fontSize: 20, weight: FontWeight.w800)),
            ],
          ),
          actions: [
            if (!mine)
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'report') {
                    final reason = await pickReportReason(context, title: '@${u.username} şikayet et');
                    if (reason == null) return;
                    await app.report(type: 'user', targetUid: widget.uid, preview: u.bio, reason: reason).catchError((_) {});
                    if (context.mounted) showSnack(context, tr('Şikayetin yöneticiye iletildi. Teşekkürler.'));
                    return;
                  }
                  if (v != 'block') return;
                  final ok = await confirmDialog(context,
                      title: blocked ? 'Engeli kaldır' : '@${u.username} engellensin mi?',
                      message: blocked
                          ? 'Gönderilerini tekrar göreceksin ve sana mesaj gönderebilecek.'
                          : 'Sana mesaj gönderemeyecek; gönderileri, yorumları ve hikayeleri sana görünmeyecek. '
                              'Engellediğini ona bildirmeyiz.',
                      confirmText: blocked ? 'Kaldır' : 'Engelle',
                      destructive: !blocked);
                  if (!ok) return;
                  await app.setBlocked(widget.uid, !blocked);
                  _load();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'report', child: T('Şikayet et')),
                  PopupMenuItem(value: 'block', child: Text(blocked ? 'Engeli kaldır' : 'Engelle')),
                ],
              ),
            if (mine) ...[
              IconButton(icon: const Icon(Icons.add_box_outlined), onPressed: () => addStoryFlow(context)),
              IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ],
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            _saved = null;
            await _load();
          },
          notificationPredicate: (n) => n.depth == 0 || n.depth == 2,
          child: NestedScrollView(
            headerSliverBuilder: (_, __) => [
              SliverToBoxAdapter(child: header),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabHeader(
                  TabBar(
                    tabs: tabs,
                    indicatorColor: theme.colorScheme.onSurface,
                    labelColor: theme.colorScheme.onSurface,
                    unselectedLabelColor: theme.hintColor,
                    indicatorSize: TabBarIndicatorSize.tab,
                  ),
                  theme.scaffoldBackgroundColor,
                ),
              ),
            ],
            body: TabBarView(children: views),
          ),
        ),
      ),
    );
  }
}

class _TabHeader extends SliverPersistentHeaderDelegate {
  final TabBar bar;
  final Color color;
  _TabHeader(this.bar, this.color);

  @override
  double get minExtent => bar.preferredSize.height;
  @override
  double get maxExtent => bar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(color: color, child: bar);

  @override
  bool shouldRebuild(covariant _TabHeader old) => old.bar != bar || old.color != color;
}

class _Count extends StatelessWidget {
  final int n;
  final String label;
  final VoidCallback? onTap;
  const _Count({required this.n, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Text('$n', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
}

class _Btn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _Btn({required this.label, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: primary ? FColors.accent : (dark ? const Color(0xFF262A33) : const Color(0xFFEFEFF2)),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          height: 36,
          child: Center(
            child: Text(label,
                style: TextStyle(fontWeight: FontWeight.w700, color: primary ? Colors.white : null)),
          ),
        ),
      ),
    );
  }
}

class FollowListScreen extends StatefulWidget {
  final String uid;
  final bool followers;
  const FollowListScreen({super.key, required this.uid, required this.followers});

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  List<FUser>? _users;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final ids = widget.followers ? await app.followersOf(widget.uid) : await app.followingOf(widget.uid);
    final users = await Future.wait(ids.map((id) => app.userById(id)));
    if (!mounted) return;
    setState(() => _users = users.whereType<FUser>().toList()
      ..sort((a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase())));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final list = (_users ?? const <FUser>[])
        .where((u) => _q.isEmpty || u.username.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.followers ? 'Takipçiler' : 'Takip edilenler')),
      body: _users == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v.trim()),
                    decoration: InputDecoration(hintText: tr('Ara'), isDense: true, prefixIcon: Icon(Icons.search)),
                  ),
                ),
                Expanded(
                  child: list.isEmpty
                      ? const EmptyState(icon: Icons.people_outline, title: 'Kimse yok')
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final u = list[i];
                            final f = app.following.contains(u.uid);
                            return ListTile(
                              leading: FAvatar(name: u.username, photo: u.photo, size: 44),
                              title: UserName(u.username, verified: u.verified),
                              subtitle: u.bio.isEmpty ? null : Text(u.bio, maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: u.uid == app.uid
                                  ? null
                                  : SizedBox(
                                      width: 110,
                                      child: _Btn(
                                        label: f ? 'Takiptesin' : 'Takip et',
                                        primary: !f,
                                        onTap: () => app.toggleFollow(u.uid),
                                      ),
                                    ),
                              onTap: () => openProfile(context, u.uid),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
