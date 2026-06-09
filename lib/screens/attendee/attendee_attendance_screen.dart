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
  String? _filterMode; // null = tutti, 'present', 'absent', 'recovery'

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
    final typeInfo  = _refService.getEffectiveCourseType(course.courseTypeId, course.extensionTypeId);

    String normCode(String code) {
      String c = code.endsWith('P') ? code.substring(0, code.length - 1) : code;
      final parts = c.split('.');
      return parts.length >= 3 ? '${parts[0]}.${parts[1]}' : c;
    }

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

    // Recovery window: how many more recoveries each over-limit module needs
    final recoveryWindow = <int, int>{};
    for (final e in modStats.entries) {
      final confirmed  = e.value['confirmed'] ?? 0;
      final unrecovered = e.value['unrecovered'] ?? 0;
      if (confirmed > 0 && unrecovered / confirmed > 0.10) {
        final maxAllowed = (confirmed * 0.10).floor();
        recoveryWindow[e.key] = unrecovered - maxAllowed;
      }
    }

    // Recovery records (synthetic schedule IDs)
    final recoveryRecords = records.where((r) => r.justification == 'recupero').toList()
      ..sort((a, b) {
        final da = _dateFromSyntheticId(a.scheduleId);
        final db = _dateFromSyntheticId(b.scheduleId);
        if (da == null || db == null) return 0;
        return db.compareTo(da);
      });

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
      if (_filterMode == 'present') return isPresent(l);
      if (_filterMode == 'absent')  return isAbsent(l);
      return true;
    }).toList();

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
                        _filterMode = null;
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

                  // Recovery window alert
                  if (recoveryWindow.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kError.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kError.withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.warning_amber, color: kError, size: 16),
                            SizedBox(width: 6),
                            Text('Recuperi necessari per rientrare nel 10%',
                                style: TextStyle(color: kError, fontSize: 12, fontWeight: FontWeight.w600)),
                          ]),
                          const SizedBox(height: 6),
                          ...recoveryWindow.entries.map((e) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '• M${e.key}: ancora ${e.value} lezione${e.value > 1 ? 'i' : 'e'} da recuperare',
                              style: const TextStyle(color: kError, fontSize: 11),
                            ),
                          )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Per-module stats
                  if (modStats.isNotEmpty) ...[
                    const Text('Dettaglio per modulo',
                        style: TextStyle(color: kTextDim, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    ..._buildModuleRows(modStats, modNames),
                    const SizedBox(height: 12),
                  ],

                  // Filter chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _filterChip('Tutte', null),
                      _filterChip('Presenze', 'present'),
                      _filterChip('Assenze', 'absent'),
                      if (totalRecovered > 0) _filterChip('Recuperi', 'recovery'),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // Lesson / recovery list
          if (_filterMode == 'recovery')
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: recoveryRecords.isEmpty
                  ? const SliverToBoxAdapter(
                      child: Center(child: Text('Nessun recupero registrato',
                          style: TextStyle(color: kTextDim, fontSize: 13))))
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final r = recoveryRecords[i];
                          final date = _dateFromSyntheticId(r.scheduleId);
                          final modNum = r.recoveredModule;
                          return Card(
                            color: kCard,
                            margin: const EdgeInsets.only(bottom: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            child: ListTile(
                              dense: true,
                              leading: const Icon(Icons.replay, color: kPrimary, size: 20),
                              title: Text(
                                modNum != null
                                    ? 'Recupero M$modNum – ${modNames[modNum] ?? ''}'
                                    : 'Recupero',
                                style: const TextStyle(color: kText, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: date != null
                                  ? Text(DateFormat('dd/MM/yyyy').format(date),
                                      style: const TextStyle(color: kTextDim, fontSize: 11))
                                  : null,
                              trailing: const Text('Recuperata',
                                  style: TextStyle(color: kPrimary, fontSize: 11)),
                            ),
                          );
                        },
                        childCount: recoveryRecords.length,
                      ),
                    ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                    final conf = isTheory ? (subConfT[nc] ?? 0) : (subConfP[nc] ?? 0);
                    final plan = isTheory ? (subPlanT[nc] ?? 0) : (subPlanP[nc] ?? 0);
                    final typeLabel = isTheory ? 'T' : 'P';
                    final hoursStr = plan > 0 ? '· $typeLabel $conf/$plan h' : '· $typeLabel ${conf}h';

                    String displayTopic = l.topic;
                    if (RegExp(r'^\d').hasMatch(l.topic) && l.topic.contains('.')) {
                      displayTopic = subNames[normCode(l.topic)] ?? subNames[nc] ?? l.topic;
                    }

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
                        title: Text('M${l.moduleNumber} $displayTopic',
                            style: const TextStyle(color: kText, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${DateFormat('dd/MM/yyyy').format(l.date)} $hoursStr',
                            style: const TextStyle(color: kTextDim, fontSize: 11)),
                        trailing: Text(statusText,
                            style: TextStyle(color: statusColor, fontSize: 11)),
                      ),
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

  DateTime? _dateFromSyntheticId(String id) {
    // Format: 'recovery:courseId8:attendeeId8:YYYY-MM-DD:mN'
    final parts = id.split(':');
    if (parts.length >= 4) return DateTime.tryParse(parts[3]);
    return null;
  }

  Widget _filterChip(String label, String? mode) {
    final active = _filterMode == mode;
    return FilterChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => setState(() => _filterMode = mode),
      selectedColor: kPrimary.withValues(alpha: 0.25),
      checkmarkColor: kPrimary,
      labelStyle: TextStyle(
        color: active ? kPrimary : kTextDim,
        fontSize: 12,
        fontWeight: active ? FontWeight.w600 : FontWeight.normal,
      ),
      backgroundColor: kSurface,
      side: BorderSide(color: active ? kPrimary : kBorder),
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
