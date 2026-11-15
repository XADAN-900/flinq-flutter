import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _register = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _register
              ? _RegisterFlow(key: const ValueKey('r'), onBack: () => setState(() => _register = false))
              : _LoginView(key: const ValueKey('l'), onRegister: () => setState(() => _register = true)),
        ),
      ),
    );
  }
}

class _LoginView extends StatefulWidget {
  final VoidCallback onRegister;
  const _LoginView({super.key, required this.onRegister});

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final _id = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AppState>().login(_id.text, _pass.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  Future<void> _forgot() async {
    final email = await promptText(context,
        title: 'Şifreni sıfırla',
        hint: 'E-posta adresin',
        initial: _id.text.contains('@') ? _id.text : '',
        confirmText: 'Bağlantı gönder');
    if (email == null || email.trim().isEmpty || !mounted) return;
    final err = await context.read<AppState>().resetPassword(email);
    if (!mounted) return;
    showSnack(context, err ?? 'Sıfırlama bağlantısı e-postana gönderildi.', error: err != null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Image.asset('assets/logo.png', width: 92, height: 92),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: GradientText('FlinQ',
                    style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: -1.5)),
              ),
              const SizedBox(height: 4),
              Text('Anlarını paylaş, keşfet.', textAlign: TextAlign.center, style: TextStyle(color: theme.hintColor)),
              const SizedBox(height: 28),
              TextField(
                controller: _id,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'E-posta veya kullanıcı adı',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pass,
                obscureText: _obscure,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'Şifre',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: _forgot, child: const Text('Şifreni mi unuttun?')),
              ),
              if (_error != null) _Err(_error!),
              const SizedBox(height: 8),
              _GradBtn(label: 'Giriş yap', busy: _busy, onTap: _submit),
              const SizedBox(height: 20),
              const Divider(),
              TextButton(
                onPressed: _busy ? null : widget.onRegister,
                child: const Text('Hesabın yok mu? Kaydol', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegisterFlow extends StatefulWidget {
  final VoidCallback onBack;
  const _RegisterFlow({super.key, required this.onBack});

  @override
  State<_RegisterFlow> createState() => _RegisterFlowState();
}

class _RegisterFlowState extends State<_RegisterFlow> {
  final _page = PageController();
  int _step = 0;
  final _user = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _bio = TextEditingController();
  Uint8List? _photo;
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  Timer? _debounce;
  bool _checking = false;
  bool? _available;

  @override
  void initState() {
    super.initState();
    _user.addListener(_onUser);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _page.dispose();
    super.dispose();
  }

  void _onUser() {
    final n = _user.text.trim();
    _debounce?.cancel();
    final err = n.isEmpty ? null : usernameError(n);
    setState(() {
      _available = null;
      _checking = n.isNotEmpty && err == null;
    });
    if (n.isEmpty || err != null) return;
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      bool taken;
      try {
        taken = await context.read<AppState>().isUsernameTaken(n);
      } catch (_) {
        if (mounted) setState(() => _checking = false);
        return;
      }
      if (!mounted || _user.text.trim() != n) return;
      setState(() {
        _checking = false;
        _available = !taken;
      });
    });
  }

  void _go(int s) {
    FocusScope.of(context).unfocus();
    setState(() {
      _step = s;
      _error = null;
    });
    _page.animateToPage(s, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  Future<void> _next() async {
    if (_step == 0) {
      final u = usernameError(_user.text.trim());
      String? e = u;
      if (e == null && _available == false) e = 'Bu kullanıcı adı zaten kullanılıyor.';
      if (e == null && !_email.text.contains('@')) e = 'Geçerli bir e-posta gir.';
      if (e == null && _pass.text.length < 6) e = 'Şifre en az 6 karakter olmalı.';
      if (e != null) {
        setState(() => _error = e);
        return;
      }
      _go(1);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AppState>().register(
          _user.text,
          _email.text,
          _pass.text,
          photoDataUrl: _photo == null ? null : toDataUrl(_photo!, 'image/jpeg'),
          bio: _bio.text,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  Future<void> _pick(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src, maxWidth: 480, maxHeight: 480, imageQuality: 85);
    if (x == null) return;
    final b = await x.readAsBytes();
    setState(() => _photo = b);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = _user.text.trim();
    Widget? suffix;
    if (_checking) {
      suffix = const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
    } else if (_available == true) {
      suffix = const Icon(Icons.check_circle_rounded, color: Color(0xFF2ECC71));
    } else if (_available == false || (n.isNotEmpty && usernameError(n) != null)) {
      suffix = const Icon(Icons.error_rounded, color: FColors.danger);
    }
    final uErr = n.isEmpty ? null : usernameError(n);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: _busy ? null : () => _step == 0 ? widget.onBack() : _go(0),
            ),
            Expanded(
              child: Row(children: [
                for (var i = 0; i < 2; i++)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: i <= _step ? FColors.brand : null,
                        color: i <= _step ? null : theme.dividerColor,
                      ),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_step == 0 ? 'Hesap oluştur' : 'Profilini tamamla',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(
                _step == 0
                    ? 'Kullanıcı adın profilinde ve etiketlerde görünür.'
                    : 'Fotoğraf ve biyografi ekle; insanlar seni daha kolay tanısın.',
                style: TextStyle(color: theme.hintColor),
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView(
            controller: _page,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
                children: [
                  TextField(
                    controller: _user,
                    maxLength: 20,
                    decoration: InputDecoration(
                      hintText: 'Kullanıcı adı',
                      prefixIcon: const Icon(Icons.alternate_email_rounded),
                      suffixIcon: suffix,
                      counterText: '',
                      helperText: uErr ??
                          (_available == true
                              ? '@$n kullanılabilir'
                              : _available == false
                                  ? 'Bu kullanıcı adı alınmış'
                                  : '3-20 karakter: harf, rakam ve _'),
                      helperStyle: TextStyle(
                        color: uErr != null || _available == false
                            ? FColors.danger
                            : (_available == true ? const Color(0xFF2ECC71) : theme.hintColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(hintText: 'E-posta', prefixIcon: Icon(Icons.mail_outline_rounded)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: _obscure,
                    onSubmitted: (_) => _next(),
                    decoration: InputDecoration(
                      hintText: 'Şifre (en az 6 karakter)',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                ],
              ),
              ListView(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 12),
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: () => _pick(ImageSource.gallery),
                      child: Stack(children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: FColors.brand),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(shape: BoxShape.circle, color: theme.scaffoldBackgroundColor),
                            child: _photo == null
                                ? FAvatar(name: n.isEmpty ? '?' : n, size: 120)
                                : ClipOval(child: Image.memory(_photo!, width: 120, height: 120, fit: BoxFit.cover)),
                          ),
                        ),
                        const Positioned(
                          right: 4,
                          bottom: 4,
                          child: CircleAvatar(
                            radius: 19,
                            backgroundColor: FColors.accent,
                            child: Icon(Icons.add_a_photo_rounded, color: Colors.white, size: 19),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: () => _pick(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Galeri'),
                      ),
                      TextButton.icon(
                        onPressed: () => _pick(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Kamera'),
                      ),
                      if (_photo != null)
                        TextButton(onPressed: () => setState(() => _photo = null), child: const Text('Kaldır')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bio,
                    maxLength: 150,
                    maxLines: 3,
                    minLines: 2,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Biyografi — kendinden bahset, #etiket ekle',
                      prefixIcon: Icon(Icons.edit_note_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Column(children: [
                      UserName(n, fontSize: 17),
                      if (_bio.text.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(_bio.text.trim(),
                              textAlign: TextAlign.center, style: TextStyle(color: theme.hintColor)),
                        ),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) _Err(_error!),
              const SizedBox(height: 8),
              _GradBtn(label: _step == 0 ? 'Devam' : 'Kaydol ve başla 🚀', busy: _busy, onTap: _next),
            ],
          ),
        ),
      ],
    );
  }
}

class _Err extends StatelessWidget {
  final String text;
  const _Err(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: FColors.danger)),
      );
}

class _GradBtn extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback onTap;
  const _GradBtn({required this.label, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(gradient: FColors.brand, borderRadius: BorderRadius.circular(12)),
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent),
          onPressed: busy ? null : onTap,
          child: busy
              ? const SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : Text(label, style: const TextStyle(color: Colors.white)),
        ),
      );
}
