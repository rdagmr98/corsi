import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
import '../../models/grade_models.dart';
import '../../models/schedule_models.dart';
import '../../models/user_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/grade_service.dart';
import '../../services/reference_service.dart';
import '../../services/schedule_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';

class MasterCourseDetailScreen extends ConsumerStatefulWidget {
  final Course course;
  const MasterCourseDetailScreen({super.key, required this.course});

  @override
  ConsumerState<MasterCourseDetailScreen> createState() => _State();
}

class _State extends ConsumerState<MasterCourseDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _scheduleService = ScheduleService();
  final _attendanceService = AttendanceService();
  final _gradeService = GradeService();
  final _refService = ReferenceService();
  final _userService = UserService();

  late Course _course;
  late List<ScheduledLesson> _lessons;
  late List<AppUser> _attendees;
  late List<AppUser> _instructors;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _load() {
    _course = widget.course;
    _lessons = _scheduleService.getLessonsForCourse(_course.id);
    final allUsers = _userService.getAllUsers();
    _attendees = allUsers.where((u) => _course.attendeeIds.contains(u.id)).toList()
      ..sort((a, b) => a.cognome.compareTo(b.cognome));
    _instructors = allUsers.where((u) => _course.instructorIds.contains(u.id)).toList()
      ..sort((a, b) => a.cognome.compareTo(b.cognome));
  }

  Future<void> _reload() async {
    await ref.read(authProvider).reloadDb();
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    final typeInfo = _refService.getEffectiveCourseType(_course.courseTypeId, _course.extensionTypeId);
    final confirmedLessons = _lessons.where((l) => l.confirmed && l.timeSlot > 0).toList();

    return Dialog(
      backgroundColor: kBg,
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1100,
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: Column(children: [
          // Header
          Container(
            color: kSurface,
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
            child: Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_course.title,
                      style: const TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(
                    '${typeInfo?.name ?? ''} · ${_attendees.length} freq. · ${_instructors.length} istr. · ${confirmedLessons.length} lezioni svolte',
                    style: const TextStyle(color: kTextDim, fontSize: 12),
                  ),
                ],
              )),
              IconButton(icon: const Icon(Icons.refresh, color: kTextDim), onPressed: _reload),
              IconButton(icon: const Icon(Icons.close, color: kTextDim),
                  onPressed: () => Navigator.pop(context)),
            ]),
          ),
          TabBar(
            controller: _tabController,
            indicatorColor: kPrimary,
            labelColor: kPrimary,
            unselectedLabelColor: kTextDim,
            tabs: const [
              Tab(text: 'Riepilogo'),
              Tab(text: 'Lezioni'),
              Tab(text: 'Presenze'),
              Tab(text: 'Voti'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOverview(typeInfo, confirmedLessons),
                _buildLessons(confirmedLessons),
                _buildAttendance(typeInfo),
                _buildGrades(typeInfo),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── Overview tab ──────────────────────────────────────────────────────────
  Widget _buildOverview(dynamic typeInfo, List<ScheduledLesson> confirmed) {
    final modules = typeInfo?.modules ?? [];
    final confirmedByMod = <int, int>{};
    final confirmedTByMod = <int, int>{};
    final confirmedPByMod = <int, int>{};
    for (final l in confirmed) {
      confirmedByMod[l.moduleNumber] = (confirmedByMod[l.moduleNumber] ?? 0) + 1;
      if (l.isTheory) {
        confirmedTByMod[l.moduleNumber] = (confirmedTByMod[l.moduleNumber] ?? 0) + 1;
      } else {
        confirmedPByMod[l.moduleNumber] = (confirmedPByMod[l.moduleNumber] ?? 0) + 1;
      }
    }

    // Completamento complessivo: ore confermate (cappate al monte ore di
    // ogni modulo, le eccedenze sono recuperi) su ore totali del programma.
    int totalPlanned = 0;
    int totalDone = 0;
    for (final m in modules) {
      final int t = m.totalHours;
      final raw = confirmedByMod[m.number] ?? 0;
      totalPlanned += t;
      totalDone += t > 0 && raw > t ? t : raw;
    }
    final overallPct = totalPlanned > 0 ? totalDone / totalPlanned : 0.0;

    return ListView(padding: const EdgeInsets.all(20), children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kPrimary.withOpacity(0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
              child: Text('Completamento corso',
                  style: TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            Text('${(overallPct * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                    color: overallPct >= 1 ? kAccent : kPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: overallPct.clamp(0.0, 1.0),
            color: overallPct >= 1 ? kAccent : kPrimary,
            backgroundColor: kSurface,
            minHeight: 7,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 6),
          Text('$totalDone / $totalPlanned ore confermate',
              style: const TextStyle(color: kTextDim, fontSize: 11)),
        ]),
      ),
      const SizedBox(height: 20),
      Text('Avanzamento per modulo', style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      ...modules.map((m) {
        final rawDone = confirmedByMod[m.number] ?? 0;
        final rawDoneT = confirmedTByMod[m.number] ?? 0;
        final rawDoneP = confirmedPByMod[m.number] ?? 0;
        final total = m.totalHours;
        final done = total > 0 && rawDone > total ? total : rawDone;
        final doneT = m.theoryHours > 0 && rawDoneT > m.theoryHours ? m.theoryHours : rawDoneT;
        final doneP = m.practicalHours > 0 && rawDoneP > m.practicalHours ? m.practicalHours : rawDoneP;
        final pT = total > 0 ? doneT / total : 0.0;
        final pP = total > 0 ? doneP / total : 0.0;
        final col = moduleColor(m.number);
        return GestureDetector(
          onTap: () => _showModuleDetail(context, m, doneT.toDouble(), doneP.toDouble()),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: col.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('M${m.displayCode}',
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(color: col, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(m.name, style: const TextStyle(color: kText, fontSize: 12), overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Text('$done / $total', style: TextStyle(color: done >= total ? kAccent : kTextDim, fontSize: 11)),
              ]),
              const SizedBox(height: 4),
              splitBar(pT, pP, height: 5),
            ]),
          ),
        );
      }),
    ]);
  }

  // ── Lessons tab ───────────────────────────────────────────────────────────
  Widget _buildLessons(List<ScheduledLesson> confirmed) {
    final sorted = confirmed.toList()
      ..sort((a, b) {
        final dc = a.date.compareTo(b.date);
        return dc != 0 ? dc : a.timeSlot.compareTo(b.timeSlot);
      });
    final instrMap = {for (final i in _instructors) i.id: i};
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: sorted.length,
      itemBuilder: (_, i) {
        final l = sorted[i];
        final col = moduleColor(l.moduleNumber);
        final instr = instrMap[l.instructorId];
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: col.withOpacity(0.2)),
          ),
          child: Row(children: [
            Container(
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 3),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: col.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
              child: Text('M${_refService.moduleLabel(l.moduleNumber)}', style: TextStyle(color: col, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 80, child: Text(DateFormat('dd/MM/yy').format(l.date), style: const TextStyle(color: kTextDim, fontSize: 11))),
            Container(
              width: 20,
              alignment: Alignment.center,
              child: Text(l.isTheory ? 'T' : 'P', style: TextStyle(color: col, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(l.topic, style: const TextStyle(color: kText, fontSize: 11), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Text(instr?.cognome ?? '—', style: const TextStyle(color: kTextDim, fontSize: 10)),
          ]),
        );
      },
    );
  }

  // ── Attendance tab ────────────────────────────────────────────────────────
  Widget _buildAttendance(dynamic typeInfo) {
    if (_attendees.isEmpty) {
      return const Center(child: Text('Nessun frequentatore', style: TextStyle(color: kTextDim)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: _attendees.length,
      itemBuilder: (_, i) {
        final a = _attendees[i];
        final modStats = _attendanceService.computePerModuleStats(
            _course.id, a.id, _lessons, modules: typeInfo?.modules);
        final totalAbsent = modStats.values.fold(0, (s, m) => s + (m['absent'] ?? 0));
        final totalUnrec = modStats.values.fold(0, (s, m) => s + (m['unrecovered'] ?? 0));
        final totalPlanned = typeInfo?.modules.fold<int>(0, (s, m) => s + (m.totalHours as int)) ?? 0;
        final totalConfirmed = modStats.values.fold(0, (s, m) => s + (m['confirmed'] ?? 0));
        final presPct = totalConfirmed > 0
            ? ((totalConfirmed - totalAbsent) / totalConfirmed * 100).toStringAsFixed(0)
            : '100';
        final absPct = totalConfirmed > 0
            ? (totalAbsent / totalConfirmed * 100).toStringAsFixed(0)
            : '0';
        final anyWarn = typeInfo != null && modStats.entries.any((e) {
          final tot = e.value['confirmed'] ?? 0;
          final unr = e.value['unrecovered'] ?? 0;
          return tot > 0 && unr / tot > 0.10;
        });

        return Card(
          color: kCard,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: anyWarn ? kError.withOpacity(0.35) : kBorder),
          ),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: anyWarn ? kError.withOpacity(0.15) : kPrimary.withOpacity(0.15),
              child: Text(a.cognome.isNotEmpty ? a.cognome[0].toUpperCase() : '?',
                  style: TextStyle(color: anyWarn ? kError : kPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            title: Text(a.fullName, style: const TextStyle(color: kText, fontSize: 13)),
            subtitle: Text(
              'Pres. $presPct% · Ass. $absPct% — $totalAbsent ore ass. · $totalUnrec non rec. su $totalPlanned ore prev.',
              style: TextStyle(color: anyWarn ? kError : kTextDim, fontSize: 11),
            ),
            children: typeInfo == null ? [] : typeInfo.modules
                .where((mod) => modStats.containsKey(mod.number) && (modStats[mod.number]!['confirmed'] ?? 0) > 0)
                .map((mod) {
              final stats = modStats[mod.number]!;
              final total = stats['confirmed'] ?? 0;
              final absent = stats['absent'] ?? 0;
              final recovered = stats['recovered'] ?? 0;
              final unrecovered = stats['unrecovered'] ?? 0;
              final pct = total > 0 ? unrecovered / total : 0.0;
              final warn = pct > 0.10;
              final mPresPct = total > 0
                  ? ((total - absent) / total * 100).toStringAsFixed(0)
                  : '100';
              final mAbsPct =
                  total > 0 ? (absent / total * 100).toStringAsFixed(0) : '0';
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.fromLTRB(24, 0, 8, 0),
                leading: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (warn ? kError : kPrimary).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('M${mod.displayCode}',
                      style: TextStyle(color: warn ? kError : kPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                title: Text(mod.name, style: const TextStyle(color: kText, fontSize: 12), overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  absent == 0
                      ? 'Pres. 100% · Ass. 0% — nessuna assenza su $total ore prev.'
                      : 'Pres. $mPresPct% · Ass. $mAbsPct% — $absent ass. · $recovered rec. · $unrecovered non rec. / $total ore prev.'
                          '${warn ? '  ⚠ LIMITE 10%' : ''}',
                  style: TextStyle(color: warn ? kError : kTextDim, fontSize: 11),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  // ── Grades tab ────────────────────────────────────────────────────────────
  Widget _buildGrades(dynamic typeInfo) {
    if (_attendees.isEmpty || typeInfo == null) {
      return const Center(child: Text('Nessun dato', style: TextStyle(color: kTextDim)));
    }
    final modules = (typeInfo.modules as List).where((m) {
      return _attendees.any((a) =>
          _gradeService.getGradesForAttendee(_course.id, a.id)
              .any((g) => g.moduleNumber == m.number));
    }).toList();

    if (modules.isEmpty) {
      return const Center(child: Text('Nessun voto inserito', style: TextStyle(color: kTextDim)));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Table(
          border: TableBorder.all(color: kBorder, width: 0.5),
          defaultColumnWidth: const FixedColumnWidth(70),
          columnWidths: const {0: FixedColumnWidth(160)},
          children: [
            TableRow(
              decoration: const BoxDecoration(color: kSurface),
              children: [
                _tCell('Frequentatore', bold: true),
                ...modules.map((m) => Tooltip(
                      message: 'M${m.displayCode} - ${m.name}',
                      child: _tCell('M${m.displayCode}', bold: true),
                    )),
                _tCell('Media', bold: true),
              ],
            ),
            ..._attendees.map((a) {
              final summary = _gradeService.getAttendeeSummary(_course.id, a.id);
              final grad = _gradeService.getGraduationScore(_course.id, a.id);
              return TableRow(children: [
                _tCell(a.fullName),
                ...modules.map((m) {
                  final ms = summary[m.number];
                  if (ms == null || !ms.hasGrades) return _tCell('—');
                  final avg = ms.weightedAverage;
                  return InkWell(
                    onTap: () => _moduleGradesDialog(a, m),
                    child: _tCell(avg.toStringAsFixed(1),
                        color: avg >= 22.5 ? kAccent : kError),
                  );
                }),
                _tCell(
                  grad > 0 ? grad.toStringAsFixed(1) : '—',
                  color: grad >= 22.5 ? kAccent : (grad > 0 ? kError : kTextDim),
                  bold: grad > 0,
                ),
              ]);
            }),
          ],
        ),
      ),
    );
  }

  // Dettaglio voti del modulo (sola lettura): stessa vista del direttore.
  void _moduleGradesDialog(AppUser a, dynamic module) {
    final grades = _gradeService
        .getGradesForAttendee(_course.id, a.id)
        .where((g) => g.moduleNumber == module.number)
        .toList()
      ..sort((g1, g2) => g1.date.compareTo(g2.date));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('M${module.displayCode} — ${a.fullName}',
                style: const TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.bold)),
            Text('${module.name}',
                style: const TextStyle(color: kTextDim, fontSize: 12)),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: grades.isEmpty
              ? const Text('Nessun voto', style: TextStyle(color: kTextDim))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: grades.map((g) {
                    final isEsame = g.assessmentType == AssessmentType.esame;
                    final typeColor = isEsame ? kWarning : kPrimary;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Container(
                          width: 92,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: typeColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(g.assessmentType.label,
                                maxLines: 1,
                                style: TextStyle(color: typeColor, fontSize: 10)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 44,
                          child: Text(
                            g.score.toStringAsFixed(1),
                            style: TextStyle(
                              color: g.isPassing ? kAccent : kError,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(DateFormat('dd/MM/yyyy').format(g.date),
                                  style: const TextStyle(color: kTextDim, fontSize: 11)),
                              if (g.notes != null && g.notes!.isNotEmpty)
                                Text(g.notes!,
                                    style: const TextStyle(color: kTextDim, fontSize: 10),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ]),
                    );
                  }).toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Chiudi', style: TextStyle(color: kTextDim)),
          ),
        ],
      ),
    );
  }

  void _showModuleDetail(BuildContext context, dynamic m, double doneT, double doneP) {
    final planT = (m.theoryHours as num).toDouble();
    final planP = (m.practicalHours as num).toDouble();
    final planTotal = planT + planP;
    final doneTotal = doneT + doneP;
    Widget row(String label, double done, double plan, Color color) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 56, child: Text(label, style: const TextStyle(color: kTextDim, fontSize: 13))),
        Expanded(child: Text('${done.toInt()} / ${plan.toInt()} ore',
            style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold))),
        Text(plan > 0 ? '${(done / plan * 100).round()}%' : '—',
            style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
      ]),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('M${m.displayCode}',
              style: const TextStyle(color: kPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          Text(m.name as String, style: const TextStyle(color: kTextDim, fontSize: 12)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          row('Totale', doneTotal, planTotal, kText),
          const Divider(color: kBorder, height: 16),
          row('Teoria', doneT, planT, kPrimary),
          if (planP > 0) row('Pratica', doneP, planP, kAccent),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Chiudi', style: TextStyle(color: kPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _tCell(String text, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Text(
      text,
      style: TextStyle(
        color: color ?? kText,
        fontSize: 11,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      ),
    ),
  );
}
