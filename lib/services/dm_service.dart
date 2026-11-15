import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../core/utils.dart';
import 'app_state.dart';
import 'native_bridge.dart';
import 'offline_store.dart';
import 'notification_service.dart';

class DmMessage {
  final String id;
  final String from;
  final String text;
  final String type; // text | image | post | heart
  final String url;
  final String postId;
  final int ts;
  final int duration; // sesli mesaj: saniye
  final bool media; // video ayrı düğümde (chats/{id}/media/{msgId})
  final Map<String, Object?>? replyTo; // {id, from, text}
  final Map<String, String> reactions; // uid -> emoji

  const DmMessage({
    required this.id,
    required this.from,
    required this.text,
    required this.type,
    this.url = '',
    this.postId = '',
    this.ts = 0,
    this.duration = 0,
    this.media = false,
    this.replyTo,
    this.reactions = const {},
  });

  Map<String, Object?> toMap() => {
        'from': from,
        'text': text,
        'type': type,
        if (url.isNotEmpty) 'url': url,
        if (postId.isNotEmpty) 'postId': postId,
        'ts': ts,
        if (duration > 0) 'duration': duration,
        if (media) 'media': true,
        if (replyTo != null) 'replyTo': replyTo,
        if (reactions.isNotEmpty) 'reactions': reactions,
      };

  factory DmMessage.fromMap(String id, Map<String, dynamic> m) => DmMessage(
        id: id,
        from: asStr(m['from']),
        text: asStr(m['text']),
        type: asStr(m['type'], 'text'),
        url: asStr(m['url']),
        postId: asStr(m['postId']),
        ts: asInt(m['ts']),
        duration: asInt(m['duration']),
        media: asBool(m['media']),
        replyTo: asMap(m['replyTo']).isEmpty ? null : asMap(m['replyTo']),
        reactions: asMap(m['reactions']).map((k, v) => MapEntry(k, asStr(v))),
      );
}

class DmThread {
  final String chatId;
  final String other;
  final String lastText;
  final int lastTs;
  final String lastFrom;
  final int unread;

  const DmThread({
    required this.chatId,
    required this.other,
    this.lastText = '',
    this.lastTs = 0,
    this.lastFrom = '',
    this.unread = 0,
  });

  Map<String, Object?> toMap() => {
        'with': other,
        'lastText': lastText,
        'lastTs': lastTs,
        'lastFrom': lastFrom,
        'unread': unread,
      };

  factory DmThread.fromMap(String id, Map<String, dynamic> m) => DmThread(
        chatId: id,
        other: asStr(m['with']),
        lastText: asStr(m['lastText']),
        lastTs: asInt(m['lastTs']),
        lastFrom: asStr(m['lastFrom']),
        unread: asInt(m['unread']),
      );
}

/// Direkt mesajlar.
/// Veri yapısı:
///   chats/{chatId}/messages/{id}  -> {from, text, type, url?, postId?, ts}
///   chats/{chatId}/members/{uid}  -> true
///   chats/{chatId}/seen/{uid}     -> zaman (görüldü)
///   chats/{chatId}/typing/{uid}   -> zaman (yazıyor)
///   userChats/{uid}/{chatId}      -> {with, lastText, lastTs, lastFrom, unread}
class DmService extends ChangeNotifier {
  DmService(this.app) {
    app.addListener(_sync);
    _sync();
  }

  final AppState app;
  FirebaseDatabase get db => app.db;

  String? _uid;
  StreamSubscription? _sub;
  List<DmThread> threads = [];
  bool loaded = false;
  String? error;
  String? activeChat;

  int get unreadTotal => threads.fold(0, (s, t) => s + (t.unread > 0 ? 1 : 0));

  static String chatIdFor(String a, String b) {
    final l = [a, b]..sort();
    return l.join('_');
  }

  void _sync() {
    final u = app.uid;
    if (u == _uid) return;
    _sub?.cancel();
    _sub = null;
    threads = [];
    loaded = false;
    error = null;
    _uid = u;
    if (u == null) {
      notifyListeners();
      return;
    }
    var first = true;
    // İnternetsizken de sohbet listesi görünsün: cihazdaki kopya.
    OfflineStore.read('dm_threads_$u').then((v) {
      if (loaded || _uid != u) return;
      final list = asMap(v)
          .entries
          .map((x) => DmThread.fromMap(x.key, asMap(x.value)))
          .where((t) => t.other.isNotEmpty)
          .toList()
        ..sort((a, b) => b.lastTs.compareTo(a.lastTs));
      if (list.isEmpty) return;
      threads = list;
      loaded = true;
      notifyListeners();
    });
    _sub = db.ref('userChats/$u').onValue.listen((e) {
      final prev = {for (final t in threads) t.chatId: t};
      final list = asMap(e.snapshot.value)
          .entries
          .map((x) => DmThread.fromMap(x.key, asMap(x.value)))
          .where((t) => t.other.isNotEmpty && !app.isBlocked(t.other))
          .toList()
        ..sort((a, b) => b.lastTs.compareTo(a.lastTs));
      if (!first) {
        for (final t in list) {
          final p = prev[t.chatId];
          if (t.unread > (p?.unread ?? 0) && t.lastFrom != u && activeChat != t.chatId) _notify(t);
        }
      }
      first = false;
      threads = list;
      loaded = true;
      app.warmUsers(list.map((t) => t.other));
      notifyListeners();
      OfflineStore.write('dm_threads_$u', {for (final t in list.take(30)) t.chatId: t.toMap()});
    }, onError: (Object e) {
      loaded = true;
      error = 'Mesajlar yüklenemedi. Veritabanı kurallarında "userChats" ve "chats" yollarına izin olmalı.';
      notifyListeners();
    });
  }

  void _notify(DmThread t) {
    if (app.foreground || !app.notifEnabled || NativeBridge.active) return;
    final name = app.cachedUser(t.other)?.username ?? 'FlinQ';
    NotificationService.show(
      id: 'dm_${t.chatId}',
      title: name,
      body: t.lastText.isEmpty ? 'Yeni mesaj' : t.lastText,
      payload: 'dm:${t.other}',
      silent: !app.notifSound,
      showContent: app.notifPreview,
    );
  }

  DatabaseReference messages(String chatId) => db.ref('chats/$chatId/messages');

  static String previewOf(String type, String text) {
    switch (type) {
      case 'image':
        return '📷 Fotoğraf';
      case 'post':
        return '📎 Bir gönderi paylaştı';
      case 'heart':
        return '❤️';
      case 'voice':
        return '🎤 Sesli mesaj';
      case 'video':
        return '🎥 Video';
      default:
        return text.length > 80 ? '${text.substring(0, 80)}…' : text;
    }
  }

  Future<void> send(String other,
      {String text = '',
      String type = 'text',
      String? url,
      String? postId,
      int duration = 0,
      Map<String, Object?>? replyTo}) async {
    final me = _uid;
    if (me == null || other.isEmpty || other == me) return;
    final chatId = chatIdFor(me, other);
    final preview = previewOf(type, text);
    final ref = messages(chatId).push();
    // Videolar mesaj listesine gömülmez (sohbet açılırken hepsi inmesin): ayrı düğüm.
    final separate = type == 'video' && url != null;
    if (separate) await db.ref('chats/$chatId/media/${ref.key}').set(url);
    await ref.set({
      'from': me,
      'text': text,
      'type': type,
      if (url != null && !separate) 'url': url,
      if (separate) 'media': true,
      if (postId != null) 'postId': postId,
      if (duration > 0) 'duration': duration,
      if (replyTo != null) 'replyTo': replyTo,
      'ts': ServerValue.timestamp,
    });
    await db.ref().update({
      'chats/$chatId/members/$me': true,
      'chats/$chatId/members/$other': true,
      'userChats/$me/$chatId/with': other,
      'userChats/$me/$chatId/lastText': preview,
      'userChats/$me/$chatId/lastTs': ServerValue.timestamp,
      'userChats/$me/$chatId/lastFrom': me,
      'userChats/$me/$chatId/unread': 0,
      'userChats/$other/$chatId/with': me,
      'userChats/$other/$chatId/lastText': preview,
      'userChats/$other/$chatId/lastTs': ServerValue.timestamp,
      'userChats/$other/$chatId/lastFrom': me,
    });
    await db.ref('userChats/$other/$chatId/unread').runTransaction((v) => Transaction.success(asInt(v) + 1));
    await setTyping(chatId, false);
  }

  Future<void> markRead(String chatId) async {
    final me = _uid;
    if (me == null) return;
    try {
      await db.ref('chats/$chatId/seen/$me').set(ServerValue.timestamp);
      final has = threads.any((t) => t.chatId == chatId && t.unread > 0);
      if (has) await db.ref('userChats/$me/$chatId/unread').set(0);
    } catch (_) {}
  }

  bool _typing = false;
  Timer? _typingOff;

  Future<void> setTyping(String chatId, bool on) async {
    final me = _uid;
    if (me == null) return;
    _typingOff?.cancel();
    final r = db.ref('chats/$chatId/typing/$me');
    try {
      if (on) {
        _typingOff = Timer(const Duration(seconds: 4), () => setTyping(chatId, false));
        if (_typing) return;
        _typing = true;
        await r.set(ServerValue.timestamp);
        r.onDisconnect().remove();
      } else {
        if (!_typing) return;
        _typing = false;
        await r.remove();
      }
    } catch (_) {}
  }

  /// Mesaja tepki (aynı emojiye tekrar basınca kaldırır).
  Future<void> react(String chatId, DmMessage m, String emoji) async {
    final me = _uid;
    if (me == null) return;
    final r = messages(chatId).child('${m.id}/reactions/$me');
    if (m.reactions[me] == emoji) {
      await r.remove();
    } else {
      await r.set(emoji);
    }
  }

  final Map<String, Future<String?>> _media = {};

  /// Ayrı saklanan video verisi (gerektiğinde indirilir, en fazla 3 tanesi bellekte).
  Future<String?> mediaOf(String chatId, DmMessage m) {
    if (m.url.isNotEmpty) return Future.value(m.url);
    final k = '$chatId/${m.id}';
    final hit = _media[k];
    if (hit != null) return hit;
    final f = db.ref('chats/$chatId/media/${m.id}').get().then((s) => asStrOrNull(s.value)).catchError((_) => null);
    if (_media.length >= 3) _media.remove(_media.keys.first);
    _media[k] = f;
    return f;
  }

  Future<void> unsend(String chatId, String msgId, {bool wasLast = false, String other = ''}) async {
    final me = _uid;
    await messages(chatId).child(msgId).remove();
    await db.ref('chats/$chatId/media/$msgId').remove().catchError((_) {});
    if (wasLast && me != null) {
      final up = <String, Object?>{'userChats/$me/$chatId/lastText': 'Mesaj geri alındı'};
      if (other.isNotEmpty) up['userChats/$other/$chatId/lastText'] = 'Mesaj geri alındı';
      try {
        await db.ref().update(up);
      } catch (_) {}
    }
  }

  /// Sohbeti sadece kendi listemden kaldırır (karşı taraf görmeye devam eder).
  Future<void> hideThread(String chatId) async {
    final me = _uid;
    if (me == null) return;
    await db.ref('userChats/$me/$chatId').remove();
  }

  @override
  void dispose() {
    app.removeListener(_sync);
    _sub?.cancel();
    super.dispose();
  }
}
