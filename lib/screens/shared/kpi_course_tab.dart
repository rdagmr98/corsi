import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/kpi_service.dart';
import '../../theme.dart';

/// Vista dati corso per compilare KPI MTOE-A-2-1 (a–d).
/// Usata da admin (tutti i corsi) e direttore (corsi assegnati).
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
  List<Course> _courses = [];
  Course? _selected;
  KpiCourseSnapshot? _snap;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
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
      _snap = _selected == null ? null : _kpi.snapshot(_selected!);
    });
  }

  Future<void> _reload() async {
    await ref.read(authProvider).reloadDb();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy');
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
              _snap = _kpi.snapshot(_selected!);
            }),
          ),
          const Spacer(),
          IconButton(
              icon: const Icon(Icons.refresh, color: kTextDim),
              onPressed: _reload),
        ]),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'Dati aggregati per compilare MTOE-A-2-1 (a–d). '
          'Non genera il Word: mostra i numeri da trascrivere.',
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
                'KPI (a) — Scostamento temporale',
                [
                  _kv('Lezioni pianificate', '${snap.plannedLessons}'),
                  _kv('Lezioni svolte (confermate)', '${snap.confirmedLessons}'),
                  _kv(
                      'Ultima svolta',
                      snap.lastConfirmedDate == null
                          ? '—'
                          : fmt.format(snap.lastConfirmedDate!)),
                  _kv(
                      'Ultima pianificata',
                      snap.lastPlannedDate == null
                          ? '—'
                          : fmt.format(snap.lastPlannedDate!)),
                  _kv(
                      'Scostamento (gg)',
                      snap.temporalDeviationDays?.toString() ?? 'n/d'),
                  _kv('Fascia KPI', snap.temporalBand),
                  _kv('Metodo', snap.temporalMethod),
                ],
              ),
              _card(
                'KPI (b) — Questionario qualità percepita',
                [
                  _kv(
                      'Dato in app',
                      snap.hasQuestionnaires
                          ? 'Disponibile'
                          : 'NON DISPONIBILE — gap: questionari non gestiti'),
                ],
                warn: !snap.hasQuestionnaires,
              ),
              _card(
                'KPI (c) — Media delle valutazioni',
                [
                  _kv('N. voti (accertamenti + esami)',
                      '${snap.gradedAttempts}'),
                  _kv(
                      'Media aritmetica',
                      snap.averageScore == null
                          ? '—'
                          : snap.averageScore!.toStringAsFixed(2)),
                  _kv('Fascia KPI', snap.averageBand),
                  const Text(
                    'Nota: media su tutti i voti registrati (come da testo KPI). '
                    'La graduatoria corso usa invece medie pesate per modulo.',
                    style: TextStyle(color: kTextDim, fontSize: 11),
                  ),
                ],
              ),
              _card(
                'KPI (d) — Tasso di incidenza insufficienze (esami modulo)',
                [
                  if (snap.failRates.isEmpty)
                    const Text('Nessun esame di modulo registrato',
                        style: TextStyle(color: kTextDim, fontSize: 12))
                  else
                    ...snap.failRates.map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            SizedBox(
                              width: 56,
                              child: Text(r.label,
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

  Widget _card(String title, List<Widget> children, {bool warn = false}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: warn ? kWarning.withOpacity(0.5) : kBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    color: warn ? kWarning : kText,
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
                  style: const TextStyle(color: kTextDim, fontSize: 12)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(color: kText, fontSize: 12)),
            ),
          ],
        ),
      );
}
