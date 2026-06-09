import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/course_service.dart';
import '../../services/reference_service.dart';
import '../../services/schedule_service.dart';
import '../../theme.dart';

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
      return const Center(child: Text('Nessun corso attivo', style: TextStyle(color: kTextDim)));
    }

    final course = _selected;
    if (course == null) return const SizedBox();

    final lessons   = _scheduleService.getLessonsForCourse(course.id);
    final records   = _attendanceService.getRecordsForAttendee(course.id, widget.userId);
    final recordMap = {for (final r in records) r.scheduleId: r};
    final typeInfo  = _refService.getCourseType(course.courseTypeId);

    final modStats = _attendanceService.computePerModuleStats(
      course.id, widget.userId, lessons, modules: typeInfo?.modules);

    // Global totals (denominator = confirmed lessons)
    final totalConfirmed = modStats.values.fold(0, (s, m) => s + (m['confirmed'] ?? 0));
    final totalAbsent    = modStats.values.fold(0, (s, m) => s + (m['absent'] ?? 0));
    final totalRecovered = modStats.values.fold(0, (s, m) => s + (m['recovered'] ?? 0));
    final totalUnrec     = modStats.values.fold(0, (s, m) => s + (m['unrecovered'] ?? 0));
    final globalPct      = totalConfirmed > 0 ? (totalConfirmed - totalUnrec) / totalConfirmed : 1.0;
    final anyWarn        = modStats.values.any((m) {
      final c = m['confirmed'] ?? 0;
      return c > 0 && (m['unrecovered'] ?? 0) / c > 0.10;
    });

    final modNames = <int, String>{
      for (final m in typeInfo?.modules ?? []) m.number: m.name,
    };

    return RefreshIndicator(
      onRefresh: _reload,
      color: kWarning,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_courses.length > 1)
                    DropdownButton<String>(
                      value: _selected?.id,
                      dropdownColor: kSurface,
                      style: const TextStyle(color: kText),
                      isExpanded: true,
                      underline: const SizedBox(),
                      items: _courses
                          .map((c) => DropdownMenuItem(value: c.id, child: Text(c.title)))
                          .toList(),
                      onChanged: (id) => setState(() {
                        _selected = _courses.firstWhere((c) => c.id == id);
                      }),
                    ),
                  const SizedBox(height: 12),

                  // Global summary card
                  Card(
                    color: kCard,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: anyWarn
                            ? kError.withValues(alpha: 0.4)
                            : kAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _stat('$totalConfirmed', 'Lezioni', kTextDim),
                              _stat('$totalAbsent', 'Assenze', totalAbsent > 0 ? kError : kAccent),
                              _stat('$totalRecovered', 'Recuperate', kPrimary),
                              _stat(
                                '${(globalPct * 100).toStringAsFixed(0)}%',
                                'Presenza',
                                globalPct >= 0.90 ? kAccent : kError,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: globalPct,
                            backgroundColor: kSurface,
                            color: globalPct >= 0.90 ? kAccent : kError,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Per-module stats
                  if (modStats.isNotEmpty) ...[
                    const Text('Dettaglio per modulo',
                        style: TextStyle(color: kTextDim, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    ..._buildModuleRows(modStats, modNames),
                  ],
                ],
              ),
            ),
          ),

          // Lesson list
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final l = lessons[i];
                  if (l.timeSlot == 0) return const SizedBox.shrink();
                  final r         = recordMap[l.id];
                  final isRecovery  = r?.justification == 'recupero';
                  final isPresent   = r?.present ?? false;
                  final isJustified = r != null && r.justification != null && r.justification != 'recupero';

                  Color statusColor;
                  IconData statusIcon;
                  String statusText;
                  if (r == null && l.confirmed) {
                    statusColor = kAccent;
                    statusIcon  = Icons.check_circle;
                    statusText  = 'Presente';
                  } else if (r == null) {
                    statusColor = kTextDim;
                    statusIcon  = Icons.schedule;
                    statusText  = 'Non registrata';
                  } else if (isRecovery) {
                    statusColor = kPrimary;
                    statusIcon  = Icons.replay;
                    statusText  = 'Recuperata (M${r.recoveredModule ?? l.moduleNumber})';
                  } else if (isPresent) {
                    statusColor = kAccent;
                    statusIcon  = Icons.check_circle;
                    statusText  = 'Presente';
                  } else if (isJustified) {
                    statusColor = kWarning;
                    statusIcon  = Icons.warning_amber;
                    statusText  = 'Giustificata';
                  } else {
                    statusColor = kError;
                    statusIcon  = Icons.cancel;
                    statusText  = 'Assente';
                  }

                  return Card(
                    color: kCard,
                    margin: const EdgeInsets.only(bottom: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    child: ListTile(
                      dense: true,
                      leading: Icon(statusIcon, color: statusColor, size: 20),
                      title: Text('M${l.moduleNumber} ${l.topic}',
                          style: const TextStyle(color: kText, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(DateFormat('dd/MM/yyyy').format(l.date),
                          style: const TextStyle(color: kTextDim, fontSize: 11)),
                      trailing: Text(statusText,
                          style: TextStyle(color: statusColor, fontSize: 11)),
                    ),
                  );
                },
                childCount: lessons.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildModuleRows(
    Map<int, Map<String, int>> modStats,
    Map<int, String> modNames,
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
      final pct   = conf > 0 ? (conf - unrec) / conf : 1.0;
      final warn  = conf > 0 && unrec / conf > 0.10;
      final color = warn ? kError : (pct >= 0.90 ? kAccent : kWarning);

      return Card(
        color: kSurface,
        margin: const EdgeInsets.only(bottom: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: warn ? kError.withValues(alpha: 0.4) : kBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('M$mod',
                    style: TextStyle(
                        color: color, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (modNames[mod] != null)
                      Text(modNames[mod]!,
                          style: const TextStyle(color: kText, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    Text(
                      absent == 0
                          ? 'Nessuna assenza su $conf lezioni'
                          : '$absent ass. · $rec rec. · $unrec non rec. / $conf lez.',
                      style: TextStyle(color: warn ? kError : kTextDim, fontSize: 10),
                    ),
                    if (warn)
                      const Text('LIMITE 10% SUPERATO',
                          style: TextStyle(
                              color: kError, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(pct * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    color: color, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _stat(String value, String label, Color color) => Column(
    children: [
      Text(value,
          style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: kTextDim, fontSize: 11)),
    ],
  );
}
