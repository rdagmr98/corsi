import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
import '../../models/reference_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/course_service.dart';
import '../../services/reference_service.dart';
import '../../services/schedule_service.dart';
import '../../theme.dart';
import '../../widgets/mobile_ui.dart';

class AttendeeAttendanceScreen extends ConsumerStatefulWidget {
  final String userId;
  const AttendeeAttendanceScreen({super.key, required this.userId});

  @override
  ConsumerState<AttendeeAttendanceScreen> createState() => _AttendeeAttendanceScreenState();
}

class _AttendeeAttendanceScreenState extends ConsumerState<AttendeeAttendanceScreen> {
  final _courseService     = CourseService();
  final _scheduleService   = ScheduleService();
  final _attendanceService = AttendanceService();
  final _refService        = ReferenceService();

  List<Course> _courses = [];
  Course? _selected;
  String? _filterMode = 'to_recover'; // null=tutti, 'present','absent','recovery','to_recover'

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _courses = _courseService.getCoursesForAttendee(widget.userId);
      if (_selected == null && _courses.isNotEmpty) _selected = _courses.first;
    });
  }

  Future<void> _reload() async {
    await ref.read(authProvider).reloadDb();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_courses.isEmpty) {
      return const EmptyState(Icons.school_outlined, 'Nessun corso attivo');
    }

    final course = _selected;
    if (course == null) return const SizedBox();

    final lessons   = _scheduleService.getLessonsForCourse(course.id);
    final records   = _attendanceService.getRecordsForAttendee(course.id, widget.userId);
    final recordMap = {for (final r in records) r.scheduleId: r};
    final typeInfo  = _refService.getEffectiveCourseType(course.courseTypeId, course.extensionTypeId, course.mamlCombinationId);

    String normCode(String code) => ScheduleService.normalizeSubCode(code);

    final subNames = <String, String>{
      for (final m in typeInfo?.modules ?? [])
        for (final s in m.submodules) s.code: s.name,
    };
    final subConfT  = <String, int>{};
    final subConfP  = <String, int>{};
    final subSchedT = <String, int>{};
    final subSchedP = <String, int>{};
    for (final l in lessons) {
      if (l.timeSlot == 0) continue;
      final nc = normCode(l.submoduleCode);
      if (l.type != 'pratica') {
        subSchedT[nc] = (subSchedT[nc] ?? 0) + 1;
        if (l.confirmed) subConfT[nc] = (subConfT[nc] ?? 0) + 1;
      } else {
        subSchedP[nc] = (subSchedP[nc] ?? 0) + 1;
        if (l.confirmed) subConfP[nc] = (subConfP[nc] ?? 0) + 1;
      }
    }
    final subPlanT = <String, int>{
      for (final m in typeInfo?.modules ?? [])
        for (final s in m.submodules)
          s.code: s.theoryHours > 0 ? s.theoryHours : (subSchedT[s.code] ?? 0),
    };
    final subPlanP = <String, int>{
      for (final m in typeInfo?.modules ?? [])
        for (final s in m.submodules)
          s.code: s.practicalHours > 0 ? s.practicalHours : (subSchedP[s.code] ?? 0),
    };

    final modStats = _attendanceService.computePerModuleStats(
      course.id, widget.userId, lessons, modules: typeInfo?.modules);

    // Global totals
    final totalConfirmed = modStats.values.fold(0, (s, m) => s + (m['confirmed'] ?? 0));
    final totalAbsent    = modStats.values.fold(0, (s, m) => s + (m['absent'] ?? 0));
    final totalRecovered = modStats.values.fold(0, (s, m) => s + (m['recovered'] ?? 0));
    final totalPlanned   = typeInfo?.modules.fold<int>(0, (s, m) => s + m.totalHours) ?? totalConfirmed;
    // Ore totali ancora da recuperare: pratica 100% + teoria oltre il 10%.
    final totalToRecover  = modStats.values.fold(0, (s, m) => s + (m['toRecover'] ?? 0));
    final totalToRecoverT = modStats.values.fold(0, (s, m) => s + (m['toRecoverT'] ?? 0));
    final totalToRecoverP = modStats.values.fold(0, (s, m) => s + (m['toRecoverP'] ?? 0));
    final anyWarn         = totalToRecover > 0;
    final completionPct   = totalPlanned > 0
        ? (totalConfirmed.clamp(0, totalPlanned) / totalPlanned)
        : 0.0;

    final modNames = <int, String>{
      for (final m in typeInfo?.modules ?? <ModuleInfo>[]) m.number: m.name,
    };

    // Recovery window: ore ancora da recuperare per modulo (solo quelle >0).
    final recoveryWindow = <int, int>{};
    for (final e in modStats.entries) {
      final toRec = e.value['toRecover'] ?? 0;
      if (toRec > 0) recoveryWindow[e.key] = toRec;
    }

    // Recovery records (synthetic schedule IDs)
    final recoveryRecords = records.where((r) => r.justification == 'recupero').toList()
      ..sort((a, b) {
        final da = a.recoveryDate;
        final db = b.recoveryDate;
        if (da == null || db == null) return 0;
        return db.compareTo(da);
      });
    final recoveryLessonByRec = _attendanceService.pairRecoveriesToAbsenceLessons(
        course.id, widget.userId, lessons);

    // Per ogni assenza, la data del recupero che la "copre" (pool FIFO per modulo+tipo).
    final recoveryPairing =
        _attendanceService.pairAbsenceRecoveries(course.id, widget.userId, lessons);

    // Assenze che richiedono ancora un recupero ora (pratica 100%, teoria solo
    // oltre la soglia 10% del modulo) — stessa logica per-riga del riepilogo
    // per modulo, così il filtro "Da recuperare" non mostra assenze già
    // tollerate entro soglia.
    final needsRecoveryNow = <String>{};
    for (final modNum in {for (final l in lessons) l.moduleNumber}) {
      final details = _attendanceService.absenceDetailsForModule(
          course.id, widget.userId, lessons, modNum, modules: typeInfo?.modules);
      for (final d in details) {
        if (d.needsRecovery) needsRecoveryNow.add(d.lesson.id);
      }
    }

    // Filtered lesson list for tabs (exclude timeSlot==0 and recovery schedule IDs)
    bool isPresent(l) {
      final r = recordMap[l.id];
      if (r == null) return l.confirmed;
      return r.present && r.justification != 'recupero';
    }
    bool isAbsent(l) {
      final r = recordMap[l.id];
      return r != null && !r.present;
    }

    final visibleLessons = lessons.where((l) {
      if (l.timeSlot == 0) return false;
      if (_filterMode == 'present')    return isPresent(l);
      if (_filterMode == 'absent')     return isAbsent(l);
      if (_filterMode == 'to_recover') return needsRecoveryNow.contains(l.id);
      return true;
    }).toList();

    final complColor = completionPct >= 0.75 ? kAccent : kWarning;

    return RefreshIndicator(
      onRefresh: _reload,
      color: kAttendeeAccent,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_courses.length > 1) ...[
                    CourseSelector(
                      courses: _courses,
                      selectedId: _selected?.id,
                      onSelected: (c) => setState(() {
                        _selected = c;
                        _filterMode = 'to_recover';
                      }),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Global summary card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: mobileCard(tint: anyWarn ? kError : kAccent),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text('${(completionPct * 100).toStringAsFixed(0)}%',
                                style: TextStyle(
                                    color: complColor, fontSize: 32, fontWeight: FontWeight.w800)),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('Completamento',
                                  style: TextStyle(color: kTextSoft, fontSize: 14)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: completionPct,
                          backgroundColor: kSurface,
                          color: complColor,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _stat('$totalConfirmed', 'Lezioni', kText)),
                            Expanded(child: _stat('$totalAbsent', 'Assenze', totalAbsent > 0 ? kError : kAccent)),
                            Expanded(child: _stat('$totalRecovered', 'Recuperate', kPrimary)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Recovery window alert
                  if (recoveryWindow.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    // Titolo sempre visibile; regola e dettaglio per modulo al tocco.
                    Material(
                      color: kError.withValues(alpha: 0.08),
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: kError.withValues(alpha: 0.4)),
                      ),
                      child: ExpansionTile(
                        shape: const Border(),
                        collapsedShape: const Border(),
                        iconColor: kError,
                        collapsedIconColor: kError,
                        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        title: Row(children: [
                          const Icon(Icons.warning_amber, color: kError, size: 18),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                                'Ore da recuperare: ${totalToRecover}h'
                                '${totalToRecoverP > 0 ? ' · ${totalToRecoverP}h pratica' : ''}'
                                '${totalToRecoverT > 0 ? ' · ${totalToRecoverT}h teoria' : ''}',
                                style: const TextStyle(color: kError, fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                        children: [
                          const Text(
                              'Pratica: 100% delle assenze · Teoria: solo le ore oltre il 10%',
                              style: TextStyle(color: kTextSoft, fontSize: 12)),
                          const SizedBox(height: 4),
                          ...recoveryWindow.entries.map((e) {
                            final tT = modStats[e.key]?['toRecoverT'] ?? 0;
                            final tP = modStats[e.key]?['toRecoverP'] ?? 0;
                            final parts = [
                              if (tP > 0) '${tP}h pratica',
                              if (tT > 0) '${tT}h teoria',
                            ].join(' + ');
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '• M${_refService.moduleLabel(e.key)}: ${e.value}h da recuperare ($parts)',
                                style: const TextStyle(color: kError, fontSize: 13),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],

                  // Per-module stats
                  if (modStats.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    const SectionTitle('Dettaglio per modulo'),
                    ..._buildModuleRows(modStats, modNames, {
                      for (final m in typeInfo?.modules ?? []) m.number: m.totalHours,
                    }),
                  ],

                  const SizedBox(height: 4),
                  const SectionTitle('Registro lezioni'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _filterChip('Da recuperare', 'to_recover'),
                      _filterChip('Tutte', null),
                      _filterChip('Presenze', 'present'),
                      _filterChip('Assenze', 'absent'),
                      if (totalRecovered > 0) _filterChip('Recuperi', 'recovery'),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // Lesson / recovery list
          if (_filterMode == 'recovery')
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: recoveryRecords.isEmpty
                  ? const SliverToBoxAdapter(
                      child: EmptyState(Icons.replay, 'Nessun recupero registrato'))
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final r = recoveryRecords[i];
                          final date = r.recoveryDate;
                          final modNum = r.recoveredModule;
                          final sub = r.recoveredSubmodule;
                          final typLabel = r.recoveredType == 'pratica'
                              ? 'Pratica'
                              : (r.recoveredType == 'teoria' ? 'Teoria' : '');
                          final isPratica = (r.recoveredType ?? 'pratica') == 'pratica';
                          final taskLabel = isPratica
                              ? _refService.taskLabelFor(
                                  typeInfo, recoveryLessonByRec[r.id]?.taskId)
                              : null;
                          return _row(
                            icon: Icons.replay,
                            color: kPrimary,
                            title: modNum != null
                                ? 'Recupero M${_refService.moduleLabel(modNum)}'
                                    '${sub != null ? ' $sub' : ''}'
                                    '${typLabel.isNotEmpty ? ' ($typLabel)' : ''}'
                                    '${taskLabel != null ? ' · $taskLabel' : ''}'
                                    ' – ${modNames[modNum] ?? ''}'
                                : 'Recupero',
                            subtitle: date != null ? DateFormat('dd/MM/yyyy').format(date) : null,
                            status: 'Recuperata',
                          );
                        },
                        childCount: recoveryRecords.length,
                      ),
                    ),
            )
          else if (visibleLessons.isEmpty)
            SliverToBoxAdapter(
              child: _filterMode == 'to_recover'
                  ? const EmptyState(Icons.check_circle_outline, 'Nessuna lezione da recuperare',
                      color: kAccent)
                  : const EmptyState(Icons.event_note, 'Nessuna lezione'),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final l = visibleLessons[i];
                    final r         = recordMap[l.id];
                    final isRecovery  = r?.justification == 'recupero';
                    final isPresent   = r?.present ?? false;
                    final isJustified = r != null && r.justification != null && r.justification != 'recupero';

                    final isTheory = l.type != 'pratica';
                    final nc = normCode(l.submoduleCode);
                    final rawConf = isTheory ? (subConfT[nc] ?? 0) : (subConfP[nc] ?? 0);
                    final plan = isTheory ? (subPlanT[nc] ?? 0) : (subPlanP[nc] ?? 0);
                    // Ore oltre il piano = recuperi: il contatore non supera il piano.
                    final conf = plan > 0 && rawConf > plan ? plan : rawConf;
                    final typeLabel = isTheory ? 'T' : 'P';
                    final hoursStr = plan > 0 ? '· $typeLabel $conf/$plan h' : '· $typeLabel ${conf}h';

                    String displayTopic = l.topic;
                    if (RegExp(r'^\d').hasMatch(l.topic) && l.topic.contains('.')) {
                      displayTopic = subNames[normCode(l.topic)] ?? subNames[nc] ?? l.topic;
                    }
                    final taskLabel = !isTheory
                        ? _refService.taskLabelFor(typeInfo, l.taskId)
                        : null;

                    final recoveredOn = recoveryPairing[l.id];
                    Color statusColor;
                    IconData statusIcon;
                    String statusText;
                    if (r == null && l.confirmed) {
                      statusColor = kAccent;
                      statusIcon  = Icons.check_circle;
                      statusText  = 'Presente';
                    } else if (r == null) {
                      statusColor = kTextSoft;
                      statusIcon  = Icons.schedule;
                      statusText  = 'Non registrata';
                    } else if (isRecovery) {
                      statusColor = kPrimary;
                      statusIcon  = Icons.replay;
                      statusText  = 'Recuperata (M${_refService.moduleLabel(r.recoveredModule ?? l.moduleNumber)})';
                    } else if (isPresent) {
                      statusColor = kAccent;
                      statusIcon  = Icons.check_circle;
                      statusText  = 'Presente';
                    } else if (recoveredOn != null) {
                      statusColor = kPrimary;
                      statusIcon  = Icons.replay;
                      statusText  = 'Recuperata il ${DateFormat('dd/MM/yyyy').format(recoveredOn)}';
                    } else if (isJustified) {
                      statusColor = kWarning;
                      statusIcon  = Icons.warning_amber;
                      statusText  = 'Giustificata';
                    } else {
                      statusColor = kError;
                      statusIcon  = Icons.cancel;
                      statusText  = 'Assente';
                    }

                    return _row(
                      icon: statusIcon,
                      color: statusColor,
                      title: 'M${_refService.moduleLabel(l.moduleNumber)} $displayTopic'
                          '${taskLabel != null ? ' · $taskLabel' : ''}',
                      subtitle: '${DateFormat('dd/MM/yyyy').format(l.date)} $hoursStr',
                      status: statusText,
                    );
                  },
                  childCount: visibleLessons.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    required String status,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: mobileCard(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: kText, fontSize: 14, fontWeight: FontWeight.w500)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: kTextSoft, fontSize: 12)),
                  ],
                  const SizedBox(height: 6),
                  Pill(status, color),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _filterChip(String label, String? mode) {
    final active = _filterMode == mode;
    return FilterChip(
      label: Text(label),
      selected: active,
      showCheckmark: false,
      onSelected: (_) => setState(() => _filterMode = mode),
      selectedColor: kAttendeeAccent.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: active ? kAttendeeAccent : kTextSoft,
        fontSize: 13,
        fontWeight: active ? FontWeight.w600 : FontWeight.normal,
      ),
      backgroundColor: kCard,
      shape: const StadiumBorder(),
      side: BorderSide(color: active ? kAttendeeAccent : kLine),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  List<Widget> _buildModuleRows(
    Map<int, Map<String, int>> modStats,
    Map<int, String> modNames,
    Map<int, int> modPlanHours,
  ) {
    final entries = modStats.entries
        .where((e) => (e.value['confirmed'] ?? 0) > 0)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return entries.map((e) {
      final mod   = e.key;
      final st    = e.value;
      final conf  = st['confirmed'] ?? 0;
      final absent = st['absent'] ?? 0;
      final rec   = st['recovered'] ?? 0;
      final unrec = st['unrecovered'] ?? 0;
      final plan  = modPlanHours[mod] ?? conf;
      final pct   = plan > 0 ? (plan - unrec) / plan : 1.0;
      final toRec  = st['toRecover'] ?? 0;
      final toRecT = st['toRecoverT'] ?? 0;
      final toRecP = st['toRecoverP'] ?? 0;
      final warn  = toRec > 0;
      final color = warn ? kError : (pct >= 0.90 ? kAccent : kWarning);
      final presPct = plan > 0
          ? ((plan - absent) / plan * 100).toStringAsFixed(0)
          : '100';
      final absPct =
          plan > 0 ? (absent / plan * 100).toStringAsFixed(0) : '0';
      // Dettaglio teoria/pratica: assenze, quante recuperate, quante ancora da recuperare
      final absentT = st['absentT'] ?? 0;
      final absentP = st['absentP'] ?? 0;
      final recT    = st['recoveredT'] ?? 0;
      final recP    = st['recoveredP'] ?? 0;
      String typeDetail(String lbl, int a, int r, int u) {
        if (a == 0 && r == 0) return '';
        final buf = StringBuffer('$lbl: $a ass.');
        if (r > 0) buf.write(' · $r recuperate');
        if (u > 0) buf.write(' · $u da recuperare');
        return buf.toString();
      }
      final breakdown = [
        typeDetail('Teoria', absentT, recT, toRecT),
        typeDetail('Pratica', absentP, recP, toRecP),
      ].where((s) => s.isNotEmpty).join('\n');
      final hasActivity = absent > 0 || rec > 0;

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: kCard,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: warn ? kError.withValues(alpha: 0.45) : kLine),
          ),
          // Riga pulita (modulo + nome + %); statistiche dettagliate al tocco.
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            iconColor: kTextSoft,
            collapsedIconColor: kTextSoft,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Row(
              children: [
                Pill('M${_refService.moduleLabel(mod)}', moduleColor(mod)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(modNames[mod] ?? '',
                      style: const TextStyle(color: kText, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(pct * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                      color: color, fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            children: [
              Text(
                !hasActivity
                    ? 'Pres. 100% · Ass. 0% — nessuna assenza su $plan ore prev.'
                    : 'Pres. $presPct% · Ass. $absPct% — $absent ass. · $rec rec. · $unrec non rec. / $plan ore prev.',
                style: TextStyle(color: warn ? kError : kTextSoft, fontSize: 12),
              ),
              if (breakdown.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    breakdown,
                    style: TextStyle(color: warn ? kError : kTextSoft, fontSize: 12),
                  ),
                ),
              if (warn)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      'DA RECUPERARE: ${toRec}h'
                      '${toRecP > 0 ? ' · ${toRecP}h pratica' : ''}'
                      '${toRecT > 0 ? ' · ${toRecT}h teoria' : ''}',
                      style: const TextStyle(
                          color: kError, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _stat(String value, String label, Color color) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w700)),
      Text(label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: kTextSoft, fontSize: 12)),
    ],
  );
}
