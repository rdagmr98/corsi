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

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _instructors = _userService.getInstructors()
        ..sort((a, b) => a.cognome.compareTo(b.cognome));
    });
  }

  Future<void> _reload() async {
    await ref.read(authProvider).reloadDb();
    _load();
  }

  // ── AMC helpers ───────────────────────────────────────────────────────────
  List<String> _theoryMods(String uid) => List<String>.from(
      (_db.amcData['instructorAmc'] as Map? ?? {})[uid]
          ?['theory_submodules'] as List? ?? []);

  List<String> _practiceMods(String uid) => List<String>.from(
      (_db.amcData['instructorAmc'] as Map? ?? {})[uid]
          ?['practice_submodules'] as List? ?? []);

  // ── Ore insegnamento per anno (rolling) ───────────────────────────────────
  List<Map<String, dynamic>> _teachingByYear(String uid) {
    final byYear = <int, double>{};
    for (final u in _db.updates
        .where((u) => u['instructor_id'] == uid && u['type'] == 'teaching')) {
      final yr = DateTime.tryParse(u['date'] as String? ?? '')?.year ?? 0;
      byYear[yr] = (byYear[yr] ?? 0) + ((u['hours'] as num?)?.toDouble() ?? 0);
    }
    return byYear.entries
        .map((e) => {'year': e.key, 'hours': e.value})
        .toList()
      ..sort((a, b) => (b['year'] as int).compareTo(a['year'] as int));
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
    final goProf   = profH >= 35;
    final go       = goTeach && goProf;

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
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        child: Row(children: [
          Text('Idoneità Istruttori (${_instructors.length})',
              style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          IconButton(
              icon: const Icon(Icons.refresh, color: kTextDim),
              onPressed: _reload),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: const Text(
          'GO se: ≥6h insegnamento (ultimi 365 giorni) E ≥35h aggiornamento professionale (ultimi 2 anni)',
          style: TextStyle(color: kTextDim, fontSize: 11),
        ),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          itemCount: _instructors.length,
          itemBuilder: (_, i) {
            final instr  = _instructors[i];
            final teachH = _gradeService.getTeachingHoursRollingYear(instr.id);
            final profH  = _gradeService.getProfessionalUpdateHoursLast2Years(instr.id);
            final tMods  = _theoryMods(instr.id);
            final pMods  = _practiceMods(instr.id);
            final goT    = instr.goOverride || teachH >= 6;
            final goP    = profH >= 35;
            final go     = goT && goP;

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
                      child: Row(children: [
                        _chip('T: ${tMods.length}', kPrimary),
                        const SizedBox(width: 4),
                        _chip('P: ${pMods.length}', kAccent),
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
        ),
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
}
