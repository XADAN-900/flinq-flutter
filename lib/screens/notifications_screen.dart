import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _filter = 'all';
  late final AppState _app;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _app.warmUsers(_app.notifications.map((n) => n.from));
  }

  @override
  void dispose() {
    // Ekrandan çıkınca hepsini okundu say.
    _app.markAllRead();
    super.dispose();
  }

  IconData _icon(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite_rounded;
      case 'comment':
        return Icons.mode_comment_rounded;
      case 'reply':
        return Icons.reply_rounded;
      case 'follow':
        return Icons.person_add_alt_1_rounded;
      case 'mention':
        return Icons.alternate_email_rounded;
      case 'milestone':
        return Icons.emoji_events_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _color(String type) {
    switch (type) {
      case 'like':
        return FColors.like;
      case 'follow':
        return FColors.violet;
      case 'milestone':
        return FColors.orange;
      default:
        return FColors.verified;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    var list = app.notifications;
    if (_filter != 'all') {
      list = list.where((n) {
        if (_filter == 'comment') return n.type == 'comment' || n.type == 'reply' || n.type == 'mention';
        return n.type == _filter;
      }).toList();
    }
    final now = DateTime.now();
    final groups = <String, List<NotificationItem>>{};
    for (final n in list) {
      final d = DateTime.fromMillisecondsSinceEpoch(n.time);
      final diff = now.difference(d).inDays;
      final g = isSameDay(d, now) ? 'Bugün' : diff < 7 ? 'Bu hafta' : diff < 30 ? 'Bu ay' : 'Daha önce';
      groups.putIfAbsent(g, () => []).add(n);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirimler'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'read') {
                await app.markAllRead();
              } else if (v == 'clear') {
                final ok = await confirmDialog(context,
                    title: 'Bildirimleri temizle', message: 'Tüm bildirimler silinsin mi?', confirmText: 'Temizle', destructive: true);
                if (ok) await app.clearNotifications();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'read', child: Text('Tümünü okundu yap')),
              PopupMenuItem(value: 'clear', child: Text('Tümünü temizle')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                for (final (k, label) in const [
                  ('all', 'Tümü'),
                  ('like', 'Beğeniler'),
                  ('comment', 'Yorumlar'),
                  ('follow', 'Takipler'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == k,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _filter = k),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'Henüz bildirim yok',
                    subtitle: 'Biri gönderini beğendiğinde ya da seni takip ettiğinde burada görürsün.',
                  )
                : ListView(
                    children: [
                      for (final g in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                          child: Text(g.key, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                        for (final n in g.value)
                          Dismissible(
                            key: ValueKey(n.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: FColors.danger,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(Icons.delete_outline, color: Colors.white),
                            ),
                            onDismissed: (_) => app.deleteNotification(n.id),
                            child: _NotifTile(n: n, icon: _icon(n.type), color: _color(n.type)),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _NotifTile extends StatelessWidget {
  final NotificationItem n;
  final IconData icon;
  final Color color;
  const _NotifTile({required this.n, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final from = app.cachedUser(n.from);
    final follow = n.type == 'follow' && n.from != app.uid;
    final following = app.following.contains(n.from);
    return Material(
      color: n.read ? Colors.transparent : FColors.accent.withValues(alpha: 0.06),
      child: InkWell(
        onTap: () => openNotificationTarget(context, n),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  FAvatar(name: from?.username ?? stripHtml(n.message), photo: from?.photo, size: 46),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                      ),
                      child: Icon(icon, size: 12, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HtmlLite(n.message, style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
                    const SizedBox(height: 2),
                    Text(timeAgo(n.time), style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12.5)),
                  ],
                ),
              ),
              if (follow) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: 32,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      backgroundColor: following ? Theme.of(context).dividerColor : FColors.accent,
                      foregroundColor: following ? Theme.of(context).colorScheme.onSurface : Colors.white,
                    ),
                    onPressed: () => app.toggleFollow(n.from),
                    child: Text(following ? 'Takiptesin' : 'Geri takip et'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
