import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
import '../../models/user_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/kpi_service.dart';
import '../../theme.dart';

/// Vista KPI corso: media voti + % insufficienze esami modulo.
/// Periodo filtrabile (da–a) + selezione frequentatori. Admin e direttore.
class KpiCourseTab extends ConsumerStatefulWidget {
  final String? directorUserId;
  final bool showAllCourses;

  const KpiCourseTab({
    super.key,
    this.directorUserId,
    this.showAllCourses = false,
  });

  @override
  ConsumerState<KpiCourseTab> createState() => _KpiCourseTabState();
}

class _KpiCourseTabState extends ConsumerState<KpiCourseTab> {
  final _kpi = KpiService();
  final _fmt = DateFormat('dd/MM/yyyy');
  List<Course> _courses = [];
  List<AppUser> _attendees = [];
  /// null = tutti i frequentatori; altrimenti sottoinsieme selezionato.
  Set<String>? _attendeeFilter;
  Course? _selected;
  KpiCourseSnapshot? _snap;
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _load(recalc: true);
  }

  void _load({bool recalc = false}) {
    setState(() {
      _courses = _kpi.coursesForUser(
        directorId: widget.showAllCourses ? null : widget.directorUserId,
        allIfAdmin: widget.showAllCourses,
      );
      if (_selected == null && _courses.isNotEmpty) {
        _selected = _courses.first;
      } else if (_selected != null) {
        _selected = _courses.where((c) => c.id == _selected!.id).firstOrNull ??
            (_courses.isNotEmpty ? _courses.first : null);
      }
      _syncAttendees();
      if (recalc) _recalc();
    });
  }

  void _syncAttendees() {
    _attendees =
        _selected == null ? [] : _kpi.attendeesForCourse(_selected!);
    final ids = _attendees.map((u) => u.id).toSet();
    if (_attendeeFilter != null) {
      _attendeeFilter = _attendeeFilter!.intersection(ids);
      if (_attendeeFilter!.isEmpty ||
          _attendeeFilter!.length == ids.length) {
        _attendeeFilter = null;
      }
    }
  }

  void _recalc() {
    _snap = _selected == null
        ? null
        : _kpi.snapshot(
            _selected!,
            from: _from,
            to: _to,
            attendeeIds: _attendeeFilter,
          );
  }

  Future<void> _reload() async {
    await ref.read(authProvider).reloadDb();
    _load(recalc: true);
  }

  Future<void> _pickFrom() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _from ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (d != null) setState(() => _from = d);
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _to ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (d != null) setState(() => _to = d);
  }

  String get _attendeeFilterLabel {
    if (_attendeeFilter == null) return 'Tutti i frequentatori';
    final n = _attendeeFilter!.length;
    return '$n / ${_attendees.length} frequentatori';
  }

  Future<void> _pickAttendees() async {
    if (_attendees.isEmpty) return;
    final draft = Set<String>.from(
        _attendeeFilter ?? _attendees.map((u) => u.id));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: kSurface,
          title: const Text('Frequentatori KPI',
              style: TextStyle(color: kText)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  TextButton(
                    onPressed: () => setLocal(
                        () => draft.addAll(_attendees.map((u) => u.id))),
                    child: const Text('Tutti'),
                  ),
                  TextButton(
                    onPressed: () => setLocal(draft.clear),
                    child: const Text('Nessuno'),
                  ),
                ]),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView(
                    shrinkWrap: true,
                    children: _attendees
                        .map((u) => CheckboxListTile(
                              dense: true,
                              value: draft.contains(u.id),
                              activeColor: kAccent,
                              title: Text(u.fullName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: kText, fontSize: 13)),
                              onChanged: (v) => setLocal(() {
                                if (v == true) {
                                  draft.add(u.id);
                                } else {
                                  draft.remove(u.id);
                                }
                              }),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annulla')),
            TextButton(
                onPressed: draft.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: const Text('Applica')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      _attendeeFilter =
          draft.length == _attendees.length ? null : Set.from(draft);
      _recalc();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_courses.isEmpty) {
      return const Center(
          child: Text('Nessun corso disponibile',
              style: TextStyle(color: kTextDim)));
    }
    final snap = _snap;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        child: Row(children: [
          Text('KPI corso', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 16),
          DropdownButton<String>(
            value: _selected?.id,
            dropdownColor: kSurface,
            style: const TextStyle(color: kText),
            underline: const SizedBox(),
            items: _courses
                .map((c) => DropdownMenuItem(value: c.id, child: Text(c.title)))
                .toList(),
            onChanged: (id) => setState(() {
              _selected = _courses.firstWhere((c) => c.id == id);
              _attendeeFilter = null;
              _syncAttendees();
              _recalc();
            }),
          ),
          const Spacer(),
          IconButton(
              icon: const Icon(Icons.refresh, color: kTextDim),
              onPressed: _reload),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Periodo:',
                style: TextStyle(color: kTextDim, fontSize: 12)),
            _chip(
              label: _from == null ? 'Da data' : 'Da ${_fmt.format(_from!)}',
              selected: _from != null,
              onTap: _pickFrom,
            ),
            _chip(
              label: _to == null ? 'A data' : 'A ${_fmt.format(_to!)}',
              selected: _to != null,
              onTap: _pickTo,
            ),
            _chip(
              label: _attendeeFilterLabel,
              selected: _attendeeFilter != null,
              onTap: _pickAttendees,
            ),
            TextButton.icon(
              onPressed: () => setState(_recalc),
              icon: const Icon(Icons.calculate, size: 18),
              label: const Text('Ricalcola'),
            ),
            if (_from != null || _to != null || _attendeeFilter != null)
              TextButton(
                onPressed: () => setState(() {
                  _from = null;
                  _to = null;
                  _attendeeFilter = null;
                  _recalc();
                }),
                child: const Text('Reset filtri'),
              ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'Media KPI: stesso peso accertamenti/esami su tutti i tentativi '
          'nel periodo (anche fail recuperati). Filtra periodo e '
          'frequentatori, poi premi Ricalcola.',
          style: TextStyle(color: kTextDim, fontSize: 12),
        ),
      ),
      const SizedBox(height: 12),
      if (snap == null)
        const Expanded(child: SizedBox())
      else
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              _card(
                'Media delle valutazioni',
                [
                  if (snap.periodFrom != null || snap.periodTo != null)
                    _kv(
                      'Periodo',
                      '${snap.periodFrom == null ? '…' : _fmt.format(snap.periodFrom!)}'
                      ' → '
                      '${snap.periodTo == null ? '…' : _fmt.format(snap.periodTo!)}',
                    ),
                  _kv('Voti nel periodo', '${snap.gradedAttempts}'),
                  _kv(
                      'Media semplice (stesso peso)',
                      snap.averageScore == null
                          ? '—'
                          : snap.averageScore!.toStringAsFixed(2)),
                  _kv('Fascia', snap.averageBand),
                  const SizedBox(height: 6),
                  const Text(
                    'Media aritmetica di tutti i tentativi nel periodo '
                    '(accertamenti ed esami stesso peso; fail recuperati '
                    'inclusi). Diversa dalla graduatoria (pesi 1 e 2).',
                    style: TextStyle(color: kTextDim, fontSize: 11, height: 1.35),
                  ),
                ],
              ),
              _card(
                'Tasso di insufficienze (esami modulo)',
                [
                  if (snap.failRates.isEmpty)
                    const Text('Nessun esame di modulo nel periodo',
                        style: TextStyle(color: kTextDim, fontSize: 12))
                  else
                    ...snap.failRates.map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 48,
                                child: Text(r.label,
                                    style: const TextStyle(
                                        color: kText,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                              ),
                              Expanded(
                                child: Text(
                                  '${r.failures} insufficienze su ${r.examAttempts} '
                                  'tentativi (${r.failPercent.toStringAsFixed(1)}%)\n'
                                  '${r.band}',
                                  style: const TextStyle(
                                      color: kTextDim,
                                      fontSize: 12,
                                      height: 1.35),
                                ),
                              ),
                            ],
                          ),
                        )),
                  if (snap.failRates.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Ogni tentativo d\'esame conta: un insufficiente poi '
                      'recuperato resta nel tasso.',
                      style: TextStyle(
                          color: kTextDim, fontSize: 11, height: 1.35),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
    ]);
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      ActionChip(
        label: Text(label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: selected ? kText : kTextDim, fontSize: 12)),
        backgroundColor: selected ? kCard : kSurface,
        side: BorderSide(color: selected ? kAccent : kBorder),
        onPressed: onTap,
      );

  Widget _card(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: kText,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    letterSpacing: 0.2)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              flex: 3,
              child: Text(k,
                  softWrap: true,
                  style: const TextStyle(color: kTextDim, fontSize: 12)),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Text(v,
                  textAlign: TextAlign.end,
                  softWrap: true,
                  style: const TextStyle(
                      color: kText,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
}
