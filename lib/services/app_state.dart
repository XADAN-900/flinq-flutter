import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/firebase_config.dart';
import '../core/utils.dart';
import '../models/models.dart';
import 'native_bridge.dart';
import 'notification_service.dart';

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState(this.prefs) {
    db = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: FirebaseConfig.databaseUrl);
    auth = FirebaseAuth.instanceFor(app: Firebase.app());
    final ti = prefs.getInt('themeMode') ?? 0;
    _themeMode = (ti >= 0 && ti < ThemeMode.values.length) ? ThemeMode.values[ti] : ThemeMode.system;
    WidgetsBinding.instance.addObserver(this);
    _authSub = auth.authStateChanges().listen(_onAuth);
  }

  final SharedPreferences prefs;
  late final FirebaseDatabase db;
  late final FirebaseAuth auth;
  StreamSubscription<User?>? _authSub;

  bool ready = false;
  User? user;
  FUser? me;
  Set<String> following = {};
  List<NotificationItem> notifications = [];
  Map<String, List<Story>> stories = {};
  final Map<String, FUser> _users = {};
  bool foreground = true;
  bool connected = true;
  Timer? _offlineTimer;

  final _subs = <StreamSubscription>[];
  bool _notifInit = false;

  String? get uid => user?.uid;
  bool get loggedIn => user != null;
  String get username => me?.username ?? user?.displayName ?? (user?.email?.split('@').first ?? 'kullanıcı');

  /// Bildirime dokunulunca açılacak hedef (ana ekran dinler).
  final StreamController<NotificationItem> openRequests = StreamController<NotificationItem>.broadcast();

  // ------------------------------------------------------------------
  // Tema / tercihler
  // ------------------------------------------------------------------
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;
  void setThemeMode(ThemeMode m) {
    _themeMode = m;
    prefs.setInt('themeMode', m.index);
    notifyListeners();
  }

  bool get autoplay => prefs.getBool('autoplay') ?? true;
  bool get feedMuted => prefs.getBool('feedMuted') ?? true;
  bool get notifEnabled => prefs.getBool('notifEnabled') ?? true;
  bool get notifSound => prefs.getBool('soundNotifications') ?? true;
  bool get notifPreview => prefs.getBool('lockscreenPreview') ?? true;

  void setPref(String key, bool v) {
    prefs.setBool(key, v);
    notifyListeners();
    syncNative();
  }

  /// Arka plan servisine oturumu ve bildirim tercihlerini iletir (uygulama kapalıyken bildirim).
  void syncNative() {
    final u = uid;
    if (u == null) return;
    NativeBridge.setSession(uid: u, enabled: notifEnabled, sound: notifSound, preview: notifPreview);
  }

  // ------------------------------------------------------------------
  // Oturum
  // ------------------------------------------------------------------
  Future<void> _onAuth(User? u) async {
    final prev = user?.uid;
    user = u;
    if (u?.uid != prev) {
      await _stop();
      me = null;
      following = {};
      notifications = [];
      _notifInit = false;
      if (u != null) _start(u.uid);
    }
    ready = true;
    notifyListeners();
  }

  void _start(String uid) {
    _subs.add(db.ref('users/$uid').onValue.listen((e) {
      final m = asMap(e.snapshot.value);
      if (m.isNotEmpty) {
        me = FUser.fromMap(uid, m);
        _users[uid] = me!;
      }
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(db.ref('following/$uid').onValue.listen((e) {
      following = asMap(e.snapshot.value).keys.toSet();
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(db.ref('notifications/$uid').onValue.listen((e) {
      final list = asMap(e.snapshot.value)
          .entries
          .map((x) => NotificationItem.fromMap(x.key, asMap(x.value)))
          .toList()
        ..sort((a, b) => b.time.compareTo(a.time));
      final known = notifications.map((n) => n.id).toSet();
      if (_notifInit) {
        for (final n in list) {
          if (!known.contains(n.id) && !n.read) _alert(n);
        }
      }
      _notifInit = true;
      notifications = list;
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(db.ref('stories').onValue.listen((e) {
      final all = asMap(e.snapshot.value);
      final out = <String, List<Story>>{};
      all.forEach((owner, v) {
        final list = asMap(v)
            .entries
            .map((x) => Story.fromMap(x.key, owner, asMap(x.value)))
            .where((s) => !s.expired && s.url.isNotEmpty)
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        if (list.isNotEmpty) out[owner] = list;
        // Süresi dolan kendi hikayelerimi temizle
        if (owner == uid) {
          asMap(v).forEach((sid, sv) {
            final s = Story.fromMap(sid, owner, asMap(sv));
            if (s.expired) db.ref('stories/$owner/$sid').remove().catchError((_) {});
          });
        }
      });
      stories = out;
      notifyListeners();
    }, onError: (_) {}));
    _subs.add(db.ref('.info/connected').onValue.listen((e) {
      final c = e.snapshot.value == true;
      _offlineTimer?.cancel();
      if (c) {
        if (!connected) {
          connected = true;
          notifyListeners();
        }
      } else {
        // Kısa kopmalar (uygulamaya dönüş, ağ geçişi, video yüklerken) uyarı göstermesin:
        // sadece 8 saniyeden uzun süren kopmada "İnternet bağlantısı yok" çıkar.
        _offlineTimer = Timer(const Duration(seconds: 8), () {
          if (connected) {
            connected = false;
            notifyListeners();
          }
          db.goOnline();
        });
      }
    }));
    unawaited(NotificationService.registerToken(db, uid));
    syncNative();
  }

  Future<void> _stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }

  void _alert(NotificationItem n) {
    // Uygulama açıkken rozet yeterli; arka plandayken telefona bildirim düşer
    // (yerel servis çalışıyorsa bildirimi o gösterir).
    if (!notifEnabled || foreground || NativeBridge.active) return;
    NotificationService.show(
      id: n.id,
      title: 'FlinQ',
      body: stripHtml(n.message),
      payload: n.id,
      silent: !notifSound,
      showContent: notifPreview,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
  }

  Future<String?> login(String emailOrUsername, String password) async {
    var email = emailOrUsername.trim();
    if (email.isEmpty || password.isEmpty) return 'E-posta/kullanıcı adı ve şifre gir.';
    try {
      if (!email.contains('@')) {
        final s = await db.ref('usernames/${email.toLowerCase()}').get();
        final u = asStr(asMap(s.value)['uid']);
        if (u.isEmpty) return 'Bu kullanıcı adı bulunamadı.';
        final e = await db.ref('users/$u/email').get();
        email = asStr(e.value);
        if (email.isEmpty) return 'Bu hesap için e-posta bulunamadı. E-postanla giriş yap.';
      }
      await auth.signInWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return _authError(e);
    } catch (e) {
      return 'Giriş yapılamadı: $e';
    }
  }

  Future<bool> isUsernameTaken(String username) async {
    final s = await db.ref('usernames/${username.trim().toLowerCase()}').get();
    if (!s.exists) return false;
    return asStr(asMap(s.value)['uid']) != uid;
  }

  Future<String?> register(String username, String email, String password,
      {String? photoDataUrl, String bio = ''}) async {
    username = username.trim();
    email = email.trim();
    final uErr = usernameError(username);
    if (uErr != null) return uErr;
    if (!email.contains('@')) return 'Geçerli bir e-posta gir.';
    if (password.length < 6) return 'Şifre en az 6 karakter olmalı.';
    try {
      final s = await db.ref('usernames/${username.toLowerCase()}').get();
      if (s.exists) return 'Bu kullanıcı adı zaten kullanılıyor.';
      final cred = await auth.createUserWithEmailAndPassword(email: email, password: password);
      final u = cred.user!;
      await u.updateDisplayName(username);
      await db.ref('users/${u.uid}').set({
        'email': u.email ?? email,
        'username': username,
        'initials': username.substring(0, 1).toUpperCase(),
        'profilePhotoUrl': photoDataUrl ?? '',
        'lastUsernameChange': 0,
        if (bio.trim().isNotEmpty) 'bio': bio.trim(),
      });
      await db.ref('usernames/${username.toLowerCase()}').set({'uid': u.uid, 'username': username});
      return null;
    } on FirebaseAuthException catch (e) {
      return _authError(e);
    } catch (e) {
      return 'Kayıt başarısız: $e';
    }
  }

  Future<String?> resetPassword(String email) async {
    try {
      await auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return _authError(e);
    }
  }

  String _authError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'E-posta adresi geçersiz.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'E-posta veya şifre hatalı.';
      case 'email-already-in-use':
        return 'Bu e-posta zaten kayıtlı.';
      case 'weak-password':
        return 'Şifre çok zayıf.';
      case 'too-many-requests':
        return 'Çok fazla deneme. Biraz sonra tekrar dene.';
      case 'network-request-failed':
        return 'İnternet bağlantısı yok.';
      default:
        return e.message ?? 'Bir hata oluştu (${e.code}).';
    }
  }

  Future<void> logout() async {
    final u = uid;
    await NativeBridge.clearSession();
    if (u != null) await NotificationService.unregisterToken(db, u);
    await NotificationService.cancelAll();
    await auth.signOut();
  }

  // ------------------------------------------------------------------
  // Kullanıcılar
  // ------------------------------------------------------------------
  FUser? cachedUser(String uid) => _users[uid];

  /// Sadece kullanıcı adı bilinen (fotoğrafı henüz yüklenmemiş) kayıtlar.
  final Set<String> _stubs = {};

  Future<FUser?> userById(String uid, {bool refresh = false}) async {
    if (!refresh && _users.containsKey(uid) && !_stubs.contains(uid)) return _users[uid];
    try {
      final s = await db.ref('users/$uid').get();
      if (!s.exists) return _users[uid];
      final u = FUser.fromMap(uid, asMap(s.value));
      _users[uid] = u;
      _stubs.remove(uid);
      return u;
    } catch (_) {
      return _users[uid];
    }
  }

  final Set<String> _warmTried = {};

  Future<void> warmUsers(Iterable<String> uids) async {
    // Bulunamayan kullanıcıyı tekrar tekrar istemeyelim (sonsuz yenileme döngüsü olmasın).
    final missing = uids
        .where((u) => u.isNotEmpty && (!_users.containsKey(u) || _stubs.contains(u)) && !_warmTried.contains(u))
        .toSet();
    if (missing.isEmpty) return;
    _warmTried.addAll(missing);
    await Future.wait(missing.map((u) => userById(u)));
    notifyListeners();
  }

  bool _allLoaded = false;
  Future<List<FUser>> allUsers({bool refresh = false}) async {
    if (!_allLoaded || refresh) {
      // Tüm "users" düğümü (profil fotoğraflarıyla) çok büyük olabilir; arama için sadece
      // küçük "usernames" indeksini okuyoruz. Fotoğraflar ekranda görününce tek tek yüklenir.
      try {
        final s = await db.ref('usernames').get();
        asMap(s.value).forEach((k, v) {
          final m = asMap(v);
          final id = asStr(m['uid']);
          if (id.isEmpty) return;
          if (!_users.containsKey(id)) {
            _users[id] = FUser(uid: id, username: asStr(m['username'], k));
            _stubs.add(id);
          }
        });
        _allLoaded = true;
      } catch (_) {}
    }
    return _users.values.toList();
  }

  // ------------------------------------------------------------------
  // Gönderiler
  // ------------------------------------------------------------------
  // ------------------------------------------------------------------
  // Gönderi yükleme — BELLEK DOSTU
  // Gönderi anahtarları Date.now() ile üretildiği için anahtar sırası = zaman sırası.
  // Böylece indeks gerekmeden "en yeni N gönderi" orderByKey().limitToLast(N) ile alınır.
  // Tüm "posts" düğümünü (base64 videolarıyla birlikte) asla tek seferde indirmeyiz:
  // bu, telefonda belleği taşırıp uygulamayı çökertiyordu.
  // ------------------------------------------------------------------
  List<String>? _keyCache;
  DateTime? _keyCacheAt;

  void invalidatePosts() => _keyCacheAt = null;

  /// Tüm gönderi anahtarları (eskiden yeniye), sadece anahtarlar — içerik yok.
  Future<List<String>> _postKeys() async {
    final fresh = _keyCacheAt != null && DateTime.now().difference(_keyCacheAt!) < const Duration(seconds: 30);
    if (fresh && _keyCache != null) return _keyCache!;
    try {
      final token = await user?.getIdToken();
      final uri = Uri.parse(
          '${FirebaseConfig.databaseUrl}/posts.json?shallow=true${token != null ? '&auth=$token' : ''}');
      final res = await http.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body);
        final keys = j is Map ? j.keys.map((e) => e.toString()).toList() : <String>[];
        keys.sort();
        _keyCache = keys;
        _keyCacheAt = DateTime.now();
        return keys;
      }
    } catch (_) {}
    return _keyCache ?? const [];
  }

  static const List<String> _metaFields = [
    'uid', 'username', 'caption', 'type', 'likes', 'likedBy', 'comments', 'timestamp', 'edited',
  ];

  /// Gönderinin medya (url) DIŞINDAKİ alanlarını okur. Base64 fotoğraf/video ancak
  /// ekranda gösterileceği zaman [postImage] / [postVideoPath] ile tek tek indirilir.
  Future<Post?> _fetchPostMeta(String id) async {
    try {
      final snaps = await Future.wait(_metaFields.map((f) => db.ref('posts/$id/$f').get()));
      final m = <String, dynamic>{};
      for (var i = 0; i < _metaFields.length; i++) {
        if (snaps[i].exists) m[_metaFields[i]] = snaps[i].value;
      }
      if (m['uid'] == null) return null;
      final p = Post.fromMap(id, m);
      return p.isValid ? p : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Post>> _fetchPosts(Iterable<String> ids) async {
    final out = <Post>[];
    final list = ids.toList();
    for (var i = 0; i < list.length; i += 6) {
      final batch = list.sublist(i, i + 6 > list.length ? list.length : i + 6);
      final got = await Future.wait(batch.map(_fetchPostMeta));
      out.addAll(got.whereType<Post>());
    }
    out.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return out;
  }

  // ---- Medya: görünürken tek tek indir ----
  final Map<String, Future<Uint8List?>> _imgFutures = {};
  final List<String> _imgOrder = [];
  final Map<String, Future<String?>> _vidFutures = {};

  /// Gönderi fotoğrafının baytları (en fazla 40 tanesi bellekte tutulur).
  Future<Uint8List?> postImage(String id) {
    final hit = _imgFutures[id];
    if (hit != null) return hit;
    final f = () async {
      try {
        final s = await db.ref('posts/$id/url').get();
        return decodeDataUrl(asStrOrNull(s.value));
      } catch (_) {
        return null;
      }
    }();
    _imgFutures[id] = f;
    _imgOrder.add(id);
    while (_imgOrder.length > 40) {
      _imgFutures.remove(_imgOrder.removeAt(0));
    }
    return f;
  }

  /// Gönderi videosunu geçici dosyaya indirir ve yolunu döndürür (diskte önbellekli).
  Future<String?> postVideoPath(String id) {
    final hit = _vidFutures[id];
    if (hit != null) return hit;
    final f = () async {
      try {
        final dir = await getTemporaryDirectory();
        for (final ext in const ['mp4', 'webm', 'mov', '3gp', 'mkv']) {
          final c = File('${dir.path}/fqv_$id.$ext');
          if (c.existsSync() && c.lengthSync() > 0) return c.path;
        }
        final s = await db.ref('posts/$id/url').get();
        final data = asStrOrNull(s.value);
        if (data == null) return null;
        final path = '${dir.path}/fqv_$id.${extFromMime(mimeOfDataUrl(data, 'video/mp4'))}';
        final ok = await compute(writeDataUrlToFile, [data, path]);
        return ok ? path : null;
      } catch (_) {
        return null;
      }
    }();
    _vidFutures[id] = f;
    f.then((v) {
      if (v == null) _vidFutures.remove(id);
    });
    return f;
  }

  /// Gönderilerin tek bir küçük alanını (uid, type, caption) toplu okur.
  Future<Map<String, String>> _postField(List<String> ids, String field) async {
    final out = <String, String>{};
    for (var i = 0; i < ids.length; i += 20) {
      final batch = ids.sublist(i, i + 20 > ids.length ? ids.length : i + 20);
      final got = await Future.wait(batch.map((id) async {
        try {
          final s = await db.ref('posts/$id/$field').get();
          return MapEntry(id, asStr(s.value));
        } catch (_) {
          return MapEntry(id, '');
        }
      }));
      out.addEntries(got);
    }
    return out;
  }

  /// En yeni [limit] gönderi.
  Future<List<Post>> loadFeed({int limit = 30, bool force = false}) async {
    final keys = await _postKeys();
    final list = await _fetchPosts(keys.reversed.take(limit));
    unawaited(warmUsers(list.map((p) => p.uid)));
    return list;
  }

  /// Bir kullanıcının gönderileri (önce sadece "uid" alanları okunur).
  Future<List<Post>> loadUserPosts(String owner, {bool force = true}) async {
    final keys = await _postKeys();
    if (keys.isEmpty) return const [];
    final uids = await _postField(keys, 'uid');
    final mine = keys.where((k) => uids[k] == owner).toList().reversed.take(120);
    return _fetchPosts(mine);
  }

  /// En yeni video gönderileri (Reels).
  Future<List<Post>> loadVideos({int scan = 300, int limit = 30}) async {
    final keys = await _postKeys();
    final recent = keys.reversed.take(scan).toList();
    final types = await _postField(recent, 'type');
    final ids = recent.where((k) => types[k] == 'video').take(limit);
    return _fetchPosts(ids);
  }

  /// #etiket içeren gönderiler (önce sadece açıklamalar okunur).
  Future<List<Post>> loadHashtag(String tag, {int scan = 500, int limit = 90}) async {
    final keys = await _postKeys();
    final recent = keys.reversed.take(scan).toList();
    final caps = await _postField(recent, 'caption');
    final re = RegExp('#${RegExp.escape(tag)}(?![\\wığüşöçİĞÜŞÖÇ])', caseSensitive: false);
    final ids = recent.where((k) => re.hasMatch(caps[k] ?? '')).take(limit);
    return _fetchPosts(ids);
  }

  /// Keşfet için etiket arama: son gönderilerin açıklamaları.
  Future<Map<String, String>> recentCaptions({int scan = 400}) async {
    final keys = await _postKeys();
    return _postField(keys.reversed.take(scan).toList(), 'caption');
  }

  Future<Post?> loadPost(String id) => _fetchPostMeta(id);

  /// Yorumları canlı izler (gönderinin medyası indirilmez).
  Stream<Post?> watchPost(String id) async* {
    final meta = await _fetchPostMeta(id);
    if (meta == null) {
      yield null;
      return;
    }
    await for (final e in db.ref('posts/$id/comments').onValue) {
      final comments = asMap(e.snapshot.value)
          .entries
          .map((x) => Comment.fromMap(x.key, asMap(x.value)))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      yield Post(
        id: meta.id,
        uid: meta.uid,
        username: meta.username,
        url: meta.url,
        caption: meta.caption,
        type: meta.type,
        likes: meta.likes,
        likedBy: meta.likedBy,
        comments: comments,
        timestamp: meta.timestamp,
        edited: meta.edited,
      );
    }
  }

  Future<void> createPost({required String url, required String caption, required String type}) async {
    final u = uid;
    if (u == null) return;
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await db.ref('posts/$id').set({
      'uid': u,
      'username': username,
      'url': url,
      'caption': caption,
      'type': type,
      'likes': 0,
      'timestamp': ServerValue.timestamp,
    });
    invalidatePosts();
    await notifyMentions(caption, postId: id);
  }

  Future<void> editPost(String id, String caption) =>
      db.ref('posts/$id').update({'caption': caption, 'edited': true});

  Future<void> deletePost(String id) async {
    await db.ref('posts/$id').remove();
    invalidatePosts();
  }

  /// Beğeniyi tersine çevirir, yeni durumu döndürür.
  Future<bool> toggleLike(Post p) async {
    final u = uid;
    if (u == null) return false;
    final ref = db.ref('posts/${p.id}');
    final liked = p.likedBy.contains(u);
    if (liked) {
      await ref.child('likedBy/$u').remove();
      await ref.child('likes').runTransaction((v) {
        final n = asInt(v);
        return Transaction.success(n > 0 ? n - 1 : 0);
      });
      return false;
    }
    await ref.child('likedBy/$u').set(true);
    await ref.child('likes').runTransaction((v) => Transaction.success(asInt(v) + 1));
    if (p.uid != u) {
      await addNotification(p.uid, {
        'type': 'like',
        'message': '<strong>${escapeHtml(username)}</strong> gönderini beğendi',
        'from': u,
        'postId': p.id,
      });
    }
    return true;
  }

  Future<void> toggleSave(String postId) async {
    final u = uid;
    if (u == null) return;
    final saved = me?.saved.contains(postId) ?? false;
    final r = db.ref('users/$u/saved/$postId');
    saved ? await r.remove() : await r.set(ServerValue.timestamp);
  }

  Future<void> addComment(Post p, String text, {Comment? replyTo}) async {
    final u = uid;
    if (u == null) return;
    final rnd = Random().nextInt(1 << 30).toRadixString(36);
    final now = DateTime.now().millisecondsSinceEpoch;
    final short = text.length > 30 ? '${text.substring(0, 30)}...' : text;
    if (replyTo != null) {
      final rid = 'reply_${now}_$rnd';
      await db.ref('posts/${p.id}/comments/${replyTo.id}/replies/$rid').set({
        'uid': u,
        'username': username,
        'text': text,
        'timestamp': ServerValue.timestamp,
      });
      if (replyTo.uid != u) {
        await addNotification(replyTo.uid, {
          'type': 'reply',
          'message': '<strong>${escapeHtml(username)}</strong> yorumuna yanıt verdi: "${escapeHtml(short)}"',
          'from': u,
          'postId': p.id,
          'commentId': replyTo.id,
          'replyId': rid,
        });
      }
      await notifyMentions(text, postId: p.id, commentId: replyTo.id);
      return;
    }
    final cid = 'comment_${now}_$rnd';
    await db.ref('posts/${p.id}/comments/$cid').set({
      'uid': u,
      'username': username,
      'text': text,
      'timestamp': ServerValue.timestamp,
    });
    if (p.uid != u) {
      await addNotification(p.uid, {
        'type': 'comment',
        'message': '<strong>${escapeHtml(username)}</strong> gönderine yorum yaptı: "${escapeHtml(short)}"',
        'from': u,
        'postId': p.id,
        'commentId': cid,
      });
    }
    await notifyMentions(text, postId: p.id, commentId: cid);
  }

  Future<void> deleteComment(String postId, String commentId, {String? replyId}) {
    final path = replyId == null
        ? 'posts/$postId/comments/$commentId'
        : 'posts/$postId/comments/$commentId/replies/$replyId';
    return db.ref(path).remove();
  }

  Future<void> toggleCommentLike(String postId, Comment c) async {
    final u = uid;
    if (u == null) return;
    final r = db.ref('posts/$postId/comments/${c.id}/likedBy/$u');
    c.likedBy.contains(u) ? await r.remove() : await r.set(true);
  }

  // ------------------------------------------------------------------
  // Takip
  // ------------------------------------------------------------------
  Future<void> toggleFollow(String target) async {
    final u = uid;
    if (u == null || target == u) return;
    if (following.contains(target)) {
      following.remove(target);
      notifyListeners();
      await db.ref('following/$u/$target').remove();
      await db.ref('followers/$target/$u').remove();
      return;
    }
    following.add(target);
    notifyListeners();
    await db.ref('following/$u/$target').set(true);
    await db.ref('followers/$target/$u').set(true);
    await addNotification(target, {
      'type': 'follow',
      'message': '<strong>${escapeHtml(username)}</strong> seni takip etmeye başladı',
      'from': u,
    });
    await _milestones(target);
  }

  Future<void> _milestones(String target) async {
    try {
      final f = await db.ref('followers/$target').get();
      final n = asMap(f.value).length;
      final us = await db.ref('users/$target').get();
      final m = asMap(us.value);
      if (n >= 100 && !asBool(m['notified100Followers'])) {
        await db.ref('users/$target').update({'notified100Followers': true});
        await addNotification(target, {
          'type': 'milestone',
          'message': 'Tebrikler! <strong>100 takipçiye</strong> ulaştın 🎉',
          'from': target,
        }, allowSelf: true);
      }
      if (n >= 1000 && !asBool(m['verified'])) {
        await db.ref('users/$target').update({'verified': true});
        await addNotification(target, {
          'type': 'milestone',
          'message':
              'Tebrikler! <strong>1000 takipçiye</strong> ulaştın ve hesabın <strong>mavi tik</strong> ile doğrulandı! ✅',
          'from': target,
        }, allowSelf: true);
      }
    } catch (_) {}
  }

  Future<Set<String>> followersOf(String u) async =>
      asMap((await db.ref('followers/$u').get()).value).keys.toSet();

  Future<Set<String>> followingOf(String u) async =>
      asMap((await db.ref('following/$u').get()).value).keys.toSet();

  // ------------------------------------------------------------------
  // Bildirimler
  // ------------------------------------------------------------------
  int get unreadCount => notifications.where((n) => !n.read).length;

  Future<void> addNotification(String target, Map<String, Object?> data, {bool allowSelf = false}) async {
    if (target.isEmpty) return;
    if (target == uid && !allowSelf) return;
    final id = 'notif_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 30).toRadixString(36)}';
    try {
      await db.ref('notifications/$target/$id').set({
        ...data,
        'id': id,
        'time': DateTime.now().millisecondsSinceEpoch,
        'read': false,
      });
    } catch (_) {}
  }

  Future<void> notifyMentions(String text, {String postId = '', String commentId = ''}) async {
    final u = uid;
    if (u == null || text.isEmpty) return;
    final names = RegExp(r'(?:^|\s)@([\wığüşöçİĞÜŞÖÇ]+)')
        .allMatches(text)
        .map((m) => m.group(1)!.toLowerCase())
        .toSet();
    for (final n in names) {
      try {
        final s = await db.ref('usernames/$n').get();
        final target = asStr(asMap(s.value)['uid']);
        if (target.isEmpty || target == u) continue;
        await addNotification(target, {
          'type': 'mention',
          'message': commentId.isEmpty
              ? '<strong>${escapeHtml(username)}</strong> seni bir gönderide etiketledi'
              : '<strong>${escapeHtml(username)}</strong> seni bir yorumda etiketledi',
          'from': u,
          'postId': postId,
          'commentId': commentId,
        });
      } catch (_) {}
    }
  }

  Future<void> markNotificationRead(String id) async {
    final u = uid;
    if (u == null) return;
    await db.ref('notifications/$u/$id/read').set(true);
  }

  Future<void> markAllRead() async {
    final u = uid;
    if (u == null) return;
    final up = <String, Object?>{};
    for (final n in notifications.where((n) => !n.read)) {
      up['${n.id}/read'] = true;
    }
    if (up.isNotEmpty) await db.ref('notifications/$u').update(up);
  }

  Future<void> deleteNotification(String id) async {
    final u = uid;
    if (u == null) return;
    await db.ref('notifications/$u/$id').remove();
  }

  Future<void> clearNotifications() async {
    final u = uid;
    if (u == null) return;
    await db.ref('notifications/$u').remove();
  }

  // ------------------------------------------------------------------
  // Profil
  // ------------------------------------------------------------------
  static const int usernameCooldownMs = 15 * 24 * 60 * 60 * 1000;

  int get usernameCooldownLeftDays {
    final last = me?.lastUsernameChange ?? 0;
    if (last == 0) return 0;
    final left = usernameCooldownMs - (DateTime.now().millisecondsSinceEpoch - last);
    return left <= 0 ? 0 : (left / (24 * 60 * 60 * 1000)).ceil();
  }

  Future<String?> changeUsername(String next) async {
    final u = uid;
    if (u == null) return 'Oturum yok.';
    next = next.trim();
    final err = usernameError(next);
    if (err != null) return err;
    if (usernameCooldownLeftDays > 0) {
      return 'Kullanıcı adını tekrar değiştirmek için $usernameCooldownLeftDays gün beklemelisin.';
    }
    final old = username;
    if (next.toLowerCase() != old.toLowerCase()) {
      final s = await db.ref('usernames/${next.toLowerCase()}').get();
      if (s.exists) return 'Bu kullanıcı adı zaten kullanılıyor.';
    }
    final up = <String, Object?>{
      'users/$u/username': next,
      'users/$u/initials': next.substring(0, 1).toUpperCase(),
      'users/$u/lastUsernameChange': ServerValue.timestamp,
      'usernames/${next.toLowerCase()}': {'uid': u, 'username': next},
    };
    if (old.toLowerCase() != next.toLowerCase()) up['usernames/${old.toLowerCase()}'] = null;
    await db.ref().update(up);
    await user?.updateDisplayName(next);
    return null;
  }

  Future<void> updateProfile({String? bio, String? photo, bool removePhoto = false}) async {
    final u = uid;
    if (u == null) return;
    final up = <String, Object?>{};
    if (bio != null) up['bio'] = bio;
    if (photo != null) up['profilePhotoUrl'] = photo;
    if (removePhoto) up['profilePhotoUrl'] = '';
    if (up.isNotEmpty) await db.ref('users/$u').update(up);
  }

  // ------------------------------------------------------------------
  // Hikayeler
  // ------------------------------------------------------------------
  Future<String?> addStory(String url, {String caption = ''}) async {
    final u = uid;
    if (u == null) return 'Oturum yok.';
    try {
      await db.ref('stories/$u').push().set({
        'url': url,
        'caption': caption,
        'timestamp': ServerValue.timestamp,
      });
      return null;
    } catch (e) {
      return 'Hikaye paylaşılamadı. Veritabanı kurallarında "stories" yoluna yazma izni olmalı.';
    }
  }

  Future<void> markStorySeen(Story s) async {
    final u = uid;
    if (u == null || s.uid == u || s.viewers.contains(u)) return;
    await db.ref('stories/${s.uid}/${s.id}/viewers/$u').set(true).catchError((_) {});
  }

  Future<void> deleteStory(Story s) => db.ref('stories/${s.uid}/${s.id}').remove();

  bool hasUnseenStory(String owner) {
    final list = stories[owner];
    if (list == null) return false;
    return list.any((s) => !s.viewers.contains(uid) && s.uid != uid);
  }

  /// Hikaye çubuğunun sırası: önce ben, sonra izlenmemişler, sonra diğerleri.
  List<String> storyOwners() {
    final owners = stories.keys.toList();
    owners.sort((a, b) {
      if (a == uid) return -1;
      if (b == uid) return 1;
      final ua = hasUnseenStory(a), ub = hasUnseenStory(b);
      if (ua != ub) return ua ? -1 : 1;
      final fa = following.contains(a), fb = following.contains(b);
      if (fa != fb) return fa ? -1 : 1;
      return stories[b]!.last.timestamp.compareTo(stories[a]!.last.timestamp);
    });
    return owners;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _stop();
    openRequests.close();
    super.dispose();
  }
}
