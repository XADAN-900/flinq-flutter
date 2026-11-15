import 'dart:async';

import 'package:flutter/services.dart';

/// Android arka plan servisi ("FlinQ · Bildirimler için bağlı") ile köprü.
class NativeBridge {
  NativeBridge._();

  static const MethodChannel _ch = MethodChannel('flinq/native');

  /// Yerel bildirime dokunulunca açılacak hedef (bildirim kimliği ya da 'dm:<uid>').
  static final StreamController<String> opens = StreamController<String>.broadcast();

  /// Yerel servis çalışıyorsa arka plan bildirimlerini o gösterir (çift bildirim olmasın).
  static bool active = false;

  static bool _init = false;

  static void init() {
    if (_init) return;
    _init = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is String) {
        opens.add(call.arguments as String);
      }
      return null;
    });
  }

  static Future<T?> _call<T>(String m, [Map<String, Object?>? a]) async {
    try {
      return await _ch.invokeMethod<T>(m, a);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setSession({
    required String uid,
    required bool enabled,
    required bool sound,
    required bool preview,
  }) async {
    final ok = await _call<bool>('setSession', {
      'uid': uid,
      'enabled': enabled,
      'sound': sound,
      'preview': preview,
    });
    active = ok == true;
  }

  static Future<void> clearSession() async {
    active = false;
    await _call('clearSession');
  }

  /// Uygulama bir yerel bildirimden açıldıysa hedefi (bir kez) döndürür.
  static Future<String?> takeLaunch() => _call<String>('takeLaunch');

  static Future<bool> isIgnoringBattery() async => (await _call<bool>('isIgnoringBattery')) ?? true;

  static Future<void> requestIgnoreBattery() => _call('requestIgnoreBattery');
}
