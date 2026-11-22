import 'package:flutter/material.dart';
import '../core/strings.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/app_state.dart';
import '../services/app_guard.dart';
import '../services/native_bridge.dart';
import '../widgets/common.dart';
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
          ListTile(
            leading: const Icon(Icons.translate_rounded),
            title: Text(S.of(context).language),
            subtitle: Text(S.langName(app.languageCode)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showModalBottomSheet(
              context: context,
              showDragHandle: true,
              builder: (_) => SafeArea(
                child: LanguagePicker(
                  selected: app.languageCode,
                  onSelected: (code) {
                    app.setLanguage(code);
                    Navigator.pop(context);
                  },
                ),
              ),
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
          ListTile(
            leading: const Icon(Icons.battery_saver_outlined),
            title: const Text('Arka planda çalışma'),
            subtitle: const Text('Pil kısıtlamasını kaldır; uygulama kapalıyken de bildirim gelsin'),
            onTap: () async {
              if (await NativeBridge.isIgnoringBattery()) {
                if (context.mounted) showSnack(context, 'Pil kısıtlaması zaten kapalı ✅');
              } else {
                await NativeBridge.requestIgnoreBattery();
              }
            },
          ),
          head('Gizlilik'),
          ListTile(
            leading: const Icon(Icons.block_rounded),
            title: const Text('Engellenen hesaplar'),
            trailing: Text('${app.me?.blocked.length ?? 0}'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BlockedScreen())),
          ),
          head('Hakkında'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('FlinQ'),
            subtitle: Text('Sürüm 2.0 · derleme ${AppGuard.build}'),
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
          ListTile(
            leading: const Icon(Icons.delete_forever_rounded, color: FColors.danger),
            title: const Text('Hesabımı sil', style: TextStyle(color: FColors.danger, fontWeight: FontWeight.w600)),
            subtitle: const Text('Gönderilerin, hikayelerin ve profilin kalıcı olarak silinir'),
            onTap: () async {
              final ok = await confirmDialog(context,
                  title: 'Hesabını sil', message: 'Hesabın ve tüm gönderilerin kalıcı olarak silinecek. Bu işlem geri alınamaz.',
                  confirmText: 'Devam', destructive: true);
              if (!ok || !context.mounted) return;
              final pw = await promptText(context, title: 'Şifreni yaz', hint: 'Onaylamak için şifren', obscure: true, confirmText: 'Hesabımı sil');
              if (pw == null || pw.isEmpty || !context.mounted) return;
              final nav = Navigator.of(context);
              final err = await app.deleteMyAccount(pw);
              if (err != null) {
                if (context.mounted) showSnack(context, err, error: true);
              } else {
                nav.popUntil((r) => r.isFirst);
              }
            },
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}


class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ids = (app.me?.blocked ?? const <String>{}).toList();
    app.warmUsers(ids);
    return Scaffold(
      appBar: AppBar(title: const Text('Engellenen hesaplar')),
      body: ids.isEmpty
          ? const Center(child: Text('Kimseyi engellemedin.'))
          : ListView.builder(
              itemCount: ids.length,
              itemBuilder: (_, i) {
                final u = app.cachedUser(ids[i]);
                return ListTile(
                  leading: FAvatar(name: u?.username ?? '?', photo: u?.photo, size: 44),
                  title: Text(u?.username ?? '…'),
                  trailing: OutlinedButton(
                    onPressed: () => app.setBlocked(ids[i], false),
                    child: const Text('Engeli kaldır'),
                  ),
                );
              },
            ),
    );
  }
}
