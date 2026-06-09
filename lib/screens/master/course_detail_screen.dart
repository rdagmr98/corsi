import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
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
    for (final l in confirmed) {
      confirmedByMod[l.moduleNumber] = (confirmedByMod[l.moduleNumber] ?? 0) + 1;
    }

    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Avanzamento per modulo', style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      ...modules.map((m) {
        final done = confirmedByMod[m.number] ?? 0;
        final total = m.totalHours;
        final pct = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
        final col = moduleColor(m.number);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 40,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: col.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('M${m.number}', style: TextStyle(color: col, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(m.name, style: const TextStyle(color: kText, fontSize: 12), overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text('$done / $total h', style: TextStyle(color: done >= total ? kAccent : kTextDim, fontSize: 11)),
            ]),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: pct,
              color: col,
              backgroundColor: kSurface,
              minHeight: 5,
              borderRadius: BorderRadius.circular(3),
            ),
          ]),
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
              child: Text('M${l.moduleNumber}', style: TextStyle(color: col, fontSize: 10, fontWeight: FontWeight.bold)),
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
              '$totalAbsent ore ass. · $totalUnrec non rec. su $totalPlanned ore prev.',
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
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.fromLTRB(24, 0, 8, 0),
                leading: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (warn ? kError : kPrimary).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('M${mod.number}',
                      style: TextStyle(color: warn ? kError : kPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                title: Text(mod.name, style: const TextStyle(color: kText, fontSize: 12), overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  absent == 0
                      ? 'Nessuna assenza su $total ore prev.'
                      : '$absent ass. · $recovered rec. · $unrecovered non rec. / $total ore prev.'
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
                ...modules.map((m) => _tCell('M${m.number}', bold: true)),
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
                  return _tCell(avg.toStringAsFixed(1),
                      color: avg >= 75 ? kAccent : (avg >= 60 ? kWarning : kError));
                }),
                _tCell(
                  grad > 0 ? grad.toStringAsFixed(1) : '—',
                  color: grad >= 75 ? kAccent : (grad >= 60 ? kWarning : (grad > 0 ? kError : kTextDim)),
                  bold: grad > 0,
                ),
              ]);
            }),
          ],
        ),
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
