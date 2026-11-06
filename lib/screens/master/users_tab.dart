import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/reference_models.dart';
import '../../models/user_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/amc_service.dart';
import '../../services/course_service.dart';
import '../../services/password_reset.dart';
import '../../services/reference_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';
import '../../utils/snackbar.dart';

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
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _load() => setState(() => _users = _userService.getAllUsers());

  Future<void> _reload() async {
    await ref.read(authProvider).reloadDb();
    if (mounted) _load();
  }

  Color _roleColor(UserRole r) => switch (r) {
    UserRole.adminMaster => Colors.purple,
    UserRole.courseDirector => kPrimary,
    UserRole.instructor => kAccent,
    UserRole.attendee => kWarning,
  };

  /// Filtro ruolo + ricerca; chi ha chiesto il reset della password in cima,
  /// poi per ruolo e cognome.
  List<AppUser> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _users
        .where((u) =>
            (_filterRole == null || u.userRole == _filterRole) &&
            (q.isEmpty ||
                '${u.fullName} ${u.nome} ${u.username ?? ''}'
                    .toLowerCase()
                    .contains(q)))
        .toList()
      ..sort((a, b) {
        if (a.passwordResetRequested != b.passwordResetRequested) {
          return a.passwordResetRequested ? -1 : 1;
        }
        final r = a.userRole.index.compareTo(b.userRole.index);
        return r != 0
            ? r
            : a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
      });
  }

  /// Intestazione del gruppo a cui appartiene la riga.
  String _groupOf(AppUser u) =>
      u.passwordResetRequested ? 'Reset password richiesto' : u.userRole.label;

  Future<void> _resetPassword(AppUser u) async {
    final temp = generateTempPassword();
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Reimposta password', style: TextStyle(color: kText)),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                u.passwordResetRequested
                    ? '${u.fullName} ha chiesto il reset della password.'
                    : 'Reimpostare la password di ${u.fullName}?',
                style: const TextStyle(color: kText),
              ),
              const SizedBox(height: 12),
              const Text('Password temporanea', style: TextStyle(color: kTextDim, fontSize: 12)),
              SelectableText(temp,
                  style: const TextStyle(color: kAccent, fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              const Text(
                'Annotala e comunicala di persona dopo aver verificato l\'identità: '
                'al primo accesso dovrà sceglierne una nuova.',
                style: TextStyle(color: kTextDim, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla', style: TextStyle(color: kTextDim)),
          ),
          if (u.passwordResetRequested)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'dismiss'),
              child: const Text('Ignora richiesta', style: TextStyle(color: kTextDim)),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'reset'),
            child: const Text('Reimposta'),
          ),
        ],
      ),
    );
    if (action == null) return;
    try {
      if (action == 'reset') {
        await _userService.resetPassword(u.id, temp);
      } else {
        await _userService.dismissPasswordResetRequest(u.id);
      }
    } catch (e) {
      showAppError('Operazione non riuscita: $e');
      return;
    }
    if (mounted) _load();
  }

  Future<void> _showUserDialog({AppUser? user}) async {
    final nomeCtrl = TextEditingController(text: user?.nome ?? '');
    final cognomeCtrl = TextEditingController(text: user?.cognome ?? '');
    final emailCtrl = TextEditingController(text: user?.email ?? '');
    final usernameCtrl = TextEditingController(text: user?.username ?? '');
    final passwordCtrl = TextEditingController();
    final titoloCtrl = TextEditingController(text: user?.titolo ?? '');
    UserRole selectedRole = user?.userRole ?? UserRole.attendee;
    String selectedForza = (user?.forza ?? 'EI').toUpperCase() == 'CC' ? 'CC' : 'EI';

    // Qualifiche AMC (solo istruttori): regole ANNESSO MTOE-P-3-1.
    final allQuals = _refService.amcQualifications();
    final qualGroups = <String, List<AmcQualification>>{};
    for (final q in allQuals) {
      qualGroups.putIfAbsent(q.group, () => []).add(q);
    }
    final selQuals = <String>{...?user?.qualifications};
    String? dlgError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          // Desktop: anagrafica a sinistra, dati di ruolo (grado/forza o
          // qualifiche AMC) a destra; mobile: tutto in colonna come prima.
          final hasExtra = selectedRole == UserRole.attendee ||
              (selectedRole == UserRole.instructor && allQuals.isNotEmpty);
          final screenW = MediaQuery.of(ctx).size.width;
          final wide = hasExtra && screenW >= 820;
          final base = <Widget>[
                  _field('Cognome', cognomeCtrl),
                  const SizedBox(height: 12),
                  _field('Nome', nomeCtrl),
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
                  if (dlgError != null) ...[
                    const SizedBox(height: 12),
                    Text(dlgError!, style: const TextStyle(color: kError, fontSize: 12)),
                  ],
          ];
          final extra = <Widget>[
                  if (selectedRole == UserRole.attendee) ...[
                    _field('Grado', titoloCtrl, hint: 'es. GRD, CAR. SC'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedForza,
                      dropdownColor: kSurface,
                      style: const TextStyle(color: kText),
                      decoration: const InputDecoration(
                        labelText: 'Forza (PS colonne)',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'EI', child: Text('EI — Esercito (sinistra)')),
                        DropdownMenuItem(value: 'CC', child: Text('CC — Carabinieri (destra)')),
                      ],
                      onChanged: (v) =>
                          setDlg(() => selectedForza = v ?? selectedForza),
                    ),
                  ],
                  if (selectedRole == UserRole.instructor && allQuals.isNotEmpty) ...[
                    if (!wide) ...const [
                      SizedBox(height: 4),
                      Divider(color: kBorder, height: 1),
                      SizedBox(height: 12),
                    ],
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Qualifiche istruttore (AMC)',
                          style: TextStyle(
                              color: kText, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'I sottomoduli insegnabili vengono assegnati in automatico secondo l\'ANNESSO MTOE-P-3-1.',
                      style: TextStyle(color: kTextDim, fontSize: 11),
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
                  ],
          ];
          return AlertDialog(
          backgroundColor: kCard,
          title: Text(user == null ? 'Nuovo utente' : 'Modifica utente',
              style: const TextStyle(color: kText)),
          content: SizedBox(
            width: wide ? (screenW - 96).clamp(0.0, 920.0) : 440,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Column(children: base)),
                          const SizedBox(width: 28),
                          Expanded(child: Column(children: extra)),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...base,
                          if (hasExtra) const SizedBox(height: 12),
                          ...extra,
                        ],
                      ),
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
                final nome = nomeCtrl.text.trim();
                final cognome = cognomeCtrl.text.trim();
                final username = usernameCtrl.text.trim();
                final password = passwordCtrl.text.trim();
                // Prima si chiudeva il dialog e si usciva in silenzio: i dati
                // inseriti andavano persi senza spiegazione.
                final err = nome.isEmpty || cognome.isEmpty || username.isEmpty
                    ? 'Cognome, nome e username sono obbligatori.'
                    : user == null && password.isEmpty
                        ? 'Inserisci la password del nuovo utente.'
                        : _users.any((o) =>
                                o.id != user?.id &&
                                (o.username ?? '').toLowerCase() ==
                                    username.toLowerCase())
                            ? 'Username «$username» già usato da un altro utente.'
                            : null;
                if (err != null) {
                  setDlg(() => dlgError = err);
                  return;
                }
                Navigator.pop(ctx);
                final isInstructor = selectedRole == UserRole.instructor;
                final isAttendee = selectedRole == UserRole.attendee;
                final grado = titoloCtrl.text.trim();
                try {
                  if (user == null) {
                    final created = await _userService.createUser(
                      nome: nome,
                      cognome: cognome,
                      email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                      username: username,
                      password: password,
                      role: selectedRole,
                      qualifications: isInstructor ? selQuals.toList() : null,
                      titolo: isAttendee && grado.isNotEmpty ? grado : null,
                      forza: isAttendee ? selectedForza : null,
                    );
                    if (isInstructor) {
                      await AmcService().applyQualifications(created.id, selQuals);
                    }
                  } else {
                    await _userService.updateUser(user.copyWith(
                      nome: nome,
                      cognome: cognome,
                      email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                      username: username,
                      role: selectedRole.value,
                      qualifications: isInstructor ? selQuals.toList() : user.qualifications,
                      titolo: isAttendee
                          ? (grado.isEmpty ? null : grado)
                          : user.titolo,
                      forza: isAttendee ? selectedForza : user.forza,
                    ));
                    if (password.isNotEmpty) {
                      await _userService.updatePassword(user.id, password);
                    }
                    if (isInstructor) {
                      await AmcService().applyQualifications(user.id, selQuals);
                    }
                  }
                } catch (e) {
                  showAppError('Salvataggio non riuscito: $e');
                } finally {
                  if (mounted) _reload();
                }
              },
              child: const Text('Salva'),
            ),
          ],
          );
        },
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
    if (ok != true) return;
    try {
      await _userService.deleteUser(u.id);
    } catch (e) {
      showAppError('Eliminazione non riuscita: $e');
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    // Frequentatore → corso/i di appartenenza, mostrati nella riga.
    final coursesOf = <String, List<String>>{};
    for (final c in CourseService().getAllCourses()) {
      for (final id in c.attendeeIds) {
        coursesOf.putIfAbsent(id, () => []).add(c.title);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(
            children: [
              Text('Utenti', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(width: 24),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: kText, fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Cerca per cognome, nome o username…',
                    prefixIcon: const Icon(Icons.search, size: 18, color: kTextDim),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 16, color: kTextDim),
                            onPressed: _searchCtrl.clear,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                  tooltip: 'Ricarica',
                  icon: const Icon(Icons.refresh, color: kTextDim),
                  onPressed: _reload),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _showUserDialog(),
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Nuovo utente'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final r in UserRole.values)
                FilterChip(
                  label: Text(
                      '${r.label} ${_users.where((u) => u.userRole == r).length}',
                      style: TextStyle(
                          fontSize: 11,
                          color: _filterRole == r ? Colors.white : kTextDim)),
                  selected: _filterRole == r,
                  selectedColor: _roleColor(r),
                  backgroundColor: kSurface,
                  onSelected: (v) => setState(() => _filterRole = v ? r : null),
                ),
              const SizedBox(width: 8),
              Text('${filtered.length} di ${_users.length} utenti',
                  style: const TextStyle(color: kTextDim, fontSize: 12)),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text('Nessun utente', style: TextStyle(color: kTextDim)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final u = filtered[i];
                    final group = _groupOf(u);
                    final header = i == 0 || _groupOf(filtered[i - 1]) != group;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (header)
                          Padding(
                            padding: const EdgeInsets.only(top: 14, bottom: 6),
                            child: Text(group.toUpperCase(),
                                style: TextStyle(
                                    color: u.passwordResetRequested
                                        ? kWarning
                                        : kTextDim,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5)),
                          ),
                        _userRow(u, coursesOf[u.id]),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _userRow(AppUser u, List<String>? courses) {
    final color = _roleColor(u.userRole);
    const dim = TextStyle(color: kTextDim, fontSize: 11);
    final grado = u.userRole == UserRole.attendee ? (u.titolo ?? '').trim() : '';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: () => _showUserDialog(user: u),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Text(
            u.cognome.isNotEmpty ? u.cognome[0].toUpperCase() : '?',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(grado.isEmpty ? u.fullName : '$grado ${u.fullName}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: kText, fontWeight: FontWeight.w500)),
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
              Flexible(
                  child: Text('@${u.username}',
                      overflow: TextOverflow.ellipsis, style: dim)),
            ],
            if (courses != null) ...[
              const SizedBox(width: 8),
              const Icon(Icons.school_outlined, size: 13, color: kTextDim),
              const SizedBox(width: 3),
              Flexible(
                  child: Text(courses.join(', '),
                      overflow: TextOverflow.ellipsis, style: dim)),
            ],
            if (u.email != null) ...[
              const SizedBox(width: 8),
              Flexible(
                  child: Text(u.email!,
                      overflow: TextOverflow.ellipsis, style: dim)),
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
            if (u.passwordResetRequested)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Text('Reset richiesto', style: TextStyle(color: kWarning, fontSize: 11)),
              ),
            IconButton(
              tooltip: 'Reimposta password',
              icon: Icon(Icons.lock_reset,
                  color: u.passwordResetRequested ? kWarning : kTextDim, size: 20),
              onPressed: () => _resetPassword(u),
            ),
            IconButton(
              tooltip: 'Modifica',
              icon: const Icon(Icons.edit_outlined, color: kTextDim, size: 20),
              onPressed: () => _showUserDialog(user: u),
            ),
            IconButton(
              tooltip: 'Elimina',
              icon: const Icon(Icons.delete_outline, color: kTextDim, size: 20),
              hoverColor: kError.withOpacity(0.15),
              onPressed: () => _deleteUser(u),
            ),
          ],
        ),
      ),
    );
  }
}
