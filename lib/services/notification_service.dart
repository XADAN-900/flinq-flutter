import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/firebase_config.dart';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: FirebaseConfig.options);
    }
  } catch (_) {}
  await NotificationService.init();
  final d = message.data;
  if ('${d['type'] ?? ''}' != 'notif') return;
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool('notifEnabled') ?? true)) return;
  await NotificationService.show(
    id: '${d['notifId'] ?? DateTime.now().millisecondsSinceEpoch}',
    title: 'FlinQ',
    body: '${d['message'] ?? 'Yeni bildirim'}',
    payload: '${d['notifId'] ?? ''}',
    silent: !(prefs.getBool('soundNotifications') ?? true),
    showContent: prefs.getBool('lockscreenPreview') ?? true,
  );
}

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static void Function(String payload)? onTap;

  static const _ch = 'fq_activity';
  static const _chSilent = 'fq_activity_silent';

  static Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('ic_notification')),
      onDidReceiveNotificationResponse: (r) {
        final p = r.payload;
        if (p != null && p.isNotEmpty && onTap != null) onTap!(p);
      },
    );
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(const AndroidNotificationChannel(
        _ch,
        'Etkinlik',
        description: 'Beğeni, yorum, takip ve etiket bildirimleri',
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound('flinq_notify'),
        playSound: true,
      ));
      await android.createNotificationChannel(const AndroidNotificationChannel(
        _chSilent,
        'Etkinlik (sessiz)',
        importance: Importance.defaultImportance,
        playSound: false,
        enableVibration: false,
      ));
    }
    _ready = true;
  }

  static Future<void> requestPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  static Future<String?> launchPayload() async {
    try {
      final d = await _plugin.getNotificationAppLaunchDetails();
      if (d != null && d.didNotificationLaunchApp) return d.notificationResponse?.payload;
    } catch (_) {}
    return null;
  }

  static int _idFor(String key) {
    var h = 0x811c9dc5;
    for (final c in key.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h;
  }

  static Future<void> show({
    required String id,
    required String title,
    required String body,
    String? payload,
    bool silent = false,
    bool showContent = true,
  }) async {
    await init();
    final text = showContent ? body : 'Yeni bir bildirimin var';
    await _plugin.show(
      _idFor(id),
      title,
      text,
      NotificationDetails(
        android: AndroidNotificationDetails(
          silent ? _chSilent : _ch,
          silent ? 'Etkinlik (sessiz)' : 'Etkinlik',
          importance: silent ? Importance.defaultImportance : Importance.high,
          priority: silent ? Priority.defaultPriority : Priority.high,
          styleInformation: BigTextStyleInformation(text),
          color: const Color(0xFFFF3D71),
          groupKey: 'flinq.activity',
          visibility: showContent ? NotificationVisibility.public : NotificationVisibility.private,
        ),
      ),
      payload: payload,
    );
  }

  static Future<void> cancelAll() => _plugin.cancelAll();

  static StreamSubscription<String>? _tokenSub;
  static String? _token;

  static Future<void> registerToken(FirebaseDatabase db, String uid) async {
    await init();
    await requestPermission();
    if (!FirebaseConfig.hasAndroidAppId) return;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      final t = await fm.getToken();
      if (t != null) {
        _token = t;
        await db.ref('fcmTokens/$uid/$t').set(ServerValue.timestamp);
      }
      await _tokenSub?.cancel();
      _tokenSub = fm.onTokenRefresh.listen((n) {
        _token = n;
        db.ref('fcmTokens/$uid/$n').set(ServerValue.timestamp);
      });
    } catch (e) {
      debugPrint('FCM kullanılamıyor: $e');
    }
  }

  static Future<void> unregisterToken(FirebaseDatabase db, String uid) async {
    await _tokenSub?.cancel();
    _tokenSub = null;
    final t = _token;
    if (t != null) {
      try {
        await db.ref('fcmTokens/$uid/$t').remove();
      } catch (_) {}
    }
  }
}
