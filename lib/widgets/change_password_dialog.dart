import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/gh_db_service.dart';
import '../theme.dart';

class ChangePasswordDialog extends ConsumerStatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  ConsumerState<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<ChangePasswordDialog> {
  final _oldCtrl  = TextEditingController();
  final _newCtrl  = TextEditingController();
  final _confCtrl = TextEditingController();
  bool _obscureOld  = true;
  bool _obscureNew  = true;
  bool _obscureConf = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _oldCtrl.dispose(); _newCtrl.dispose(); _confCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = ref.read(authProvider).currentUser;
    if (user == null) return;

    final oldHash = GhDbService.hashPassword(_oldCtrl.text);
    final db = GhDbService();

    // Verifica password attuale
    final raw = db.users.firstWhere(
      (u) => u['id'] == user.id,
      orElse: () => {},
    );
    if (raw.isEmpty || raw['password_hash'] != oldHash) {
      setState(() => _error = 'Password attuale non corretta.');
      return;
    }

    final newPwd = _newCtrl.text.trim();
    if (newPwd.length < 4) {
      setState(() => _error = 'La nuova password deve avere almeno 4 caratteri.');
      return;
    }
    if (newPwd != _confCtrl.text.trim()) {
      setState(() => _error = 'Le password non coincidono.');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      await db.updateUserPassword(user.id, GhDbService.hashPassword(newPwd));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() { _error = 'Errore: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kCard,
      title: const Text('Cambia password', style: TextStyle(color: kText)),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pwdField('Password attuale', _oldCtrl, _obscureOld,
                () => setState(() => _obscureOld = !_obscureOld)),
            const SizedBox(height: 12),
            _pwdField('Nuova password', _newCtrl, _obscureNew,
                () => setState(() => _obscureNew = !_obscureNew)),
            const SizedBox(height: 12),
            _pwdField('Conferma nuova password', _confCtrl, _obscureConf,
                () => setState(() => _obscureConf = !_obscureConf)),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: kError, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Annulla', style: TextStyle(color: kTextDim)),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Salva'),
        ),
      ],
    );
  }

  Widget _pwdField(String label, TextEditingController ctrl, bool obscure, VoidCallback toggle) =>
      TextField(
        controller: ctrl,
        obscureText: obscure,
        style: const TextStyle(color: kText),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffixIcon: IconButton(
            icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 18, color: kTextDim),
            onPressed: toggle,
          ),
        ),
      );
}
