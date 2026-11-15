import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _user;
  late final TextEditingController _bio;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _user = TextEditingController(text: app.username);
    _bio = TextEditingController(text: app.me?.bio ?? '');
  }

  Future<void> _photo() async {
    final app = context.read<AppState>();
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeriden seç'),
              onTap: () => Navigator.pop(ctx, 'gallery')),
          ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Fotoğraf çek'),
              onTap: () => Navigator.pop(ctx, 'camera')),
          if ((app.me?.photo ?? '').isNotEmpty)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: FColors.danger),
              title: const Text('Fotoğrafı kaldır', style: TextStyle(color: FColors.danger)),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
        ]),
      ),
    );
    if (action == null) return;
    if (action == 'remove') {
      await app.updateProfile(removePhoto: true);
      return;
    }
    final x = await ImagePicker().pickImage(
      source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 480,
      maxHeight: 480,
      imageQuality: 85,
    );
    if (x == null) return;
    final b = await x.readAsBytes();
    await app.updateProfile(photo: toDataUrl(b, 'image/jpeg'));
    if (mounted) showSnack(context, 'Profil fotoğrafı güncellendi.');
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    setState(() => _busy = true);
    String? err;
    if (_user.text.trim() != app.username) {
      err = await app.changeUsername(_user.text);
    }
    if (err == null) await app.updateProfile(bio: _bio.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      showSnack(context, err, error: true);
    } else {
      showSnack(context, 'Profil güncellendi.');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final left = app.usernameCooldownLeftDays;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profili düzenle'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Bitti', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: FAvatar(name: app.username, photo: app.me?.photo, size: 96)),
          Center(
            child: TextButton(onPressed: _photo, child: const Text('Fotoğrafı düzenle')),
          ),
          const SizedBox(height: 8),
          const Text('Kullanıcı adı', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            controller: _user,
            enabled: left == 0,
            maxLength: 20,
            decoration: const InputDecoration(prefixText: '@'),
          ),
          Text(
            left > 0
                ? 'Kullanıcı adını tekrar değiştirmek için $left gün beklemelisin.'
                : 'Kullanıcı adını 15 günde bir değiştirebilirsin.',
            style: TextStyle(color: theme.hintColor, fontSize: 12),
          ),
          const SizedBox(height: 18),
          const Text('Biyografi', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            controller: _bio,
            maxLines: 4,
            maxLength: 150,
            decoration: const InputDecoration(hintText: 'Kendinden bahset… #etiket @kullanıcı'),
          ),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.mail_outline_rounded),
            title: const Text('E-posta'),
            subtitle: Text(app.user?.email ?? app.me?.email ?? ''),
          ),
        ],
      ),
    );
  }
}
