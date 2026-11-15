import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/dm_service.dart';
import '../services/offline_store.dart';
import '../widgets/common.dart';
import '../widgets/post_card.dart';
import '../widgets/post_image.dart';
import '../widgets/video_thumb.dart';
import 'post_detail_screen.dart';

void openDm(BuildContext context, String otherUid) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => DmChatScreen(otherUid: otherUid)));
}

// ==========================================================================
// GELEN KUTUSU
// ==========================================================================

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  String _q = '';

  Future<void> _newMessage() async {
    final uid = await pickUser(context, title: 'Yeni mesaj');
    if (uid != null && mounted) openDm(context, uid);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final dm = context.watch<DmService>();
    final theme = Theme.of(context);
    final threads = dm.threads.where((t) {
      if (_q.isEmpty) return true;
      final n = app.cachedUser(t.other)?.username ?? '';
      return n.toLowerCase().contains(_q.toLowerCase());
    }).toList();
    return Scaffold(
      appBar: AppBar(
        title: UserName(app.username, verified: app.me?.verified ?? false, fontSize: 20, weight: FontWeight.w800),
        actions: [
          IconButton(icon: const Icon(Icons.edit_square), tooltip: 'Yeni mesaj', onPressed: _newMessage),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(hintText: 'Ara', isDense: true, prefixIcon: Icon(Icons.search_rounded)),
            ),
          ),
          if (dm.error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(dm.error!, style: const TextStyle(color: FColors.danger)),
            ),
          Expanded(
            child: !dm.loaded
                ? const Center(child: CircularProgressIndicator())
                : threads.isEmpty
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const EmptyState(
                            icon: Icons.send_outlined,
                            title: 'Mesajların',
                            subtitle: 'Arkadaşlarına özel fotoğraf ve mesaj gönder, gönderileri paylaş.',
                          ),
                          FilledButton(onPressed: _newMessage, child: const Text('Mesaj gönder')),
                        ],
                      )
                    : ListView.builder(
                        itemCount: threads.length,
                        itemBuilder: (_, i) {
                          final t = threads[i];
                          final u = app.cachedUser(t.other);
                          final unread = t.unread > 0;
                          final mine = t.lastFrom == app.uid;
                          return Dismissible(
                            key: ValueKey(t.chatId),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: FColors.danger,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(Icons.delete_outline, color: Colors.white),
                            ),
                            confirmDismiss: (_) => confirmDialog(context,
                                title: 'Sohbeti sil',
                                message: 'Sohbet senin listenden kaldırılacak. Karşı taraf görmeye devam eder.',
                                confirmText: 'Sil',
                                destructive: true),
                            onDismissed: (_) => dm.hideThread(t.chatId),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              leading: FAvatar(
                                name: u?.username ?? '?',
                                photo: u?.photo,
                                size: 54,
                                ring: app.stories.containsKey(t.other)
                                    ? (app.hasUnseenStory(t.other) ? StoryRing.unseen : StoryRing.seen)
                                    : StoryRing.none,
                              ),
                              title: UserName(u?.username ?? '…',
                                  verified: u?.verified ?? false, weight: unread ? FontWeight.w800 : FontWeight.w600),
                              subtitle: Text(
                                '${mine ? 'Sen: ' : ''}${t.lastText} · ${timeAgo(t.lastTs)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
                                  color: unread ? theme.colorScheme.onSurface : theme.hintColor,
                                ),
                              ),
                              trailing: unread
                                  ? Container(
                                      width: 10,
                                      height: 10,
                                      decoration: const BoxDecoration(color: FColors.verified, shape: BoxShape.circle),
                                    )
                                  : Icon(Icons.photo_camera_outlined, color: theme.hintColor),
                              onTap: () => openDm(context, t.other),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// Kullanıcı seçici (yeni mesaj / gönderi paylaş).
Future<String?> pickUser(BuildContext context, {String title = 'Kişi seç'}) {
  return Navigator.push<String>(context, MaterialPageRoute(builder: (_) => _UserPicker(title: title)));
}

class _UserPicker extends StatefulWidget {
  final String title;
  const _UserPicker({required this.title});

  @override
  State<_UserPicker> createState() => _UserPickerState();
}

class _UserPickerState extends State<_UserPicker> {
  List<FUser>? _all;
  String _q = '';

  @override
  void initState() {
    super.initState();
    context.read<AppState>().allUsers().then((l) {
      if (mounted) setState(() => _all = l);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final list = (_all ?? const <FUser>[])
        .where((u) => u.uid != app.uid)
        .where((u) => _q.isEmpty || u.username.toLowerCase().contains(_q.toLowerCase()))
        .toList()
      ..sort((a, b) {
        final fa = app.following.contains(a.uid), fb = app.following.contains(b.uid);
        if (fa != fb) return fa ? -1 : 1;
        return a.username.toLowerCase().compareTo(b.username.toLowerCase());
      });
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(hintText: 'Ara…', isDense: true, prefixIcon: Icon(Icons.search_rounded)),
            ),
          ),
          Expanded(
            child: _all == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final u = list[i];
                      return ListTile(
                        leading: FAvatar(name: u.username, photo: u.photo, size: 44),
                        title: UserName(u.username, verified: u.verified),
                        subtitle: app.following.contains(u.uid) ? const Text('Takip ediyorsun') : null,
                        onTap: () => Navigator.pop(context, u.uid),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Gönderiyi DM ile gönder ya da başka uygulamada paylaş.
Future<void> sharePostSheet(BuildContext context, Post p) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SharePostSheet(post: p),
  );
}

class _SharePostSheet extends StatefulWidget {
  final Post post;
  const _SharePostSheet({required this.post});

  @override
  State<_SharePostSheet> createState() => _SharePostSheetState();
}

class _SharePostSheetState extends State<_SharePostSheet> {
  final Set<String> _sent = {};
  List<FUser>? _all;
  String _q = '';

  @override
  void initState() {
    super.initState();
    context.read<AppState>().allUsers().then((l) {
      if (mounted) setState(() => _all = l);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final dm = context.read<DmService>();
    final recent = dm.threads.map((t) => t.other).toList();
    final others = (_all ?? const <FUser>[])
        .where((u) => u.uid != app.uid && !recent.contains(u.uid))
        .toList()
      ..sort((a, b) {
        final fa = app.following.contains(a.uid), fb = app.following.contains(b.uid);
        if (fa != fb) return fa ? -1 : 1;
        return a.username.compareTo(b.username);
      });
    final ids = [...recent, ...others.map((u) => u.uid)]
        .where((id) => _q.isEmpty || (app.cachedUser(id)?.username ?? '').toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(hintText: 'Kime gönderilsin?', isDense: true, prefixIcon: Icon(Icons.search)),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: ids.length,
              itemBuilder: (_, i) {
                final id = ids[i];
                final u = app.cachedUser(id);
                final sent = _sent.contains(id);
                return ListTile(
                  leading: FAvatar(name: u?.username ?? '?', photo: u?.photo, size: 44),
                  title: UserName(u?.username ?? '…', verified: u?.verified ?? false),
                  trailing: SizedBox(
                    width: 112,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        backgroundColor: sent ? Theme.of(context).dividerColor : FColors.accent,
                        foregroundColor: sent ? Theme.of(context).colorScheme.onSurface : Colors.white,
                      ),
                      onPressed: sent
                          ? null
                          : () async {
                              setState(() => _sent.add(id));
                              try {
                                await dm.send(id, type: 'post', postId: widget.post.id);
                              } catch (_) {
                                if (mounted) setState(() => _sent.remove(id));
                              }
                            },
                      // Yazı her zaman tek satır kalsın (büyük yazı boyutunda küçülür, alta kaymaz).
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(sent ? 'Gönderildi' : 'Gönder', maxLines: 1, softWrap: false),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.ios_share_rounded),
            title: const Text('Başka uygulamada paylaş'),
            onTap: () {
              final p = widget.post;
              Navigator.pop(context);
              Share.share(p.type == 'text'
                  ? '"${p.caption}" — @${p.username} FlinQ\'da'
                  : '@${p.username} FlinQ\'da bir gönderi paylaştı${p.caption.isNotEmpty ? ': ${p.caption}' : ''}');
            },
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

// ==========================================================================
// SOHBET
// ==========================================================================

class DmChatScreen extends StatefulWidget {
  final String otherUid;
  const DmChatScreen({super.key, required this.otherUid});

  @override
  State<DmChatScreen> createState() => _DmChatScreenState();
}

class _DmChatScreenState extends State<DmChatScreen> with WidgetsBindingObserver {
  late final AppState app;
  late final DmService dm;
  late final String chatId;
  final List<DmMessage> _msgs = [];
  final List<StreamSubscription> _subs = [];
  final _input = TextEditingController();
  bool _loaded = false;
  int _seenTs = 0;
  bool _otherTyping = false;
  bool _sendingImage = false;
  final Map<String, Future<Post?>> _postFutures = {};

  @override
  void initState() {
    super.initState();
    app = context.read<AppState>();
    dm = context.read<DmService>();
    chatId = DmService.chatIdFor(app.uid ?? '', widget.otherUid);
    dm.activeChat = chatId;
    WidgetsBinding.instance.addObserver(this);
    app.userById(widget.otherUid);
    _loadOffline();
    final q = dm.messages(chatId).orderByKey().limitToLast(30);
    q.get().then((_) {
      if (mounted) setState(() => _loaded = true);
    }).catchError((_) {
      if (mounted) setState(() => _loaded = true);
    });
    _subs.add(q.onChildAdded.listen((e) {
      final k = e.snapshot.key;
      if (k == null || _msgs.any((m) => m.id == k)) return;
      final m = DmMessage.fromMap(k, asMap(e.snapshot.value));
      _msgs.add(m);
      _msgs.sort((a, b) => a.id.compareTo(b.id));
      if (m.from != app.uid) dm.markRead(chatId);
      _saveOfflineSoon();
      if (mounted) setState(() {});
    }, onError: (_) {}));
    _subs.add(q.onChildChanged.listen((e) {
      final k = e.snapshot.key;
      final i = _msgs.indexWhere((m) => m.id == k);
      if (i >= 0 && k != null) {
        _msgs[i] = DmMessage.fromMap(k, asMap(e.snapshot.value));
        _saveOfflineSoon();
        if (mounted) setState(() {});
      }
    }, onError: (_) {}));
    _subs.add(q.onChildRemoved.listen((e) async {
      final k = e.snapshot.key;
      if (k == null || !app.connected) return;
      try {
        final s = await dm.messages(chatId).child(k).get();
        if (s.exists) return; // pencereden düştü, silinmedi
      } catch (_) {}
      _msgs.removeWhere((m) => m.id == k);
      _saveOfflineSoon();
      if (mounted) setState(() {});
    }, onError: (_) {}));
    _subs.add(app.db.ref('chats/$chatId/seen/${widget.otherUid}').onValue.listen((e) {
      if (mounted) setState(() => _seenTs = asInt(e.snapshot.value));
    }, onError: (_) {}));
    _subs.add(app.db.ref('chats/$chatId/typing/${widget.otherUid}').onValue.listen((e) {
      final ts = asInt(e.snapshot.value);
      final on = ts > 0 && DateTime.now().millisecondsSinceEpoch - ts < 10000;
      if (mounted && on != _otherTyping) setState(() => _otherTyping = on);
    }, onError: (_) {}));
    dm.markRead(chatId);
    _input.addListener(() {
      if (_input.text.trim().isNotEmpty) dm.setTyping(chatId, true);
      setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) dm.markRead(chatId);
  }

  // ---------- Çevrimdışı kopya: internet yokken de son mesajlar görünsün ----------
  Timer? _offlineSave;

  Future<void> _loadOffline() async {
    final v = await OfflineStore.read('dmc_$chatId');
    if (!mounted || v is! List) return;
    var added = false;
    for (final e in v) {
      final m = asMap(e);
      final id = asStr(m['id']);
      if (id.isEmpty || _msgs.any((x) => x.id == id)) continue;
      _msgs.add(DmMessage.fromMap(id, m));
      added = true;
    }
    if (added) {
      _msgs.sort((a, b) => a.id.compareTo(b.id));
      setState(() => _loaded = true);
    }
  }

  void _saveOfflineSoon() {
    _offlineSave?.cancel();
    _offlineSave = Timer(const Duration(seconds: 2), _writeOffline);
  }

  void _writeOffline() {
    var media = 0;
    final list = <Object?>[];
    for (final m in _msgs.reversed.take(30)) {
      final map = <String, Object?>{'id': m.id, ...m.toMap()};
      if (m.url.isNotEmpty) {
        if (m.url.length > 1500 * 1024 || media + m.url.length > 5 * 1024 * 1024) {
          map.remove('url');
        } else {
          media += m.url.length;
        }
      }
      list.add(map);
    }
    OfflineStore.write('dmc_$chatId', list.reversed.toList());
    OfflineStore.prune('dmc_', 15);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (dm.activeChat == chatId) dm.activeChat = null;
    dm.setTyping(chatId, false);
    if (_offlineSave?.isActive ?? false) {
      _offlineSave!.cancel();
      _writeOffline();
    }
    for (final s in _subs) {
      s.cancel();
    }
    _input.dispose();
    super.dispose();
  }

  Future<void> _send({String type = 'text', String? url}) async {
    final text = _input.text.trim();
    if (type == 'text' && text.isEmpty) return;
    if (type == 'text') _input.clear();
    HapticFeedback.selectionClick();
    try {
      await dm.send(widget.otherUid, text: type == 'text' ? text : '', type: type, url: url);
    } catch (e) {
      if (type == 'text') _input.text = text;
      if (mounted) {
        showSnack(context, 'Mesaj gönderilemedi. Veritabanı kurallarında "chats" yoluna izin olmalı.', error: true);
      }
    }
  }

  Future<void> _sendImage(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src, maxWidth: 1080, maxHeight: 1080, imageQuality: 72);
    if (x == null) return;
    setState(() => _sendingImage = true);
    final b = await x.readAsBytes();
    await _send(type: 'image', url: toDataUrl(b, 'image/jpeg'));
    if (mounted) setState(() => _sendingImage = false);
  }

  Future<Post?> _post(String id) => _postFutures.putIfAbsent(id, () async {
        final p = await app.loadPost(id);
        if (p != null) await app.warmUsers([p.uid]);
        return p;
      });

  void _actions(DmMessage m) {
    final mine = m.from == app.uid;
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (m.type == 'text')
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Kopyala'),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: m.text));
                showSnack(context, 'Kopyalandı');
              },
            ),
          if (mine)
            ListTile(
              leading: const Icon(Icons.undo_rounded, color: FColors.danger),
              title: const Text('Gönderimi geri al', style: TextStyle(color: FColors.danger)),
              onTap: () {
                Navigator.pop(ctx);
                dm.unsend(chatId, m.id, wasLast: _msgs.isNotEmpty && _msgs.last.id == m.id, other: widget.otherUid);
              },
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appW = context.watch<AppState>();
    final other = appW.cachedUser(widget.otherUid);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final reversed = _msgs.reversed.toList();
    String? lastMineSeenId;
    for (final m in reversed) {
      if (m.from == app.uid) {
        if (_seenTs >= m.ts && m.ts > 0) lastMineSeenId = m.id;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () => openProfile(context, widget.otherUid),
          child: Row(children: [
            FAvatar(name: other?.username ?? '?', photo: other?.photo, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                UserName(other?.username ?? '…', verified: other?.verified ?? false, fontSize: 16),
                Text(
                  _otherTyping ? 'yazıyor…' : '@${other?.username ?? ''}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: _otherTyping ? FColors.accent : theme.hintColor),
                ),
              ]),
            ),
          ]),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    itemCount: reversed.length + 1,
                    itemBuilder: (_, i) {
                      if (i == reversed.length) return _intro(other);
                      final m = reversed[i];
                      final mine = m.from == app.uid;
                      final older = i + 1 < reversed.length ? reversed[i + 1] : null;
                      final showTime = older == null || (m.ts - older.ts) > 30 * 60 * 1000;
                      return Column(
                        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          if (showTime && m.ts > 0)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Text('${formatDayHeader(m.ts)} ${formatClock(m.ts)}',
                                    style: TextStyle(fontSize: 12, color: theme.hintColor)),
                              ),
                            ),
                          GestureDetector(
                            onLongPress: () => _actions(m),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: _bubble(m, mine, dark),
                            ),
                          ),
                          if (m.id == lastMineSeenId)
                            Padding(
                              padding: const EdgeInsets.only(top: 2, right: 4),
                              child: Text('Görüldü', style: TextStyle(fontSize: 11.5, color: theme.hintColor)),
                            ),
                        ],
                      );
                    },
                  ),
          ),
          if (_otherTyping)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${other?.username ?? ''} yazıyor…',
                    style: TextStyle(color: theme.hintColor, fontStyle: FontStyle.italic, fontSize: 12.5)),
              ),
            ),
          SafeArea(
            top: false,
            child: Container(
              margin: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: dark ? FColors.darkCard : const Color(0xFFF1F2F5),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(5),
                    child: GestureDetector(
                      onTap: _sendingImage ? null : () => _sendImage(ImageSource.camera),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: FColors.brand),
                        child: _sendingImage
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Mesaj…',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                      ),
                    ),
                  ),
                  if (_input.text.trim().isEmpty) ...[
                    IconButton(
                      icon: const Icon(Icons.image_outlined),
                      onPressed: _sendingImage ? null : () => _sendImage(ImageSource.gallery),
                    ),
                    IconButton(
                      icon: const Icon(Icons.favorite_border_rounded),
                      onPressed: () => _send(type: 'heart'),
                    ),
                  ] else
                    TextButton(
                      onPressed: () => _send(),
                      child: const Text('Gönder', style: TextStyle(fontWeight: FontWeight.w800, color: FColors.accent)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _intro(FUser? u) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          FAvatar(name: u?.username ?? '?', photo: u?.photo, size: 92),
          const SizedBox(height: 10),
          UserName(u?.username ?? '', verified: u?.verified ?? false, fontSize: 19, weight: FontWeight.w800),
          if ((u?.bio ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 4, 30, 0),
              child: Text(u!.bio, textAlign: TextAlign.center, style: TextStyle(color: theme.hintColor)),
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => openProfile(context, widget.otherUid),
            child: const Text('Profili gör'),
          ),
        ],
      ),
    );
  }

  Widget _bubble(DmMessage m, bool mine, bool dark) {
    final maxW = MediaQuery.of(context).size.width * 0.72;
    switch (m.type) {
      case 'heart':
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text('❤️', style: TextStyle(fontSize: 46)),
        );
      case 'image':
        final b = MediaCache.bytes(m.url);
        return GestureDetector(
          onTap: b == null
              ? null
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        backgroundColor: Colors.black,
                        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
                        body: Center(child: InteractiveViewer(maxScale: 5, child: Image.memory(b))),
                      ),
                    ),
                  ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: b == null
                ? Container(width: 200, height: 200, color: Colors.black12)
                : ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxW, maxHeight: 320),
                    child: Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 800),
                  ),
          ),
        );
      case 'post':
        return FutureBuilder<Post?>(
          future: _post(m.postId),
          builder: (context, snap) {
            final p = snap.data;
            final width = maxW * 0.85;
            if (snap.connectionState != ConnectionState.done) {
              return Container(
                width: width,
                height: 220,
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(18)),
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            if (p == null) {
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: dark ? FColors.darkCard : const Color(0xFFEFEFF2),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text('Bu gönderi artık yok'),
              );
            }
            final author = app.cachedUser(p.uid);
            Widget media;
            if (p.type == 'text') {
              media = TextPostCard(text: p.caption, seed: p.id, small: true);
            } else if (p.type == 'video') {
              media = VideoThumb(postId: p.id, showPlayIcon: true);
            } else {
              media = PostImage(postId: p.id, cacheWidth: 600);
            }
            return GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: p.id))),
              child: Container(
                width: width,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: dark ? FColors.darkCard : const Color(0xFFEFEFF2),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(children: [
                        FAvatar(name: p.username, photo: author?.photo, size: 26),
                        const SizedBox(width: 8),
                        Flexible(child: UserName(author?.username ?? p.username, verified: author?.verified ?? false, fontSize: 13)),
                      ]),
                    ),
                    AspectRatio(aspectRatio: 1, child: media),
                    if (p.caption.isNotEmpty && p.type != 'text')
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(p.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      default:
        return Container(
          constraints: BoxConstraints(maxWidth: maxW),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: mine
                ? const LinearGradient(colors: [Color(0xFF7B61FF), Color(0xFFFF3D71)])
                : null,
            color: mine ? null : (dark ? FColors.darkCard : const Color(0xFFEFEFF2)),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Text(m.text, style: TextStyle(color: mine ? Colors.white : null, fontSize: 15.5)),
        );
    }
  }
}
