import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/kpi_service.dart';
import '../../theme.dart';

/// Vista KPI corso: media voti + % insufficienze esami modulo.
/// Periodo filtrabile (da–a). Admin (tutti i corsi) e direttore (assegnati).
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
      if (recalc) _recalc();
    });
  }

  void _recalc() {
    _snap = _selected == null
        ? null
        : _kpi.snapshot(_selected!, from: _from, to: _to);
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
            TextButton.icon(
              onPressed: () => setState(_recalc),
              icon: const Icon(Icons.calculate, size: 18),
              label: const Text('Ricalcola'),
            ),
            if (_from != null || _to != null)
              TextButton(
                onPressed: () => setState(() {
                  _from = null;
                  _to = null;
                  _recalc();
                }),
                child: const Text('Tutto il corso'),
              ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'Media aritmetica voti e % insufficienze esami modulo. '
          'Scegli un periodo e premi Ricalcola (senza date = tutto il corso).',
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
                  _kv('N. voti (accertamenti + esami)',
                      '${snap.gradedAttempts}'),
                  _kv(
                      'Media aritmetica',
                      snap.averageScore == null
                          ? '—'
                          : snap.averageScore!.toStringAsFixed(2)),
                  _kv('Fascia', snap.averageBand),
                  const Text(
                    'Nota: media su tutti i voti nel periodo. '
                    'La graduatoria corso usa medie pesate per modulo.',
                    style: TextStyle(color: kTextDim, fontSize: 11),
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
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            SizedBox(
                              width: 56,
                              child: Text(r.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: kText,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ),
                            Expanded(
                              child: Text(
                                '${r.failures}/${r.examAttempts} insuff. '
                                '(${r.failPercent.toStringAsFixed(1)}%) — ${r.band}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: kTextDim, fontSize: 12),
                              ),
                            ),
                          ]),
                        )),
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
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: kText,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 200,
              child: Text(k,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kTextDim, fontSize: 12)),
            ),
            Expanded(
              child: Text(v,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kText, fontSize: 12)),
            ),
          ],
        ),
      );
}
