import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _id = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppState>();
    final err = _register
        ? await app.register(_user.text, _id.text, _pass.text)
        : await app.login(_id.text, _pass.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  Future<void> _forgot() async {
    final email = await promptText(context,
        title: 'Şifreni sıfırla', hint: 'E-posta adresin', initial: _id.text.contains('@') ? _id.text : '',
        confirmText: 'Bağlantı gönder');
    if (email == null || email.trim().isEmpty || !mounted) return;
    final err = await context.read<AppState>().resetPassword(email);
    if (!mounted) return;
    showSnack(context, err ?? 'Sıfırlama bağlantısı e-postana gönderildi.', error: err != null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
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
                  Text(
                    _register ? 'Arkadaşlarının fotoğraf ve videolarını görmek için kaydol.' : 'Anlarını paylaş, keşfet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.hintColor),
                  ),
                  const SizedBox(height: 28),
                  if (_register) ...[
                    TextField(
                      controller: _user,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(hintText: 'Kullanıcı adı', prefixIcon: Icon(Icons.alternate_email)),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: _id,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: _register ? 'E-posta' : 'E-posta veya kullanıcı adı',
                      prefixIcon: const Icon(Icons.mail_outline_rounded),
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
                  if (!_register)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(onPressed: _forgot, child: const Text('Şifreni mi unuttun?')),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: FColors.danger)),
                    ),
                  const SizedBox(height: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(gradient: FColors.brand, borderRadius: BorderRadius.circular(12)),
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent),
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                          : Text(_register ? 'Kaydol' : 'Giriş yap', style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _register = !_register;
                              _error = null;
                            }),
                    child: Text(_register ? 'Hesabın var mı? Giriş yap' : 'Hesabın yok mu? Kaydol'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
