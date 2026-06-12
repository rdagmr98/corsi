import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/user_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/user_service.dart';
import '../../theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _userService = UserService();
  bool _obscure = true;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final auth = ref.read(authProvider);
    final ok = await auth.login(_usernameCtrl.text.trim(), _passwordCtrl.text);
    if (!ok || !mounted) return;
    final user = auth.currentUser!;
    switch (user.userRole) {
      case UserRole.adminMaster:
        context.go('/master');
      case UserRole.courseDirector:
        context.go('/director');
      case UserRole.instructor:
        context.go('/instructor');
      case UserRole.attendee:
        context.go('/attendee');
    }
  }

  Future<void> _register() async {
    final nomeCtrl = TextEditingController();
    final cognomeCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    UserRole role = UserRole.attendee;
    String? error;
    bool busy = false;
    bool obscure = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: kCard,
          title: const Text('Registrazione', style: TextStyle(color: kText, fontSize: 16)),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nomeCtrl,
                    decoration: const InputDecoration(labelText: 'Nome', isDense: true),
                    style: const TextStyle(color: kText),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: cognomeCtrl,
                    decoration: const InputDecoration(labelText: 'Cognome', isDense: true),
                    style: const TextStyle(color: kText),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: userCtrl,
                    decoration: const InputDecoration(labelText: 'Username', isDense: true),
                    style: const TextStyle(color: kText),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passCtrl,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          color: kTextDim,
                          size: 18,
                        ),
                        onPressed: () => setDlg(() => obscure = !obscure),
                      ),
                    ),
                    style: const TextStyle(color: kText),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<UserRole>(
                    value: role,
                    dropdownColor: kSurface,
                    isExpanded: true,
                    style: const TextStyle(color: kText),
                    decoration: const InputDecoration(labelText: 'Ruolo', isDense: true),
                    items: const [
                      DropdownMenuItem(
                        value: UserRole.attendee,
                        child: Text('Frequentatore'),
                      ),
                      DropdownMenuItem(
                        value: UserRole.instructor,
                        child: Text('Istruttore'),
                      ),
                    ],
                    onChanged: (v) => setDlg(() => role = v ?? UserRole.attendee),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!,
                        style: const TextStyle(color: kError, fontSize: 12),
                        textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Annulla', style: TextStyle(color: kTextDim)),
            ),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      final nome = nomeCtrl.text.trim();
                      final cognome = cognomeCtrl.text.trim();
                      final username = userCtrl.text.trim();
                      final password = passCtrl.text;
                      if (nome.isEmpty ||
                          cognome.isEmpty ||
                          username.isEmpty ||
                          password.length < 4) {
                        setDlg(() => error =
                            'Compila tutti i campi (password di almeno 4 caratteri).');
                        return;
                      }
                      setDlg(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await ref.read(authProvider).initDb();
                        if (_userService.usernameExists(username)) {
                          setDlg(() {
                            busy = false;
                            error = 'Username già in uso.';
                          });
                          return;
                        }
                        await _userService.createUser(
                          nome: nome,
                          cognome: cognome,
                          username: username,
                          password: password,
                          role: role,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        _usernameCtrl.text = username;
                        _passwordCtrl.text = password;
                        await _login();
                      } catch (e) {
                        setDlg(() {
                          busy = false;
                          error = 'Errore di registrazione: $e';
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Registrati'),
            ),
          ],
        ),
      ),
    );

    nomeCtrl.dispose();
    cognomeCtrl.dispose();
    userCtrl.dispose();
    passCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(
                  'assets/images/smam_logo.png',
                  width: 140,
                  height: 140,
                ),
                const SizedBox(height: 16),
                Text(
                  'Gestione Corsi',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 24,
                    color: kText,
                  ),
                ),
                Text(
                  'Manutenzione Aeronautica',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline, color: kTextDim),
                  ),
                  style: const TextStyle(color: kText),
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline, color: kTextDim),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        color: kTextDim,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  style: const TextStyle(color: kText),
                  onSubmitted: (_) => _login(),
                ),
                if (auth.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    auth.error!,
                    style: const TextStyle(color: kError, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: auth.isLoading ? null : _login,
                  child: auth.isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Accedi'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: auth.isLoading ? null : _register,
                  child: const Text(
                    'Non hai un account? Registrati',
                    style: TextStyle(color: kTextDim, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
