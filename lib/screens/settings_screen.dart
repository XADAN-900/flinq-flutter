import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/app_state.dart';
import 'edit_profile_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    Widget head(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
          child: Text(t, style: TextStyle(color: theme.hintColor, fontWeight: FontWeight.w700, fontSize: 13)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        children: [
          head('Hesap'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Profili düzenle'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Şifre sıfırlama bağlantısı gönder'),
            subtitle: Text(app.user?.email ?? ''),
            onTap: () async {
              final email = app.user?.email;
              if (email == null) return;
              final err = await app.resetPassword(email);
              if (context.mounted) {
                showSnack(context, err ?? 'Bağlantı $email adresine gönderildi.', error: err != null);
              }
            },
          ),
          head('Görünüm'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Sistem'), icon: Icon(Icons.brightness_auto)),
                ButtonSegment(value: ThemeMode.light, label: Text('Açık'), icon: Icon(Icons.light_mode)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Koyu'), icon: Icon(Icons.dark_mode)),
              ],
              selected: {app.themeMode},
              onSelectionChanged: (s) => app.setThemeMode(s.first),
            ),
          ),
          head('Videolar'),
          SwitchListTile(
            secondary: const Icon(Icons.play_circle_outline),
            title: const Text('Videoları otomatik oynat'),
            value: app.autoplay,
            onChanged: (v) => app.setPref('autoplay', v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_off_outlined),
            title: const Text('Akışta videolar sessiz başlasın'),
            value: app.feedMuted,
            onChanged: (v) => app.setPref('feedMuted', v),
          ),
          head('Bildirimler'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Telefon bildirimleri'),
            subtitle: const Text('Beğeni, yorum, takip, yanıt ve etiketler'),
            value: app.notifEnabled,
            onChanged: (v) => app.setPref('notifEnabled', v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: const Text('Bildirim sesi'),
            value: app.notifSound,
            onChanged: (v) => app.setPref('soundNotifications', v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: const Text('Kilit ekranında içerik'),
            value: app.notifPreview,
            onChanged: (v) => app.setPref('lockscreenPreview', v),
          ),
          head('Hakkında'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('FlinQ'),
            subtitle: Text('Sürüm 2.0.0 · Flutter'),
          ),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: FColors.danger),
            title: const Text('Çıkış yap', style: TextStyle(color: FColors.danger, fontWeight: FontWeight.w600)),
            onTap: () async {
              final ok = await confirmDialog(context,
                  title: 'Çıkış yap', message: '@${app.username} hesabından çıkılsın mı?', confirmText: 'Çıkış yap', destructive: true);
              if (!ok) return;
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              await app.logout();
            },
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
