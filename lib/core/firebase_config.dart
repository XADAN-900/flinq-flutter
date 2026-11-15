import 'package:firebase_core/firebase_core.dart';

/// FlinQ Firebase projesi (flinq-8e74c).
///
/// FCM push için Android uygulama kimliği derlemede
/// `--dart-define=FIREBASE_ANDROID_APP_ID=1:40261522799:android:xxxx` ile verilebilir.
/// Verilmezse web kimliği kullanılır: giriş ve veritabanı yine çalışır.
class FirebaseConfig {
  static const String databaseUrl =
      'https://flinq-8e74c-default-rtdb.europe-west1.firebasedatabase.app';

  static const String _androidAppId =
      String.fromEnvironment('FIREBASE_ANDROID_APP_ID', defaultValue: '');

  static const String _webAppId = '1:40261522799:web:79a7a32902ee7231e7049a';

  static bool get hasAndroidAppId => _androidAppId.isNotEmpty;

  static FirebaseOptions get options => FirebaseOptions(
        apiKey: 'AIzaSyDdSWxFYZ8YsHFAk-NMpvVPNTdf-QyWvx4',
        appId: hasAndroidAppId ? _androidAppId : _webAppId,
        messagingSenderId: '40261522799',
        projectId: 'flinq-8e74c',
        authDomain: 'flinq-8e74c.firebaseapp.com',
        databaseURL: databaseUrl,
        storageBucket: 'flinq-8e74c.appspot.com',
      );
}
