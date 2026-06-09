import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
import '../../models/reference_models.dart';
import '../../models/schedule_models.dart';
import '../../models/user_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/course_service.dart';
import '../../services/reference_service.dart';
import '../../services/schedule_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';

class DirectorAttendanceTab extends ConsumerStatefulWidget {
  final String userId;
  const DirectorAttendanceTab({super.key, required this.userId});

  @override
  ConsumerState<DirectorAttendanceTab> createState() => _DirectorAttendanceTabState();
}

class _DirectorAttendanceTabState extends ConsumerState<DirectorAttendanceTab>
    with SingleTickerProviderStateMixin {
  final _courseService = CourseService();
  final _scheduleService = ScheduleService();
  final _attendanceService = AttendanceService();
  final _userService = UserService();
  final _refService = ReferenceService();

  late TabController _tabController;
  List<Course> _courses = [];
  Course? _selected;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _load() {
    setState(() {
      _courses = _courseService.getCoursesForDirector(widget.userId);
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
      return const Center(child: Text('Nessun corso assegnato', style: TextStyle(color: kTextDim)));
    }

    final course = _selected;
    if (course == null) return const SizedBox();

    final allLessons = _scheduleService.getLessonsForCourse(course.id);
    final attendees = _userService.getAllUsers()
        .where((u) => course.attendeeIds.contains(u.id))
        .toList()
      ..sort((a, b) => a.cognome.compareTo(b.cognome));
    final typeInfo = _refService.getCourseType(course.courseTypeId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(
            children: [
              if (_courses.length > 1)
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
                  }),
                )
              else
                Text('Presenze: ${_selected?.title ?? ''}',
                    style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(icon: const Icon(Icons.refresh, color: kTextDim), onPressed: _reload),
            ],
          ),
        ),
        const SizedBox(height: 4),
        TabBar(
          controller: _tabController,
          indicatorColor: kPrimary,
          labelColor: kPrimary,
          unselectedLabelColor: kTextDim,
          tabs: const [
            Tab(text: 'Per Frequentatore'),
            Tab(text: 'Per Lezione'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPerStudentView(course, attendees, allLessons, typeInfo),
              _buildPerLessonView(course, attendees, allLessons),
            ],
          ),
        ),
      ],
    );
  }

  // ── Per-student tab ──────────────────────────────────────────────────────

  Widget _buildPerStudentView(
    Course course,
    List<AppUser> attendees,
    List<ScheduledLesson> allLessons,
    CourseTypeInfo? typeInfo,
  ) {
    if (attendees.isEmpty) {
      return const Center(child: Text('Nessun frequentatore', style: TextStyle(color: kTextDim)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      itemCount: attendees.length,
      itemBuilder: (_, i) => _buildStudentCard(course, attendees[i], allLessons, typeInfo),
    );
  }

  Widget _buildStudentCard(
    Course course,
    AppUser a,
    List<ScheduledLesson> allLessons,
    CourseTypeInfo? typeInfo,
  ) {
    final modStats = _attendanceService.computePerModuleStats(
      course.id, a.id, allLessons, modules: typeInfo?.modules);
    final totalAbsent = modStats.values.fold(0, (s, m) => s + (m['absent'] ?? 0));
    final totalUnrecovered = modStats.values.fold(0, (s, m) => s + (m['unrecovered'] ?? 0));
    final totalPlannedHours = typeInfo?.modules.fold(0, (s, m) => s + m.totalHours) ?? 0;
    final anyWarning = typeInfo != null &&
        modStats.entries.any((e) {
          final total = e.value['total'] ?? 0;
          final unrecovered = e.value['unrecovered'] ?? 0;
          return total > 0 && unrecovered / total > 0.10;
        });

    return Card(
      color: kCard,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: anyWarning ? kError.withOpacity(0.35) : kBorder),
      ),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: anyWarning ? kError.withOpacity(0.15) : kPrimary.withOpacity(0.15),
          child: Text(
            a.cognome.isNotEmpty ? a.cognome[0].toUpperCase() : '?',
            style: TextStyle(
                color: anyWarning ? kError : kPrimary, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(a.fullName,
            style: const TextStyle(color: kText, fontWeight: FontWeight.w500, fontSize: 14)),
        subtitle: Text(
          '$totalAbsent ore ass. · $totalUnrecovered non rec. su $totalPlannedHours ore prev.',
          style: TextStyle(
              color: anyWarning ? kError : kTextDim, fontSize: 12),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.person_remove_outlined, color: kError, size: 18),
          tooltip: 'Espelli dal corso',
          onPressed: () => _expelStudent(course, a),
        ),
        children: typeInfo == null
            ? []
            : typeInfo.modules
                .where((mod) => modStats.containsKey(mod.number) && (modStats[mod.number]!['total'] ?? 0) > 0)
                .map((mod) => _buildModuleRow(course, a, mod, modStats[mod.number]!))
                .toList(),
      ),
    );
  }

  Future<void> _expelStudent(Course course, AppUser student) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Espelli frequentatore', style: TextStyle(color: kText)),
        content: Text(
          'Rimuovere ${student.fullName} dal corso "${course.title}"?\n\nI dati di presenze e voti verranno mantenuti.',
          style: const TextStyle(color: kTextDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla', style: TextStyle(color: kTextDim)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kError),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Espelli'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final updated = course.copyWith(
      attendeeIds: course.attendeeIds.where((id) => id != student.id).toList(),
    );
    await _courseService.updateCourse(updated);
    _reload();
  }

  Widget _buildModuleRow(
    Course course,
    AppUser a,
    ModuleInfo mod,
    Map<String, int> stats,
  ) {
    final total = stats['total'] ?? 0;
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
            style: TextStyle(
                color: warn ? kError : kPrimary,
                fontSize: 11,
                fontWeight: FontWeight.bold)),
      ),
      title: Text(mod.name,
          style: const TextStyle(color: kText, fontSize: 12),
          overflow: TextOverflow.ellipsis),
      subtitle: warn
          ? Text(
              '$unrecovered ore non rec. / $total ore prev. — ${(pct * 100).toStringAsFixed(1)}%  ⚠ LIMITE 10%',
              style: const TextStyle(color: kError, fontSize: 11),
            )
          : Text(
              absent == 0
                  ? 'Nessuna assenza su $total ore prev.'
                  : '$absent ore ass. · $recovered rec. · $unrecovered non rec. / $total ore prev.',
              style: const TextStyle(color: kTextDim, fontSize: 11),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (absent > 0)
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: kAccent, size: 20),
              tooltip: 'Aggiungi recupero',
              onPressed: () => _addRecovery(course, a.id, mod.number),
            ),
          if (recovered > 0)
            IconButton(
              icon: const Icon(Icons.history, color: kTextDim, size: 20),
              tooltip: 'Vedi recuperi',
              onPressed: () => _showRecoveries(course, a.id, a.fullName, mod.number),
            ),
        ],
      ),
    );
  }

  Future<void> _addRecovery(Course course, String attendeeId, int moduleNumber) async {
    DateTime? selectedDate;
    final user = ref.read(authProvider).currentUser;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: kCard,
          title: const Text('Aggiungi Recupero', style: TextStyle(color: kText)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Modulo: M$moduleNumber',
                  style: const TextStyle(color: kTextDim, fontSize: 13)),
              const SizedBox(height: 12),
              const Text('Data recupero:',
                  style: TextStyle(color: kTextDim, fontSize: 13)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    selectedDate != null
                        ? DateFormat('dd/MM/yyyy').format(selectedDate!)
                        : 'Non impostata',
                    style: const TextStyle(color: kText),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (d != null) setDlg(() => selectedDate = d);
                    },
                    child: const Text('Scegli'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla', style: TextStyle(color: kTextDim)),
            ),
            ElevatedButton(
              onPressed: selectedDate == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && selectedDate != null) {
      await _attendanceService.saveRecovery(
        courseId: course.id,
        attendeeId: attendeeId,
        confirmedBy: user?.id ?? '',
        recoveredModule: moduleNumber,
        recoveryDate: selectedDate!,
      );
      _reload();
    }
  }

  Future<void> _showRecoveries(
      Course course, String attendeeId, String name, int moduleNumber) async {
    final records = _attendanceService
        .getRecordsForAttendee(course.id, attendeeId)
        .where((r) => r.justification == 'recupero' && r.recoveredModule == moduleNumber)
        .toList();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: Text('Recuperi M$moduleNumber — $name',
            style: const TextStyle(color: kText)),
        content: SizedBox(
          width: 400,
          child: records.isEmpty
              ? const Text('Nessun recupero registrato.',
                  style: TextStyle(color: kTextDim))
              : ListView(
                  shrinkWrap: true,
                  children: records
                      .map((r) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.check_circle_outline,
                                color: kAccent, size: 18),
                            title: Text(
                              r.confirmedAt != null
                                  ? 'Recupero del ${DateFormat('dd/MM/yyyy').format(r.confirmedAt!)}'
                                  : 'Recupero',
                              style: const TextStyle(color: kText, fontSize: 12),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: kError, size: 18),
                              onPressed: () async {
                                await _attendanceService.deleteRecovery(r.id);
                                if (ctx.mounted) Navigator.pop(ctx);
                                _reload();
                              },
                            ),
                          ))
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Chiudi')),
        ],
      ),
    );
  }

  // ── Per-lesson tab (file controllo istruttori) ───────────────────────────

  Widget _buildPerLessonView(
    Course course,
    List<AppUser> attendees,
    List<ScheduledLesson> allLessons,
  ) {
    final confirmedLessons = allLessons
        .where((l) => l.confirmed && l.timeSlot > 0)
        .toList()
      ..sort((a, b) {
        final dc = a.date.compareTo(b.date);
        return dc != 0 ? dc : a.timeSlot.compareTo(b.timeSlot);
      });

    final allRecords = _attendanceService.getAllRecordsForCourse(course.id);
    final recoveryRecords = allRecords
        .where((r) => r.justification == 'recupero' && r.recoveredModule != null)
        .toList();

    final Map<String, List<AttendanceRecord>> recoveryByDate = {};
    for (final r in recoveryRecords) {
      if (r.confirmedAt != null) {
        final dk = DateFormat('yyyy-MM-dd').format(r.confirmedAt!);
        recoveryByDate.putIfAbsent(dk, () => []).add(r);
      }
    }

    final attendeeMap = {for (final a in attendees) a.id: a};

    final items = <Widget>[
      ...confirmedLessons.map((l) {
        final absentRecords = allRecords
            .where((r) => r.scheduleId == l.id && !r.present)
            .toList();
        return _buildLessonCard(l, absentRecords, attendeeMap);
      }),
      if (recoveryByDate.isNotEmpty)
        _buildRecoverySection(recoveryByDate, attendeeMap),
    ];

    if (items.isEmpty) {
      return const Center(
          child: Text('Nessuna lezione confermata', style: TextStyle(color: kTextDim)));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      children: items,
    );
  }

  Widget _buildLessonCard(
    ScheduledLesson l,
    List<AttendanceRecord> absentRecords,
    Map<String, AppUser> attendeeMap,
  ) {
    return Card(
      color: kCard,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kPrimary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'M${l.moduleNumber} · ${l.submoduleCode} · S${l.timeSlot}',
                    style: const TextStyle(color: kPrimary, fontSize: 10),
                  ),
                ),
                const SizedBox(width: 8),
                Text(DateFormat('dd/MM/yyyy').format(l.date),
                    style: const TextStyle(color: kTextDim, fontSize: 11)),
                const Spacer(),
                if (absentRecords.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: kError.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('${absentRecords.length} ass.',
                        style: const TextStyle(color: kError, fontSize: 10)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(l.topic,
                style: const TextStyle(color: kText, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            if (absentRecords.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Divider(color: kBorder, height: 1),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: absentRecords.map((r) {
                  final att = attendeeMap[r.attendeeId];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: kError.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: kError.withOpacity(0.3)),
                    ),
                    child: Text(
                      att?.fullName ?? r.attendeeId.substring(0, 8),
                      style: const TextStyle(color: kError, fontSize: 11),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecoverySection(
    Map<String, List<AttendanceRecord>> recoveryByDate,
    Map<String, AppUser> attendeeMap,
  ) {
    final sortedDates = recoveryByDate.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Divider(color: kBorder),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'RECUPERI',
            style: TextStyle(
                color: kAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5),
          ),
        ),
        ...sortedDates.map((dk) {
          final recs = recoveryByDate[dk]!;
          final date = DateTime.parse(dk);
          return Card(
            color: kCard,
            margin: const EdgeInsets.only(bottom: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: kAccent.withOpacity(0.25)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.replay, color: kAccent, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('dd/MM/yyyy').format(date),
                        style: const TextStyle(
                            color: kAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...recs.map((r) {
                    final att = attendeeMap[r.attendeeId];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        children: [
                          Text(
                            att?.fullName ?? r.attendeeId.substring(0, 8),
                            style: const TextStyle(color: kText, fontSize: 12),
                          ),
                          const SizedBox(width: 8),
                          const Text('→',
                              style: TextStyle(color: kTextDim, fontSize: 12)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: kAccent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'M${r.recoveredModule}',
                              style: const TextStyle(
                                  color: kAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }
}
