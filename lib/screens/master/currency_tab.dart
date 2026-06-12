import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/user_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/gh_db_service.dart';
import '../../services/grade_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';

class CurrencyTab extends ConsumerStatefulWidget {
  const CurrencyTab({super.key});
  @override
  ConsumerState<CurrencyTab> createState() => _CurrencyTabState();
}

class _CurrencyTabState extends ConsumerState<CurrencyTab> {
  final _userService  = UserService();
  final _gradeService = GradeService();
  final _db           = GhDbService();
  List<AppUser> _instructors = [];
  bool? _filterGo; // null=tutti, true=GO, false=NO-GO
  _SortMode _sortMode = _SortMode.name;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _instructors = _userService.getInstructors();
    });
  }

  Future<void> _reload() async {
    await ref.read(authProvider).reloadDb();
    _load();
  }

  // ── AMC helpers ───────────────────────────────────────────────────────────
  List<String> _theoryMods(String uid) {
    final grid = _db.amcData['theoryGrid'] as Map<String, dynamic>? ?? {};
    return grid.entries
        .where((e) => (e.value as List).contains(uid))
        .map((e) => e.key)
        .toList()..sort();
  }

  List<String> _practiceMods(String uid) {
    final grid = _db.amcData['practiceGrid'] as Map<String, dynamic>? ?? {};
    return grid.entries
        .where((e) => (e.value as List).contains(uid))
        .map((e) => e.key)
        .toList()..sort();
  }

  // ── Ore confermate per istruttore (lezioni confirmed + recuperi) ─────────
  Map<String, int> _confirmedHoursMap(bool theory) {
    final result = <String, int>{};
    for (final raw in _db.schedules) {
      final instr = raw['instructor_id'] as String?;
      if (instr == null) continue;
      if (raw['confirmed'] != true) continue;
      if ((raw['time_slot'] as int? ?? 0) <= 0) continue;
      final isT = raw['type'] != 'pratica';
      if (isT == theory) result[instr] = (result[instr] ?? 0) + 1;
    }
    // I recuperi confermati contano come ore di lezione per l'istruttore (teoria)
    if (theory) {
      for (final raw in _db.records) {
        if (raw['justification'] != 'recupero') continue;
        if (raw['present'] != true) continue;
        final instr = raw['confirmed_by'] as String?;
        if (instr == null || instr.isEmpty) continue;
        result[instr] = (result[instr] ?? 0) + 1;
      }
    }
    return result;
  }

  // ── Ore insegnamento per anno (rolling) ───────────────────────────────────
  List<Map<String, dynamic>> _teachingByYear(String uid) {
    final byYear = <int, double>{};
    for (final u in _db.updates
        .where((u) => u['instructor_id'] == uid && u['type'] == 'teaching')) {
      final yr = DateTime.tryParse(u['date'] as String? ?? '')?.year ?? 0;
      byYear[yr] = (byYear[yr] ?? 0) + ((u['hours'] as num?)?.toDouble() ?? 0);
    }
    // Le lezioni validate/confermate a calendario contano 1h ciascuna,
    // come nel totale currency (GradeService.getTeachingHoursRollingYear).
    for (final raw in _db.schedules) {
      if (raw['instructor_id'] != uid) continue;
      if (raw['confirmed'] != true) continue;
      if ((raw['time_slot'] as int? ?? 0) <= 0) continue;
      final yr = DateTime.tryParse(raw['date'] as String? ?? '')?.year ?? 0;
      byYear[yr] = (byYear[yr] ?? 0) + 1;
    }
    return byYear.entries
        .map((e) => {'year': e.key, 'hours': e.value})
        .toList()
      ..sort((a, b) => (b['year'] as int).compareTo(a['year'] as int));
  }

  // ── Group update dialog ───────────────────────────────────────────────────
  Future<void> _addGroupUpdate() async {
    final hoursCtrl = TextEditingController();
    final descCtrl  = TextEditingController();
    String type = 'professional';
    DateTime date = DateTime.now();
    final selectedInstructors = <String>{};

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: kCard,
          title: const Text('Aggiornamento di gruppo', style: TextStyle(color: kText)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  value: type,
                  dropdownColor: kSurface,
                  style: const TextStyle(color: kText),
                  decoration: const InputDecoration(labelText: 'Tipo', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'teaching',     child: Text('Ore insegnamento')),
                    DropdownMenuItem(value: 'professional', child: Text('Aggiornamento professionale')),
                  ],
                  onChanged: (v) => setDlg(() => type = v ?? type),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hoursCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: kText),
                  decoration: const InputDecoration(labelText: 'Ore', isDense: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  style: const TextStyle(color: kText),
                  decoration: const InputDecoration(labelText: 'Descrizione', isDense: true),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Text(DateFormat('dd/MM/yyyy').format(date),
                      style: const TextStyle(color: kText)),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) setDlg(() => date = d);
                    },
                    child: const Text('Cambia'),
                  ),
                ]),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Istruttori:', style: TextStyle(color: kTextDim, fontSize: 12)),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _instructors.map((i) {
                    final sel = selectedInstructors.contains(i.id);
                    return FilterChip(
                      label: Text(i.fullName,
                          style: TextStyle(
                              color: sel ? Colors.white : kTextDim,
                              fontSize: 11)),
                      selected: sel,
                      selectedColor: kPrimary.withOpacity(0.8),
                      backgroundColor: kSurface,
                      onSelected: (v) => setDlg(() {
                        if (v) selectedInstructors.add(i.id);
                        else selectedInstructors.remove(i.id);
                      }),
                    );
                  }).toList(),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla', style: TextStyle(color: kTextDim)),
            ),
            ElevatedButton(
              onPressed: () async {
                final hours = double.tryParse(hoursCtrl.text.trim()) ?? 0;
                if (hours <= 0 || selectedInstructors.isEmpty) return;
                Navigator.pop(ctx);
                for (final id in selectedInstructors) {
                  await _gradeService.addUpdate(
                    instructorId: id,
                    type: type,
                    hours: hours,
                    description: descCtrl.text.trim(),
                    date: date,
                  );
                }
                _reload();
              },
              child: Text('Aggiungi a ${selectedInstructors.length} istruttori'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Add update dialog ─────────────────────────────────────────────────────
  Future<void> _addUpdate(AppUser instr) async {
    final hoursCtrl = TextEditingController();
    final descCtrl  = TextEditingController();
    String type = 'professional';
    DateTime date = DateTime.now();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: kCard,
          title: Text('Aggiorna ore – ${instr.cognome}',
              style: const TextStyle(color: kText)),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: type,
                dropdownColor: kSurface,
                style: const TextStyle(color: kText),
                decoration: const InputDecoration(labelText: 'Tipo', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'teaching',     child: Text('Ore insegnamento')),
                  DropdownMenuItem(value: 'professional', child: Text('Aggiornamento professionale')),
                ],
                onChanged: (v) => setDlg(() => type = v ?? type),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hoursCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: kText),
                decoration: const InputDecoration(labelText: 'Ore', isDense: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                style: const TextStyle(color: kText),
                decoration: const InputDecoration(labelText: 'Descrizione', isDense: true),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Text(DateFormat('dd/MM/yyyy').format(date),
                    style: const TextStyle(color: kText)),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (d != null) setDlg(() => date = d);
                  },
                  child: const Text('Cambia'),
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla', style: TextStyle(color: kTextDim)),
            ),
            ElevatedButton(
              onPressed: () async {
                final hours = double.tryParse(hoursCtrl.text.trim()) ?? 0;
                if (hours <= 0) return;
                Navigator.pop(ctx);
                await _gradeService.addUpdate(
                  instructorId: instr.id,
                  type: type,
                  hours: hours,
                  description: descCtrl.text.trim(),
                  date: date,
                );
                _reload();
              },
              child: const Text('Aggiungi'),
            ),
          ],
        ),
      ),
    );
  }

  // ── DAAA expiry dialog ────────────────────────────────────────────────────
  Future<void> _editDaaExpiry(AppUser instr) async {
    DateTime? expiry = instr.daaExpiry;

    final confirmed = await showDialog<Object?>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: kCard,
          title: Text('Scadenza DAAA – ${instr.cognome}',
              style: const TextStyle(color: kText)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
              'Aggiornamento biennale istruttore NAM/DAAA (M10)',
              style: TextStyle(color: kTextDim, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: Text(
                  expiry != null
                      ? DateFormat('dd/MM/yyyy').format(expiry!)
                      : 'Non impostata',
                  style: TextStyle(
                    color: expiry == null
                        ? kTextDim
                        : expiry!.isBefore(DateTime.now())
                            ? kError
                            : kAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: expiry ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (d != null) setDlg(() => expiry = d);
                },
                child: const Text('Cambia'),
              ),
              if (expiry != null)
                TextButton(
                  onPressed: () => setDlg(() => expiry = null),
                  child: const Text('Rimuovi', style: TextStyle(color: kError)),
                ),
            ]),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla', style: TextStyle(color: kTextDim)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, expiry ?? const _RemoveDate()),
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == null) return;
    final newExpiry = confirmed is _RemoveDate ? null : confirmed as DateTime;
    await _userService.setDaaExpiry(instr.id, newExpiry);
    _reload();
  }

  // ── GO override dialog ────────────────────────────────────────────────────
  Future<void> _toggleGoOverride(AppUser instr) async {
    final newVal = !instr.goOverride;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: Text(newVal ? 'Imposta GO manuale' : 'Rimuovi GO manuale',
            style: const TextStyle(color: kText)),
        content: Text(
          newVal
              ? '${instr.cognome} sarà marcato GO indipendentemente dalle ore di lezione (OJT / ripristino currency).\n\nConfirmi?'
              : 'Rimuovere il GO manuale per ${instr.cognome}? La valutazione tornerà automatica.',
          style: const TextStyle(color: kTextDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla', style: TextStyle(color: kTextDim)),
          ),
          ElevatedButton(
            style: newVal ? null : ElevatedButton.styleFrom(backgroundColor: kError),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(newVal ? 'Imposta GO' : 'Rimuovi'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _userService.setGoOverride(instr.id, newVal);
      _reload();
    }
  }

  // ── Detail dialog ─────────────────────────────────────────────────────────
  void _showDetail(AppUser instr) {
    final teachH   = _gradeService.getTeachingHoursRollingYear(instr.id);
    final profH    = _gradeService.getProfessionalUpdateHoursLast2Years(instr.id);
    final theoryM  = _theoryMods(instr.id);
    final practM   = _practiceMods(instr.id);
    final byYear   = _teachingByYear(instr.id);
    final profList = _gradeService.getUpdatesForInstructor(instr.id)
        .where((u) => u.isProfessional)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final goTeach  = instr.goOverride || teachH >= 6;
    final goProf   = instr.goOverride || profH >= 35;
    final goDaa    = instr.daaExpiry == null || instr.goOverride ||
        instr.daaExpiry!.isAfter(DateTime.now());
    final go       = goTeach && goProf && goDaa;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlg) => Dialog(
          backgroundColor: kCard,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
            child: Column(children: [
              // Header
              Container(
                color: kSurface,
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                child: Row(children: [
                  Expanded(child: Text(instr.fullName,
                      style: const TextStyle(color: kText, fontSize: 18,
                          fontWeight: FontWeight.bold))),
                  if (instr.goOverride)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kWarning.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: kWarning),
                      ),
                      child: const Text('OJT', style: TextStyle(color: kWarning,
                          fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  _goBadge(go),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: kPrimary),
                    tooltip: 'Aggiungi ore',
                    onPressed: () {
                      Navigator.pop(context);
                      _addUpdate(instr);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: kTextDim),
                    onPressed: () => Navigator.pop(context),
                  ),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Currency ─────────────────────────────────────────
                      _sectionTitle('Idoneità (Currency)'),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: _currencyCard(
                          'Ore lezione (ultimi 365 giorni)',
                          teachH, 6, goTeach,
                          override: instr.goOverride,
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _currencyCard(
                          'Ore aggiornamento professionale (2 anni)',
                          profH, 35, goProf,
                        )),
                      ]),
                      const SizedBox(height: 8),
                      _daaCard(instr, goDaa),
                      const SizedBox(height: 4),
                      // Override toggle
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _toggleGoOverride(instr);
                        },
                        icon: Icon(
                          instr.goOverride ? Icons.lock_open : Icons.how_to_reg,
                          size: 16,
                          color: instr.goOverride ? kError : kWarning,
                        ),
                        label: Text(
                          instr.goOverride
                              ? 'Rimuovi GO manuale (OJT)'
                              : 'Imposta GO manuale per OJT / ripristino',
                          style: TextStyle(
                              color: instr.goOverride ? kError : kWarning,
                              fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: instr.goOverride ? kError : kWarning),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Ore insegnamento per anno ────────────────────────
                      _sectionTitle('Storico ore insegnamento per anno'),
                      const SizedBox(height: 8),
                      if (byYear.isEmpty)
                        const Text('Nessun dato',
                            style: TextStyle(color: kTextDim, fontSize: 12))
                      else
                        ...byYear.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            SizedBox(
                              width: 44,
                              child: Text('${e['year']}',
                                  style: const TextStyle(color: kTextDim,
                                      fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                            Expanded(child: LinearProgressIndicator(
                              value: ((e['hours'] as double) / 100).clamp(0.0, 1.0),
                              color: kPrimary,
                              backgroundColor: kSurface,
                              minHeight: 6,
                              borderRadius: BorderRadius.circular(3),
                            )),
                            const SizedBox(width: 8),
                            Text('${(e['hours'] as double).toStringAsFixed(0)}h',
                                style: const TextStyle(color: kText, fontSize: 12)),
                          ]),
                        )),
                      const SizedBox(height: 20),

                      // ── Aggiornamenti professionali ──────────────────────
                      _sectionTitle(
                          'Aggiornamenti professionali (ultimi 2 anni: '
                          '${profH.toStringAsFixed(0)}h / 35h)'),
                      const SizedBox(height: 8),
                      if (profList.isEmpty)
                        const Text('Nessun aggiornamento registrato',
                            style: TextStyle(color: kTextDim, fontSize: 12))
                      else
                        ...profList.map((u) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(children: [
                            SizedBox(
                              width: 72,
                              child: Text(
                                DateFormat('MM/yyyy').format(u.date),
                                style: const TextStyle(color: kTextDim, fontSize: 11),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: kAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('${u.hours.toStringAsFixed(0)}h',
                                  style: const TextStyle(color: kAccent,
                                      fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(u.description,
                                style: const TextStyle(color: kTextDim, fontSize: 11),
                                overflow: TextOverflow.ellipsis)),
                          ]),
                        )),
                      const SizedBox(height: 20),

                      // ── Sottomoduli abilitati ────────────────────────────
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionTitle('Teoria (${theoryM.length} sottomod.)'),
                            const SizedBox(height: 6),
                            theoryM.isEmpty
                                ? const Text('—',
                                    style: TextStyle(color: kTextDim, fontSize: 11))
                                : Wrap(
                                    spacing: 4, runSpacing: 4,
                                    children: theoryM
                                        .map((s) => _chip(s, kPrimary))
                                        .toList(),
                                  ),
                          ],
                        )),
                        const SizedBox(width: 16),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionTitle('Pratica (${practM.length} sottomod.)'),
                            const SizedBox(height: 6),
                            practM.isEmpty
                                ? const Text('—',
                                    style: TextStyle(color: kTextDim, fontSize: 11))
                                : Wrap(
                                    spacing: 4, runSpacing: 4,
                                    children: practM
                                        .map((s) => _chip(s, kAccent))
                                        .toList(),
                                  ),
                          ],
                        )),
                      ]),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Widget helpers ────────────────────────────────────────────────────────
  Widget _goBadge(bool go) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: (go ? kAccent : kError).withOpacity(0.15),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: go ? kAccent : kError),
    ),
    child: Text(go ? 'GO' : 'NO-GO',
        style: TextStyle(
            color: go ? kAccent : kError,
            fontWeight: FontWeight.bold,
            fontSize: 12)),
  );

  Widget _currencyCard(String label, double val, double req, bool ok,
      {bool override = false}) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: ok
                  ? (override ? kWarning.withOpacity(0.4) : kAccent.withOpacity(0.3))
                  : kError.withOpacity(0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: kTextDim, fontSize: 11)),
          const SizedBox(height: 6),
          Row(children: [
            if (override)
              const Text('OJT', style: TextStyle(color: kWarning,
                  fontSize: 22, fontWeight: FontWeight.bold))
            else
              Text(val.toStringAsFixed(0),
                  style: TextStyle(
                      color: ok ? kAccent : kError,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
            Text(override ? '' : ' / ${req.toStringAsFixed(0)}h',
                style: const TextStyle(color: kTextDim, fontSize: 13)),
          ]),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: override ? 1.0 : (val / req).clamp(0.0, 1.0),
            color: override ? kWarning : (ok ? kAccent : kError),
            backgroundColor: kBg,
            minHeight: 5,
            borderRadius: BorderRadius.circular(3),
          ),
        ]),
      );

  Widget _daaCard(AppUser instr, bool ok) {
    final expiry = instr.daaExpiry;
    final color  = expiry == null ? kTextDim : (ok ? kAccent : kError);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(expiry == null ? 0.15 : 0.35)),
      ),
      child: Row(children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Aggiornamento biennale DAAA (M10)',
                style: TextStyle(color: kTextDim, fontSize: 11)),
            const SizedBox(height: 4),
            Text(
              expiry == null
                  ? 'Non applicabile'
                  : 'Scade: ${DateFormat('dd/MM/yyyy').format(expiry)}',
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: expiry != null ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        )),
        if (expiry != null && !ok)
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: kError.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('SCADUTA', style: TextStyle(color: kError, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        TextButton.icon(
          onPressed: () {
            Navigator.pop(context);
            _editDaaExpiry(instr);
          },
          icon: const Icon(Icons.edit_calendar, size: 14),
          label: Text(expiry == null ? 'Imposta' : 'Modifica',
              style: const TextStyle(fontSize: 11)),
          style: TextButton.styleFrom(
            foregroundColor: kPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
        ),
      ]),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          color: kText, fontSize: 13, fontWeight: FontWeight.bold));

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 10)),
  );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // Compute GO for each instructor
    final rows = _instructors.map((instr) {
      final teachH = _gradeService.getTeachingHoursRollingYear(instr.id);
      final profH  = _gradeService.getProfessionalUpdateHoursLast2Years(instr.id);
      final goT  = instr.goOverride || teachH >= 6;
      final goP  = instr.goOverride || profH >= 35;
      final goDaa = instr.daaExpiry == null || instr.goOverride || instr.daaExpiry!.isAfter(now);
      final go  = goT && goP && goDaa;
      return (instr: instr, teachH: teachH, profH: profH, goT: goT, goP: goP, goDaa: goDaa, go: go);
    }).toList();

    // Filter
    final filtered = _filterGo == null
        ? rows
        : rows.where((r) => r.go == _filterGo).toList();

    // Sort
    filtered.sort((a, b) => switch (_sortMode) {
      _SortMode.name    => a.instr.cognome.compareTo(b.instr.cognome),
      _SortMode.goFirst => b.go ? 1 : (a.go ? -1 : a.instr.cognome.compareTo(b.instr.cognome)),
      _SortMode.noGoFirst => a.go ? 1 : (b.go ? -1 : a.instr.cognome.compareTo(b.instr.cognome)),
      _SortMode.teachH  => b.teachH.compareTo(a.teachH),
      _SortMode.profH   => b.profH.compareTo(a.profH),
    });

    final goCount   = rows.where((r) => r.go).length;
    final noGoCount = rows.length - goCount;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        child: Row(children: [
          Text('Idoneità Istruttori (${_instructors.length})',
              style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _addGroupUpdate,
            icon: const Icon(Icons.groups, size: 16),
            label: const Text('Aggiornamento di gruppo', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          ),
          const SizedBox(width: 8),
          IconButton(
              icon: const Icon(Icons.refresh, color: kTextDim),
              onPressed: _reload),
        ]),
      ),
      // Filters + Sort bar
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Row(children: [
          // GO filter chips
          _filterChip('Tutti', _filterGo == null, kTextDim,
              () => setState(() => _filterGo = null)),
          const SizedBox(width: 6),
          _filterChip('GO ($goCount)', _filterGo == true, kAccent,
              () => setState(() => _filterGo = true)),
          const SizedBox(width: 6),
          _filterChip('NO-GO ($noGoCount)', _filterGo == false, kError,
              () => setState(() => _filterGo = false)),
          const Spacer(),
          // Sort menu
          PopupMenuButton<_SortMode>(
            color: kSurface,
            tooltip: 'Ordina',
            icon: const Icon(Icons.sort, color: kTextDim, size: 20),
            onSelected: (m) => setState(() => _sortMode = m),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _SortMode.name,     child: Text('A-Z', style: TextStyle(color: kText))),
              PopupMenuItem(value: _SortMode.goFirst,  child: Text('GO prima', style: TextStyle(color: kText))),
              PopupMenuItem(value: _SortMode.noGoFirst,child: Text('NO-GO prima', style: TextStyle(color: kText))),
              PopupMenuItem(value: _SortMode.teachH,   child: Text('Ore lezione ↓', style: TextStyle(color: kText))),
              PopupMenuItem(value: _SortMode.profH,    child: Text('Ore aggiorn. ↓', style: TextStyle(color: kText))),
            ],
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: const Text(
          'GO se: ≥6h insegnamento (365gg) E ≥35h aggiorn. prof. (2 anni). OJT manuale bypassa entrambi.',
          style: TextStyle(color: kTextDim, fontSize: 11),
        ),
      ),
      Expanded(
        child: Builder(builder: (context) {
          final theoryH  = _confirmedHoursMap(true);
          final practiceH = _confirmedHoursMap(false);
          return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          itemCount: filtered.length,
          itemBuilder: (_, i) {
            final r      = filtered[i];
            final instr  = r.instr;
            final teachH = r.teachH;
            final profH  = r.profH;
            final goT    = r.goT;
            final goP    = r.goP;
            final go     = r.go;
            final goDaa  = r.goDaa;

            return Card(
              color: kCard,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                    color: go
                        ? kAccent.withOpacity(0.2)
                        : kError.withOpacity(0.2)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _showDetail(instr),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    _goBadge(go),
                    const SizedBox(width: 14),
                    // Nome
                    SizedBox(
                      width: 200,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(instr.fullName,
                              style: const TextStyle(color: kText,
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          if (instr.goOverride)
                            const Text('GO manuale (OJT)',
                                style: TextStyle(color: kWarning, fontSize: 10)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _miniStat('Lez. 365gg',
                        instr.goOverride ? 'OJT' : '${teachH.toStringAsFixed(0)}h / 6h',
                        goT),
                    const SizedBox(width: 16),
                    _miniStat('Aggiorn. 2 anni',
                        '${profH.toStringAsFixed(0)}h / 35h',
                        goP),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(spacing: 4, runSpacing: 4, children: [
                        _chip('T: ${theoryH[instr.id] ?? 0}h', kPrimary),
                        _chip('P: ${practiceH[instr.id] ?? 0}h', kAccent),
                        if (instr.daaExpiry != null)
                          _chip(
                            'DAAA ${DateFormat('MM/yy').format(instr.daaExpiry!)}',
                            goDaa ? kAccent : kError,
                          ),
                      ]),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline,
                          color: kPrimary, size: 20),
                      tooltip: 'Aggiungi ore',
                      onPressed: () => _addUpdate(instr),
                    ),
                    const Icon(Icons.chevron_right, color: kTextDim, size: 18),
                  ]),
                ),
              ),
            );
          },
        );
        }),
      ),
    ]);
  }

  Widget _miniStat(String label, String val, bool ok) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: kTextDim, fontSize: 10)),
      Text(val,
          style: TextStyle(
              color: ok ? kAccent : kError,
              fontSize: 12,
              fontWeight: FontWeight.bold)),
    ],
  );

  Widget _filterChip(String label, bool selected, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.15) : kSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? color : kBorder),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? color : kTextDim,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
        ),
      );
}

enum _SortMode { name, goFirst, noGoFirst, teachH, profH }

class _RemoveDate {
  const _RemoveDate();
}
