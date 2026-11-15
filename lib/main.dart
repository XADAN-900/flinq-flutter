import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/firebase_config.dart';
import 'core/nav.dart';
import 'core/theme.dart';
import 'models/models.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/app_state.dart';
import 'services/dm_service.dart';
import 'services/notification_service.dart';
import 'widgets/feed_video.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR');
  await Firebase.initializeApp(options: FirebaseConfig.options);
  try {
    final db = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: FirebaseConfig.databaseUrl);
    db.setPersistenceEnabled(true);
    db.setPersistenceCacheSizeBytes(40 * 1024 * 1024);
  } catch (_) {}
  if (FirebaseConfig.hasAndroidAppId) {
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  }
  await NotificationService.init();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final prefs = await SharedPreferences.getInstance();
  final app = AppState(prefs);
  final dm = DmService(app);
  NotificationService.onTap = (payload) => _openFromNotification(app, payload);
  runApp(FlinQApp(app: app, dm: dm));
  WidgetsBinding.instance.addPostFrameCallback((_) => _showLastCrash());
  final launch = await NotificationService.launchPayload();
  if (launch != null && launch.isNotEmpty) {
    Future.delayed(const Duration(milliseconds: 1500), () => _openFromNotification(app, launch));
  }
}

Future<void> _openFromNotification(AppState app, String notifId) async {
  final uid = app.uid;
  if (uid == null) return;
  if (notifId.startsWith('dm:')) {
    app.openRequests.add(NotificationItem(id: notifId, type: 'dm', message: '', from: notifId.substring(3), read: true));
    return;
  }
  for (final n in app.notifications) {
    if (n.id == notifId) {
      app.openRequests.add(n);
      return;
    }
  }
  // Bildirim listesi henüz yüklenmediyse doğrudan veritabanından al.
  try {
    final s = await app.db.ref('notifications/$uid/$notifId').get();
    if (!s.exists) return;
    final m = s.value;
    if (m is Map) {
      final map = m.map((k, v) => MapEntry(k.toString(), v));
      app.openRequests.add(NotificationItem.fromMap(notifId, map));
    }
  } catch (_) {}
}

/// Uygulama bir önceki açılışta çöktüyse raporu gösterir (kopyalanıp geliştiriciye iletilebilir).
Future<void> _showLastCrash() async {
  const ch = MethodChannel('flinq/crash');
  String? report;
  try {
    report = await ch.invokeMethod<String>('get');
  } catch (_) {}
  if (report == null || report.trim().isEmpty) return;
  await Future.delayed(const Duration(milliseconds: 1200));
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return;
  final text = report.length > 6000 ? report.substring(0, 6000) : report;
  await showDialog(
    context: ctx,
    builder: (c) => AlertDialog(
      title: const Text('Uygulama kapanmıştı 😕'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Son açılışta bir hata oluştu. Raporu kopyalayıp geliştiriciye gönderirsen hemen düzeltilir.'),
            const SizedBox(height: 10),
            Container(
              height: 180,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8)),
              child: SingleChildScrollView(
                child: SelectableText(text, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat')),
        FilledButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            Navigator.pop(c);
          },
          child: const Text('Raporu kopyala'),
        ),
      ],
    ),
  );
  try {
    await ch.invokeMethod('clear');
  } catch (_) {}
}

class FlinQApp extends StatelessWidget {
  final AppState app;
  final DmService dm;
  const FlinQApp({super.key, required this.app, required this.dm});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<DmService>.value(value: dm),
      ],
      child: Consumer<AppState>(
        builder: (context, app, _) => MaterialApp(
          title: 'FlinQ',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          navigatorObservers: [VideoPauseObserver()],
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: app.themeMode,
          locale: const Locale('tr', 'TR'),
          supportedLocales: const [Locale('tr', 'TR'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const _Gate(),
        ),
      ),
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.ready) {
      return Scaffold(
        body: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Image.asset('assets/logo.png', width: 110, height: 110),
          ),
        ),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: app.loggedIn ? HomeScreen(key: ValueKey(app.uid)) : const AuthScreen(key: ValueKey('auth')),
    );
  }
}
