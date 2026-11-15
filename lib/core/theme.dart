import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FColors {
  static const Color accent = Color(0xFFFF3D71);
  static const Color violet = Color(0xFF7B61FF);
  static const Color orange = Color(0xFFFF9F43);
  static const Color like = Color(0xFFFF2D55);
  static const Color verified = Color(0xFF1D9BF0);
  static const Color darkBg = Color(0xFF0A0C10);
  static const Color darkCard = Color(0xFF15181F);
  static const Color danger = Color(0xFFFF4757);

  static const LinearGradient brand = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [orange, accent, violet],
  );

  static const List<List<Color>> textPostGradients = [
    [Color(0xFF7B61FF), Color(0xFFFF3D71)],
    [Color(0xFF0BA360), Color(0xFF3CBA92)],
    [Color(0xFFFF9F43), Color(0xFFFF3D71)],
    [Color(0xFF1D2B64), Color(0xFF6A5CFF)],
    [Color(0xFF232526), Color(0xFF414345)],
    [Color(0xFF00C6FB), Color(0xFF005BEA)],
  ];
}

class AppTheme {
  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: FColors.accent, brightness: b).copyWith(
      primary: FColors.accent,
      surface: dark ? FColors.darkBg : Colors.white,
    );
    final fg = dark ? Colors.white : const Color(0xFF111318);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: b,
      scaffoldBackgroundColor: dark ? FColors.darkBg : Colors.white,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? FColors.darkBg : Colors.white,
        foregroundColor: fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: fg),
        systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? FColors.darkCard : const Color(0xFFF1F2F5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: FColors.accent, width: 1.3),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      dividerTheme: DividerThemeData(color: dark ? Colors.white12 : Colors.black12, thickness: 0.5, space: 0.5),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? FColors.danger : null,
  ));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = 'Tamam',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmText,
              style: TextStyle(
                  color: destructive ? FColors.danger : null, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return r == true;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? hint,
  String initial = '',
  bool obscure = false,
  String confirmText = 'Kaydet',
  int maxLines = 1,
}) async {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        obscureText: obscure,
        maxLines: obscure ? 1 : maxLines,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(confirmText)),
      ],
    ),
  );
}
