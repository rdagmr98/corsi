import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/reference_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/reference_service.dart';
import '../../theme.dart';
import '../../utils/snackbar.dart';

class CourseTypesTab extends ConsumerStatefulWidget {
  const CourseTypesTab({super.key});

  @override
  ConsumerState<CourseTypesTab> createState() => _CourseTypesTabState();
}

class _CourseTypesTabState extends ConsumerState<CourseTypesTab> {
  final _refService = ReferenceService();
  List<CourseTypeInfo> _types = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _types = _refService.getCourseTypes();
      _loading = false;
    });
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    await ref.read(authProvider).reloadDb();
    _load();
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: const TextStyle(color: kTextDim, fontSize: 12)),
  );

  // Etichetta sopra il campo, MAI labelText dentro InputDecoration in campi
  // stretti (Row/SizedBox): il floating label di Material va a metà sul
  // bordo e si taglia quando lo spazio orizzontale è limitato.
  Widget _labeledField(String label, Widget field) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [_label(label), field],
  );

  // ── Dialog tipo corso (id/code/name/category/maxAttendees) ───────────────
  Future<void> _showCourseTypeDialog({CourseTypeInfo? type}) async {
    final isNew = type == null;
    final idCtrl = TextEditingController(text: type?.id ?? '');
    final codeCtrl = TextEditingController(text: type?.code ?? '');
    final nameCtrl = TextEditingController(text: type?.name ?? '');
    final maxCtrl = TextEditingController(text: '${type?.maxAttendees ?? 28}');
    String category = type?.category ?? 'B1';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: kCard,
          title: Text(isNew ? 'Nuovo tipo corso' : 'Modifica tipo corso',
              style: const TextStyle(color: kText)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Id (univoco, es. b1)'),
                  TextField(
                    controller: idCtrl,
                    enabled: isNew,
                    style: TextStyle(color: isNew ? kText : kTextDim),
                    decoration: const InputDecoration(isDense: true),
                  ),
                  const SizedBox(height: 12),
                  _label('Codice (es. TB1)'),
                  TextField(
                    controller: codeCtrl,
                    style: const TextStyle(color: kText),
                    decoration: const InputDecoration(isDense: true),
                  ),
                  const SizedBox(height: 12),
                  _label('Nome'),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: kText),
                    decoration: const InputDecoration(isDense: true),
                  ),
                  const SizedBox(height: 12),
                  _label('Categoria'),
                  DropdownButtonFormField<String>(
                    value: category,
                    dropdownColor: kSurface,
                    style: const TextStyle(color: kText),
                    decoration: const InputDecoration(isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'B1', child: Text('B1')),
                      DropdownMenuItem(value: 'B2', child: Text('B2')),
                    ],
                    onChanged: (v) => setDlg(() => category = v ?? 'B1'),
                  ),
                  const SizedBox(height: 12),
                  _label('Max frequentatori'),
                  TextField(
                    controller: maxCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: kText),
                    decoration: const InputDecoration(isDense: true),
                  ),
                  if (isNew)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Il calendario settimanale viene copiato da un tipo corso esistente. '
                        'I moduli si aggiungono dopo la creazione.',
                        style: TextStyle(color: kTextDim, fontSize: 11),
                      ),
                    ),
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
                final id = idCtrl.text.trim();
                final code = codeCtrl.text.trim();
                final name = nameCtrl.text.trim();
                final maxAttendees = int.tryParse(maxCtrl.text.trim()) ?? 28;
                if (id.isEmpty || code.isEmpty || name.isEmpty) return;

                final types = _refService.getCourseTypes();
                if (isNew) {
                  if (types.any((t) => t.id == id)) {
                    showAppError('Esiste già un tipo corso con id "$id".');
                    return;
                  }
                  final template = types.isNotEmpty
                      ? types.first.schedule
                      : const ScheduleTemplate(mondayThursday: [], friday: [], hoursPerWeek: 27);
                  types.add(CourseTypeInfo(
                    id: id,
                    code: code,
                    name: name,
                    category: category,
                    maxAttendees: maxAttendees,
                    schedule: template,
                    modules: const [],
                  ));
                } else {
                  final idx = types.indexWhere((t) => t.id == type.id);
                  if (idx < 0) {
                    Navigator.pop(ctx);
                    return;
                  }
                  types[idx] = CourseTypeInfo(
                    id: type.id,
                    code: code,
                    name: name,
                    category: category,
                    maxAttendees: maxAttendees,
                    schedule: types[idx].schedule,
                    modules: types[idx].modules,
                  );
                }
                Navigator.pop(ctx);
                try {
                  await _refService.saveCourseTypes(types);
                } catch (_) {
                  showAppError('Salvataggio tipo corso non riuscito. Riprova.');
                } finally {
                  _reload();
                }
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCourseType(CourseTypeInfo t) async {
    if (_refService.isCourseTypeInUse(t.id)) {
      showAppError('Impossibile eliminare: il tipo corso "${t.code}" è usato da almeno un corso esistente.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Elimina tipo corso', style: TextStyle(color: kText)),
        content: Text('Eliminare "${t.code} — ${t.name}" e tutti i suoi moduli?',
            style: const TextStyle(color: kTextDim)),
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
    final types = _refService.getCourseTypes()..removeWhere((x) => x.id == t.id);
    try {
      await _refService.saveCourseTypes(types);
    } catch (_) {
      showAppError('Eliminazione non riuscita. Riprova.');
    } finally {
      _reload();
    }
  }

  // ── Dialog dettaglio: elenco moduli di un tipo corso ──────────────────────
  Future<void> _showCourseTypeDetailDialog(CourseTypeInfo ct) async {
    var modules = List<ModuleInfo>.from(ct.modules);

    void refresh(StateSetter setDlg) {
      final fresh = _refService.getCourseType(ct.id);
      setDlg(() => modules = List<ModuleInfo>.from(fresh?.modules ?? []));
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Dialog(
          backgroundColor: kCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: 760,
            height: MediaQuery.of(ctx).size.height * 0.8,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('${ct.code} — ${ct.name}',
                            style: const TextStyle(color: kText, fontSize: 17, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await _showModuleDialog(ct.id);
                          refresh(setDlg);
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Nuovo modulo'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: kTextDim),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(color: kBorder, height: 1),
                Expanded(
                  child: modules.isEmpty
                      ? const Center(child: Text('Nessun modulo', style: TextStyle(color: kTextDim)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: modules.length,
                          itemBuilder: (_, i) {
                            final m = modules[i];
                            return Card(
                              color: kSurface,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Container(
                                  width: 4,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: moduleColor(m.number),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                title: Text('M${m.displayCode} — ${m.name}',
                                    style: const TextStyle(color: kText, fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  'Teoria ${m.theoryHours}h · Pratica ${m.practicalHours}h · ${m.submodules.length} sottomoduli',
                                  style: const TextStyle(color: kTextDim, fontSize: 12),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, color: kTextDim, size: 20),
                                      onPressed: () async {
                                        await _showModuleDialog(ct.id, module: m);
                                        refresh(setDlg);
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: kError, size: 20),
                                      onPressed: () async {
                                        await _deleteModule(ct.id, m);
                                        refresh(setDlg);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    _reload();
  }

  Future<void> _deleteModule(String courseTypeId, ModuleInfo m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Elimina modulo', style: TextStyle(color: kText)),
        content: Text('Eliminare il modulo M${m.displayCode} — ${m.name}?',
            style: const TextStyle(color: kTextDim)),
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
    final types = _refService.getCourseTypes();
    final idx = types.indexWhere((t) => t.id == courseTypeId);
    if (idx < 0) return;
    final ct = types[idx];
    final newModules = ct.modules.where((mm) => mm.number != m.number).toList();
    types[idx] = CourseTypeInfo(
      id: ct.id,
      code: ct.code,
      name: ct.name,
      category: ct.category,
      maxAttendees: ct.maxAttendees,
      schedule: ct.schedule,
      modules: newModules,
    );
    try {
      await _refService.saveCourseTypes(types);
    } catch (_) {
      showAppError('Eliminazione modulo non riuscita. Riprova.');
    }
  }

  // ── Dialog modulo: campi + sottomoduli + task pratici (draft locale) ─────
  Future<void> _showModuleDialog(String courseTypeId, {ModuleInfo? module}) async {
    final isNew = module == null;
    final originalNumber = module?.number;
    final draft = isNew
        ? _ModuleDraft.empty(_refService.nextTaskId())
        : _ModuleDraft.fromModule(module, _refService.nextTaskId());

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final simple = draft.submodules.length <= 1;
          return AlertDialog(
            backgroundColor: kCard,
            title: Text(isNew ? 'Nuovo modulo' : 'Modifica modulo M${module.displayCode}',
                style: const TextStyle(color: kText)),
            content: SizedBox(
              width: 720,
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 80,
                          child: _labeledField(
                            'Numero',
                            TextField(
                              controller: draft.number,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: kText),
                              decoration: const InputDecoration(isDense: true),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 90,
                          child: _labeledField(
                            'Etichetta',
                            TextField(
                              controller: draft.label,
                              style: const TextStyle(color: kText),
                              decoration: const InputDecoration(hintText: 'es. 11A', isDense: true),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _labeledField(
                            'Nome modulo',
                            TextField(
                              controller: draft.name,
                              style: const TextStyle(color: kText),
                              decoration: const InputDecoration(isDense: true),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 160,
                          child: _labeledField(
                            'Domande esame',
                            TextField(
                              controller: draft.examQuestions,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: kText),
                              decoration: const InputDecoration(isDense: true),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 160,
                          child: _labeledField(
                            'Minuti esame',
                            TextField(
                              controller: draft.examMinutes,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: kText),
                              decoration: const InputDecoration(isDense: true),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (simple)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 160,
                            child: _labeledField(
                              'Teoria (ore)',
                              TextField(
                                controller: draft.theory,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: kText),
                                decoration: const InputDecoration(isDense: true),
                                onChanged: (_) => setDlg(() {}),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 160,
                            child: _labeledField(
                              'Pratica (ore)',
                              TextField(
                                controller: draft.practical,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: kText),
                                decoration: const InputDecoration(isDense: true),
                                onChanged: (_) => setDlg(() {}),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          'Teoria ${draft.submodules.fold<int>(0, (s, x) => s + (int.tryParse(x.theory.text.trim()) ?? 0))}h · '
                          'Pratica ${draft.submodules.fold<int>(0, (s, x) => s + (int.tryParse(x.practical.text.trim()) ?? 0))}h '
                          '— calcolato dalla somma dei sottomoduli',
                          style: const TextStyle(color: kTextDim, fontSize: 12),
                        ),
                      ),
                    const Divider(color: kBorder, height: 28),
                    Row(
                      children: [
                        Text('Sottomoduli (${draft.submodules.length})',
                            style: const TextStyle(color: kTextDim, fontSize: 12)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => setDlg(() => draft.submodules.add(_SubmoduleDraft())),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Aggiungi sottomodulo'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...draft.submodules.asMap().entries.map(
                          (e) => _buildSubmoduleCard(setDlg, draft, e.value, e.key),
                        ),
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
                  final name = draft.name.text.trim();
                  final number = int.tryParse(draft.number.text.trim());
                  if (name.isEmpty || number == null) return;

                  final types = _refService.getCourseTypes();
                  final idx = types.indexWhere((t) => t.id == courseTypeId);
                  if (idx < 0) {
                    Navigator.pop(ctx);
                    return;
                  }
                  final ct = types[idx];
                  final newModule = draft.toModule();
                  final others = ct.modules.where((mm) => mm.number != (originalNumber ?? -1)).toList();
                  if (others.any((mm) => mm.number == newModule.number)) {
                    showAppError('Esiste già un modulo numero ${newModule.number} in questo tipo corso.');
                    return;
                  }
                  final newModules = List<ModuleInfo>.from(ct.modules);
                  final mIdx = originalNumber != null
                      ? newModules.indexWhere((mm) => mm.number == originalNumber)
                      : -1;
                  if (mIdx >= 0) {
                    newModules[mIdx] = newModule;
                  } else {
                    newModules.add(newModule);
                  }
                  types[idx] = CourseTypeInfo(
                    id: ct.id,
                    code: ct.code,
                    name: ct.name,
                    category: ct.category,
                    maxAttendees: ct.maxAttendees,
                    schedule: ct.schedule,
                    modules: newModules,
                  );
                  Navigator.pop(ctx);
                  try {
                    await _refService.saveCourseTypes(types);
                  } catch (_) {
                    showAppError('Salvataggio modulo non riuscito. Riprova.');
                  }
                },
                child: const Text('Salva'),
              ),
            ],
          );
        },
      ),
    );
    draft.dispose();
  }

  Widget _buildSubmoduleCard(StateSetter setDlg, _ModuleDraft draft, _SubmoduleDraft s, int i) {
    return Card(
      key: ObjectKey(s),
      color: kSurface,
      margin: const EdgeInsets.only(bottom: 6),
      child: ExpansionTile(
        key: ObjectKey(s),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Row(
          children: [
            SizedBox(
              width: 70,
              child: TextField(
                controller: s.code,
                style: const TextStyle(color: kText, fontSize: 13),
                decoration: const InputDecoration(isDense: true, hintText: 'Codice'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: s.name,
                style: const TextStyle(color: kText, fontSize: 13),
                decoration: const InputDecoration(isDense: true, hintText: 'Nome sottomodulo'),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: kError, size: 18),
              onPressed: () => setDlg(() => draft.submodules.removeAt(i).dispose()),
            ),
          ],
        ),
        subtitle: Builder(builder: (_) {
          final practicalPlanned = int.tryParse(s.practical.text.trim()) ?? 0;
          final taskSum = s.tasks.fold<int>(0, (acc, t) => acc + (int.tryParse(t.hours.text.trim()) ?? 0));
          final mismatch = s.tasks.isNotEmpty && taskSum != practicalPlanned;
          return Text(
            '${s.theory.text.isEmpty ? 0 : s.theory.text}h teoria · '
            '${s.practical.text.isEmpty ? 0 : s.practical.text}h pratica · '
            'task ${taskSum}h${mismatch ? ' (≠ pratica)' : ''}',
            style: TextStyle(color: mismatch ? kError : kTextDim, fontSize: 11),
          );
        }),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: _labeledField(
                        'Teoria (ore)',
                        TextField(
                          controller: s.theory,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: kText),
                          decoration: const InputDecoration(isDense: true),
                          onChanged: (_) => setDlg(() {}),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: _labeledField(
                        'Pratica (ore)',
                        TextField(
                          controller: s.practical,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: kText),
                          decoration: const InputDecoration(isDense: true),
                          onChanged: (_) => setDlg(() {}),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: _labeledField(
                        'Livello',
                        TextField(
                          controller: s.level,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: kText),
                          decoration: const InputDecoration(isDense: true),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _labeledField(
                  'Argomenti (separati da virgola)',
                  TextField(
                    controller: s.topics,
                    style: const TextStyle(color: kText),
                    decoration: const InputDecoration(isDense: true),
                  ),
                ),
                const Divider(color: kBorder, height: 24),
                Row(
                  children: [
                    const Text('Task pratici', style: TextStyle(color: kTextDim, fontSize: 12)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => setDlg(() => s.tasks.add(_TaskDraft(id: '${draft.nextTaskId()}'))),
                      icon: const Icon(Icons.add, size: 14),
                      label: const Text('Aggiungi task', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                if (s.tasks.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      SizedBox(width: 60, child: _label('ID')),
                      const SizedBox(width: 8),
                      Expanded(child: _label('Nome task')),
                      const SizedBox(width: 8),
                      SizedBox(width: 80, child: _label('Ore')),
                      const SizedBox(width: 32),
                    ],
                  ),
                ],
                ...s.tasks.asMap().entries.map((te) {
                  final j = te.key;
                  final t = te.value;
                  return Padding(
                    key: ObjectKey(t),
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 60,
                          child: TextField(
                            controller: t.programId,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: kText, fontSize: 12),
                            decoration: const InputDecoration(isDense: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: t.name,
                            style: const TextStyle(color: kText, fontSize: 12),
                            decoration: const InputDecoration(isDense: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: t.hours,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(color: kText, fontSize: 12),
                            decoration: const InputDecoration(isDense: true),
                            onChanged: (_) => setDlg(() {}),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: kError, size: 16),
                          onPressed: () => setDlg(() => s.tasks.removeAt(j).dispose()),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: kPrimary));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(
            children: [
              Text('Tipi Corso', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(icon: const Icon(Icons.refresh, color: kTextDim), onPressed: _reload),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _showCourseTypeDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuovo tipo corso'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _types.isEmpty
              ? const Center(child: Text('Nessun tipo corso', style: TextStyle(color: kTextDim)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _types.length,
                  itemBuilder: (_, i) {
                    final t = _types[i];
                    final inUse = _refService.isCourseTypeInUse(t.id);
                    return Card(
                      color: kCard,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: kBorder),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _showCourseTypeDetailDialog(t),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          title: Row(
                            children: [
                              Text(t.code, style: const TextStyle(color: kText, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: kPrimary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(t.category, style: const TextStyle(color: kPrimary, fontSize: 10)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(t.name,
                                    style: const TextStyle(color: kTextDim), overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            '${t.modules.length} moduli · Teoria ${t.totalTheoryHours}h · '
                            'Pratica ${t.totalPracticalHours}h · Tot ${t.totalHours}h'
                            '${inUse ? ' · in uso' : ''}',
                            style: const TextStyle(color: kTextDim, fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: kTextDim, size: 20),
                                onPressed: () => _showCourseTypeDialog(type: t),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: kError, size: 20),
                                onPressed: () => _deleteCourseType(t),
                              ),
                            ],
                          ),
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

// ── Draft locali per editing in memoria prima del salvataggio ──────────────

// Evita lo ".0" superfluo per le ore intere, mantenendo i decimali (es. 1.5h) quando presenti.
String _fmtNum(num n) => n == n.truncate() ? n.truncate().toString() : n.toString();

class _TaskDraft {
  // Id interno univoco su tutto reference.json (auto-generato, non editabile in UI).
  final TextEditingController id;
  // Numero task del programma ufficiale (riparte da 1 per tipo corso): questo è il campo
  // che l'admin legge dal PDF e modifica — vedi PracticalTask.programTaskId.
  final TextEditingController programId;
  final TextEditingController name;
  final TextEditingController hours;

  _TaskDraft({String id = '', String programId = '', String name = '', String hours = '0'})
      : id = TextEditingController(text: id),
        programId = TextEditingController(text: programId),
        name = TextEditingController(text: name),
        hours = TextEditingController(text: hours);

  factory _TaskDraft.fromTask(PracticalTask t) => _TaskDraft(
        id: '${t.id}',
        programId: '${t.programTaskId}',
        name: t.name,
        hours: _fmtNum(t.plannedHours),
      );

  PracticalTask toTask() {
    final rawId = int.tryParse(id.text.trim()) ?? 0;
    return PracticalTask(
      id: rawId,
      programTaskId: int.tryParse(programId.text.trim()) ?? rawId,
      name: name.text.trim(),
      plannedHours: double.tryParse(hours.text.trim().replaceAll(',', '.')) ?? 0,
    );
  }

  void dispose() {
    id.dispose();
    programId.dispose();
    name.dispose();
    hours.dispose();
  }
}

class _SubmoduleDraft {
  final TextEditingController code;
  final TextEditingController name;
  final TextEditingController theory;
  final TextEditingController practical;
  final TextEditingController level;
  final TextEditingController topics;
  final List<_TaskDraft> tasks;
  final int? perDifferenzaOf;

  _SubmoduleDraft({
    String code = '',
    String name = '',
    String theory = '0',
    String practical = '0',
    String level = '',
    String topics = '',
    List<_TaskDraft>? tasks,
    this.perDifferenzaOf,
  })  : code = TextEditingController(text: code),
        name = TextEditingController(text: name),
        theory = TextEditingController(text: theory),
        practical = TextEditingController(text: practical),
        level = TextEditingController(text: level),
        topics = TextEditingController(text: topics),
        tasks = tasks ?? [];

  factory _SubmoduleDraft.fromSub(SubmoduleInfo s) => _SubmoduleDraft(
        code: s.code,
        name: s.name,
        theory: '${s.theoryHours}',
        practical: '${s.practicalHours}',
        level: s.level?.toString() ?? '',
        topics: s.topics.join(', '),
        tasks: s.practicalTasks.map(_TaskDraft.fromTask).toList(),
        perDifferenzaOf: s.perDifferenzaOf,
      );

  SubmoduleInfo toSubmodule() => SubmoduleInfo(
        code: code.text.trim(),
        name: name.text.trim(),
        theoryHours: int.tryParse(theory.text.trim()) ?? 0,
        practicalHours: int.tryParse(practical.text.trim()) ?? 0,
        level: int.tryParse(level.text.trim()),
        topics: topics.text.trim().isEmpty
            ? const []
            : topics.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
        practicalTasks: tasks.map((t) => t.toTask()).toList(),
        perDifferenzaOf: perDifferenzaOf,
      );

  void dispose() {
    code.dispose();
    name.dispose();
    theory.dispose();
    practical.dispose();
    level.dispose();
    topics.dispose();
    for (final t in tasks) {
      t.dispose();
    }
  }
}

class _ModuleDraft {
  final TextEditingController number;
  final TextEditingController label;
  final TextEditingController name;
  final TextEditingController examQuestions;
  final TextEditingController examMinutes;
  final TextEditingController theory;
  final TextEditingController practical;
  final List<_SubmoduleDraft> submodules;
  int _idCounter;

  _ModuleDraft({
    String number = '',
    String label = '',
    String name = '',
    String examQuestions = '0',
    String examMinutes = '0',
    String theory = '0',
    String practical = '0',
    List<_SubmoduleDraft>? submodules,
    int idCounter = 1,
  })  : number = TextEditingController(text: number),
        label = TextEditingController(text: label),
        name = TextEditingController(text: name),
        examQuestions = TextEditingController(text: examQuestions),
        examMinutes = TextEditingController(text: examMinutes),
        theory = TextEditingController(text: theory),
        practical = TextEditingController(text: practical),
        submodules = submodules ?? [],
        _idCounter = idCounter;

  factory _ModuleDraft.empty(int seedTaskId) => _ModuleDraft(idCounter: seedTaskId);

  factory _ModuleDraft.fromModule(ModuleInfo m, int seedTaskId) => _ModuleDraft(
        number: '${m.number}',
        label: m.label ?? '',
        name: m.name,
        examQuestions: '${m.examQuestions}',
        examMinutes: '${m.examMinutes}',
        theory: '${m.theoryHours}',
        practical: '${m.practicalHours}',
        submodules: m.submodules.map(_SubmoduleDraft.fromSub).toList(),
        idCounter: seedTaskId,
      );

  int nextTaskId() => _idCounter++;

  ModuleInfo toModule() {
    final subsRaw = submodules.map((s) => s.toSubmodule()).toList();
    final simple = subsRaw.length <= 1;
    int th, pr;
    List<SubmoduleInfo> subs;
    if (simple) {
      th = int.tryParse(theory.text.trim()) ?? 0;
      pr = int.tryParse(practical.text.trim()) ?? 0;
      subs = subsRaw.isEmpty
          ? const []
          : [
              SubmoduleInfo(
                code: subsRaw[0].code,
                name: subsRaw[0].name,
                theoryHours: th,
                practicalHours: pr,
                level: subsRaw[0].level,
                topics: subsRaw[0].topics,
                practicalTasks: subsRaw[0].practicalTasks,
                perDifferenzaOf: subsRaw[0].perDifferenzaOf,
              ),
            ];
    } else {
      th = subsRaw.fold(0, (s, x) => s + x.theoryHours);
      pr = subsRaw.fold(0, (s, x) => s + x.practicalHours);
      subs = subsRaw;
    }
    return ModuleInfo(
      number: int.tryParse(number.text.trim()) ?? 0,
      label: label.text.trim().isEmpty ? null : label.text.trim(),
      name: name.text.trim(),
      theoryHours: th,
      practicalHours: pr,
      examQuestions: int.tryParse(examQuestions.text.trim()) ?? 0,
      examMinutes: int.tryParse(examMinutes.text.trim()) ?? 0,
      submodules: subs,
    );
  }

  void dispose() {
    number.dispose();
    label.dispose();
    name.dispose();
    examQuestions.dispose();
    examMinutes.dispose();
    theory.dispose();
    practical.dispose();
    for (final s in submodules) {
      s.dispose();
    }
  }
}
