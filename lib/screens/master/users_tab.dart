import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/reference_models.dart';
import '../../models/user_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/amc_service.dart';
import '../../services/gh_db_service.dart';
import '../../services/reference_service.dart';
import '../../services/schedule_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';

class UsersTab extends ConsumerStatefulWidget {
  const UsersTab({super.key});

  @override
  ConsumerState<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<UsersTab> {
  final _userService = UserService();
  final _refService = ReferenceService();
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
    final titoloCtrl = TextEditingController(text: user?.titolo ?? '');
    final licenzaCtrl = TextEditingController(text: user?.licenza ?? '');
    UserRole selectedRole = user?.userRole ?? UserRole.attendee;

    // Qualifiche AMC (solo istruttori): regole ANNESSO MTOE-P-3-1.
    final allQuals = _refService.amcQualifications();
    final qualGroups = <String, List<AmcQualification>>{};
    for (final q in allQuals) {
      qualGroups.putIfAbsent(q.group, () => []).add(q);
    }
    final selQuals = <String>{...?user?.qualifications};
    bool qualsTouched = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: kCard,
          title: Text(user == null ? 'Nuovo utente' : 'Modifica utente',
              style: const TextStyle(color: kText)),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
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
                  if (selectedRole == UserRole.instructor && allQuals.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(color: kBorder, height: 1),
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Qualifiche istruttore (AMC)',
                          style: TextStyle(
                              color: kText, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Expanded(
                          child: Text(
                            'I sottomoduli insegnabili vengono assegnati in automatico secondo l\'ANNESSO MTOE-P-3-1.',
                            style: TextStyle(color: kTextDim, fontSize: 11),
                          ),
                        ),
                        if (user != null) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            ),
                            onPressed: () {
                              final db = GhDbService();
                              final taughtT = <String>{};
                              final taughtP = <String>{};
                              for (final l in db.schedules) {
                                if (l['instructor_id'] != user.id) continue;
                                final nc = ScheduleService.normalizeSubCode(
                                    l['submodule_code'] as String? ?? '');
                                if (nc.isEmpty) continue;
                                if (l['type'] == 'teoria') taughtT.add(nc);
                                else taughtP.add(nc);
                              }
                              final suggested = _refService
                                  .reverseEngineerQuals(taughtT, taughtP);
                              setDlg(() {
                                qualsTouched = true;
                                selQuals
                                  ..clear()
                                  ..addAll(suggested);
                              });
                            },
                            child: const Text('Auto-rileva', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final entry in qualGroups.entries) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(entry.key,
                            style: const TextStyle(
                                color: kTextDim,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final q in entry.value)
                              FilterChip(
                                label: Text(q.label,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: selQuals.contains(q.id)
                                            ? Colors.white
                                            : kTextDim)),
                                selected: selQuals.contains(q.id),
                                selectedColor: kPrimary,
                                checkmarkColor: Colors.white,
                                backgroundColor: kSurface,
                                visualDensity: VisualDensity.compact,
                                onSelected: (v) => setDlg(() {
                                  qualsTouched = true;
                                  v ? selQuals.add(q.id) : selQuals.remove(q.id);
                                }),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: kSurface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Sottomoduli insegnabili: '
                        '${_refService.teachableSubmodules(selQuals, theory: true).length} teoria · '
                        '${_refService.teachableSubmodules(selQuals, theory: false).length} pratica',
                        style: const TextStyle(color: kAccent, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _field('Titolo abilitazione', titoloCtrl)),
                        const SizedBox(width: 8),
                        Expanded(child: _field('Licenza Part-66', licenzaCtrl)),
                      ],
                    ),
                  ],
                ],
              ),
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
                final isInstructor = selectedRole == UserRole.instructor;
                if (user == null) {
                  if (password.isEmpty) return;
                  final created = await _userService.createUser(
                    nome: nome,
                    cognome: cognome,
                    email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                    username: username,
                    password: password,
                    role: selectedRole,
                    qualifications: isInstructor ? selQuals.toList() : null,
                    titolo: isInstructor && titoloCtrl.text.trim().isNotEmpty
                        ? titoloCtrl.text.trim() : null,
                    licenza: isInstructor && licenzaCtrl.text.trim().isNotEmpty
                        ? licenzaCtrl.text.trim() : null,
                  );
                  if (isInstructor) {
                    await AmcService().applyQualifications(created.id, selQuals);
                  }
                } else {
                  // Le griglie AMC si toccano solo se le qualifiche sono state
                  // compilate (ora o in passato): gli istruttori storici senza
                  // qualifiche registrate restano gestiti a mano.
                  final setQuals =
                      isInstructor && (qualsTouched || user.qualifications != null);
                  await _userService.updateUser(user.copyWith(
                    nome: nome,
                    cognome: cognome,
                    email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                    username: username,
                    role: selectedRole.value,
                    qualifications:
                        setQuals ? selQuals.toList() : user.qualifications,
                    titolo: isInstructor && titoloCtrl.text.trim().isNotEmpty
                        ? titoloCtrl.text.trim() : null,
                    licenza: isInstructor && licenzaCtrl.text.trim().isNotEmpty
                        ? licenzaCtrl.text.trim() : null,
                  ));
                  if (password.isNotEmpty) {
                    await _userService.updatePassword(user.id, password);
                  }
                  if (setQuals) {
                    await AmcService().applyQualifications(user.id, selQuals);
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
