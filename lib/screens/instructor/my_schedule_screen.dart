import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/schedule_models.dart';
import '../../models/reference_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/course_service.dart';
import '../../services/reference_service.dart';
import '../../services/schedule_service.dart';
import '../../theme.dart';
import '../../widgets/mobile_ui.dart';

class InstructorScheduleScreen extends ConsumerStatefulWidget {
  final String userId;
  const InstructorScheduleScreen({super.key, required this.userId});

  @override
  ConsumerState<InstructorScheduleScreen> createState() => _InstructorScheduleScreenState();
}

class _InstructorScheduleScreenState extends ConsumerState<InstructorScheduleScreen> {
  final _scheduleService = ScheduleService();
  final _courseService   = CourseService();
  final _refService      = ReferenceService();
  List<ScheduledLesson> _lessons = [];
  List<SlotNote> _notes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
    _lessons = _scheduleService.getAllRelevantLessonsForInstructor(widget.userId)
        .where((l) => !l.date.isBefore(DateTime.now().subtract(const Duration(days: 7))))
        .toList();
    _notes = _courseService.getCoursesForInstructor(widget.userId)
        .expand((c) => _scheduleService.getNotesForCourse(c.id))
        .where((n) => !n.date.isBefore(DateTime.now().subtract(const Duration(days: 7))))
        .toList();
  });

  Future<void> _reload() async {
    await ref.read(authProvider).reloadDb();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    String normCode(String code) => ScheduleService.normalizeSubCode(code);

    final allCourses = _courseService.getAllCourses();
    final courseById = {for (final c in allCourses) c.id: c};
    final distinctCourseIds = _lessons.map((l) => l.courseId).toSet().toList()..sort();
    final showCourseBadge = distinctCourseIds.length > 1;
    const courseBadgeColors = [kPrimary, kAccent, kWarning, Colors.purple, Colors.teal];
    final courseColorMap = <String, Color>{
      for (var i = 0; i < distinctCourseIds.length; i++)
        distinctCourseIds[i]: courseBadgeColors[i % courseBadgeColors.length],
    };
    // Per corso: tipo effettivo (base + estensione MIL/MAML, altrimenti i moduli
    // dell'estensione restano senza monte ore) e ordinale progressivo di ogni
    // lezione su tutto il corso, come nel calendario del direttore.
    final typeInfoPerCourse = <String, CourseTypeInfo?>{};
    final ordinals = <String, int>{};
    final schedTotals = <String, int>{}; // corso|T/P|sottomodulo → ore calendarizzate
    for (final cid in distinctCourseIds) {
      final c = courseById[cid];
      typeInfoPerCourse[cid] = c == null
          ? null
          : _refService.getEffectiveCourseType(c.courseTypeId, c.extensionTypeId, c.mamlCombinationId);
      final sorted = _scheduleService.getLessonsForCourse(cid).where((l) => l.timeSlot > 0).toList()
        ..sort((a, b) {
          final dc = a.date.compareTo(b.date);
          return dc != 0 ? dc : a.timeSlot.compareTo(b.timeSlot);
        });
      for (final l in sorted) {
        final k = '$cid|${l.isTheory ? 'T' : 'P'}|${normCode(l.submoduleCode)}';
        ordinals[l.id] = schedTotals[k] = (schedTotals[k] ?? 0) + 1;
      }
    }
    final subNamesPerCourse = <String, Map<String, String>>{
      for (final cid in distinctCourseIds)
        cid: {
          for (final m in typeInfoPerCourse[cid]?.modules ?? <ModuleInfo>[])
            for (final s in m.submodules) normCode(s.code): s.name,
        },
    };
    final taskNamesPerCourse = <String, Map<int, String>>{
      for (final cid in distinctCourseIds)
        cid: {
          for (final m in typeInfoPerCourse[cid]?.modules ?? <ModuleInfo>[])
            for (final s in m.submodules)
              for (final t in s.practicalTasks)
                if (t.name.isNotEmpty) t.id: t.name,
        },
    };
    final planPerCourse = <String, Map<String, int>>{};
    for (final cid in distinctCourseIds) {
      final plan = planPerCourse[cid] = <String, int>{};
      for (final m in typeInfoPerCourse[cid]?.modules ?? <ModuleInfo>[]) {
        for (final s in m.submodules) {
          final nc = normCode(s.code);
          plan['T|$nc'] = (plan['T|$nc'] ?? 0) + s.theoryHours;
          plan['P|$nc'] = (plan['P|$nc'] ?? 0) + s.practicalHours;
        }
      }
    }

    final grouped = <String, List<ScheduledLesson>>{};
    for (final l in _lessons) {
      final key = DateFormat('yyyy-MM-dd').format(l.date);
      grouped.putIfAbsent(key, () => []).add(l);
    }
    for (final g in grouped.values) {
      g.sort((a, b) => a.timeSlot.compareTo(b.timeSlot));
    }
    final notesByDate = <String, List<SlotNote>>{};
    for (final n in _notes) {
      final key = DateFormat('yyyy-MM-dd').format(n.date);
      notesByDate.putIfAbsent(key, () => []).add(n);
    }
    final dates = {...grouped.keys, ...notesByDate.keys}.toList()..sort();

    return RefreshIndicator(
      onRefresh: _reload,
      color: kPrimary,
      child: dates.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 80),
                EmptyState(Icons.event_available, 'Nessuna lezione programmata'),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: dates.length,
              itemBuilder: (_, i) {
                final date = DateTime.parse(dates[i]);
                final dayLessons = grouped[dates[i]] ?? [];
                final dayNotes = notesByDate[dates[i]] ?? [];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DayHeader(date, accent: kInstructorAccent),
                    if (dayNotes.isNotEmpty)
                      NoteBanner(dayNotes.map((n) => n.text).join(' · ')),
                    ...dayLessons.map((l) {
                      final isTheory = l.isTheory;
                      final color = moduleColor(l.moduleNumber);
                      final nc = normCode(l.submoduleCode);
                      final subNames = subNamesPerCourse[l.courseId] ?? {};
                      final taskNames = taskNamesPerCourse[l.courseId] ?? {};
                      final typeLabel = isTheory ? 'T' : 'P';
                      final plan = planPerCourse[l.courseId]?['$typeLabel|$nc'] ?? 0;
                      // Senza monte ore nel programma il totale è quanto calendarizzato.
                      final total = plan > 0 ? plan : (schedTotals['${l.courseId}|$typeLabel|$nc'] ?? 0);
                      final ord = ordinals[l.id];
                      // Ore oltre il piano = recuperi: il contatore non supera il piano.
                      final hoursStr = ord == null
                          ? typeLabel
                          : '$typeLabel ${ord > total ? total : ord}/$total h${ord > total ? ' (rec.)' : ''}';
                      final slotTime = typeInfoPerCourse[l.courseId]
                          ?.schedule
                          .slotsForWeekday(l.date.weekday)
                          .where((t) => t.slot == l.timeSlot)
                          .firstOrNull;

                      String displayTopic = l.topic;
                      if (RegExp(r'^\d').hasMatch(l.topic) && l.topic.contains('.')) {
                        displayTopic = subNames[normCode(l.topic)] ?? subNames[nc] ?? l.topic;
                      }

                      return LessonCard(
                        color: color,
                        slot: l.timeSlot,
                        isTheory: isTheory,
                        module: 'M${_refService.moduleLabel(l.moduleNumber)}',
                        topic: displayTopic,
                        start: slotTime?.start,
                        end: slotTime?.end,
                        task: l.taskId != null ? '${taskNames[l.taskId] ?? l.taskId}' : null,
                        overline: showCourseBadge ? courseById[l.courseId]?.title : null,
                        overlineColor: courseColorMap[l.courseId],
                        meta: hoursStr,
                        confirmed: l.confirmed,
                      );
                    }),
                  ],
                );
              },
            ),
    );
  }
}
