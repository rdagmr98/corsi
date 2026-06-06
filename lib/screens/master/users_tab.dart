import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/user_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/user_service.dart';
import '../../theme.dart';

class UsersTab extends ConsumerStatefulWidget {
  const UsersTab({super.key});

  @override
  ConsumerState<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<UsersTab> {
  final _userService = UserService();
  List<AppUser> _users = [];
  UserRole? _filterRole;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _users = _userService.getAllUsers());

  Future<void> _reload() async {
    await ref.read(authProvider).reloadDb();
    _load();
  }

  Color _roleColor(UserRole r) => switch (r) {
    UserRole.adminMaster => Colors.purple,
    UserRole.courseDirector => kPrimary,
    UserRole.instructor => kAccent,
    UserRole.attendee => kWarning,
  };

  List<AppUser> get _filtered => _filterRole == null
      ? _users
      : _users.where((u) => u.userRole == _filterRole).toList();

  Future<void> _showUserDialog({AppUser? user}) async {
    final nomeCtrl = TextEditingController(text: user?.nome ?? '');
    final cognomeCtrl = TextEditingController(text: user?.cognome ?? '');
    final emailCtrl = TextEditingController(text: user?.email ?? '');
    final usernameCtrl = TextEditingController(text: user?.username ?? '');
    final passwordCtrl = TextEditingController();
    UserRole selectedRole = user?.userRole ?? UserRole.attendee;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: kCard,
          title: Text(user == null ? 'Nuovo utente' : 'Modifica utente',
              style: const TextStyle(color: kText)),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: _field('Cognome', cognomeCtrl)),
                    const SizedBox(width: 12),
                    Expanded(child: _field('Nome', nomeCtrl)),
                  ],
                ),
                const SizedBox(height: 12),
                _field('Email', emailCtrl, hint: 'opzionale'),
                const SizedBox(height: 12),
                _field('Username', usernameCtrl),
                const SizedBox(height: 12),
                _field(
                  user == null ? 'Password' : 'Nuova password (lascia vuoto per non cambiare)',
                  passwordCtrl,
                  obscure: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  value: selectedRole,
                  dropdownColor: kSurface,
                  style: const TextStyle(color: kText),
                  decoration: const InputDecoration(labelText: 'Ruolo', isDense: true),
                  items: UserRole.values
                      .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                      .toList(),
                  onChanged: (v) => setDlg(() => selectedRole = v ?? selectedRole),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla', style: TextStyle(color: kTextDim)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final nome = nomeCtrl.text.trim();
                final cognome = cognomeCtrl.text.trim();
                final username = usernameCtrl.text.trim();
                final password = passwordCtrl.text.trim();
                if (nome.isEmpty || cognome.isEmpty || username.isEmpty) return;
                if (user == null) {
                  if (password.isEmpty) return;
                  await _userService.createUser(
                    nome: nome,
                    cognome: cognome,
                    email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                    username: username,
                    password: password,
                    role: selectedRole,
                  );
                } else {
                  await _userService.updateUser(user.copyWith(
                    nome: nome,
                    cognome: cognome,
                    email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                    username: username,
                    role: selectedRole.value,
                  ));
                  if (password.isNotEmpty) {
                    await _userService.updatePassword(user.id, password);
                  }
                }
                _reload();
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {String? hint, bool obscure = false}) =>
      TextField(
        controller: ctrl,
        obscureText: obscure,
        style: const TextStyle(color: kText),
        decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
      );

  Future<void> _deleteUser(AppUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Elimina utente', style: TextStyle(color: kText)),
        content: Text('Eliminare ${u.fullName}?', style: const TextStyle(color: kTextDim)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kError),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _userService.deleteUser(u.id);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(
            children: [
              Text('Utenti', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              ...UserRole.values.map((r) => Padding(
                padding: const EdgeInsets.only(left: 6),
                child: FilterChip(
                  label: Text(r.label, style: TextStyle(fontSize: 11, color: _filterRole == r ? Colors.white : kTextDim)),
                  selected: _filterRole == r,
                  selectedColor: _roleColor(r),
                  backgroundColor: kSurface,
                  onSelected: (v) => setState(() => _filterRole = v ? r : null),
                ),
              )),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.refresh, color: kTextDim), onPressed: _reload),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _showUserDialog(),
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Nuovo utente'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text('${filtered.length} utenti', style: const TextStyle(color: kTextDim, fontSize: 12)),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final u = filtered[i];
              final color = _roleColor(u.userRole);
              return Card(
                color: kCard,
                margin: const EdgeInsets.only(bottom: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: color.withOpacity(0.2)),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withOpacity(0.15),
                    child: Text(
                      u.cognome.isNotEmpty ? u.cognome[0].toUpperCase() : '?',
                      style: TextStyle(color: color, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(u.fullName, style: const TextStyle(color: kText, fontWeight: FontWeight.w500)),
                  subtitle: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(u.userRole.label, style: TextStyle(color: color, fontSize: 10)),
                      ),
                      if (u.username != null) ...[
                        const SizedBox(width: 8),
                        Text('@${u.username}', style: const TextStyle(color: kTextDim, fontSize: 11)),
                      ],
                      if (u.email != null) ...[
                        const SizedBox(width: 8),
                        Text(u.email!, style: const TextStyle(color: kTextDim, fontSize: 11)),
                      ],
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!u.isActive)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Text('Disattivo', style: TextStyle(color: kError, fontSize: 11)),
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: kTextDim, size: 20),
                        onPressed: () => _showUserDialog(user: u),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: kError, size: 20),
                        onPressed: () => _deleteUser(u),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
