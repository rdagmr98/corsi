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
          ? const Center(child: Text('Nessuna lezione programmata', style: TextStyle(color: kTextDim)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: dates.length,
              itemBuilder: (_, i) {
                final date = DateTime.parse(dates[i]);
                final dayLessons = grouped[dates[i]] ?? [];
                final dayNotes = notesByDate[dates[i]] ?? [];
                final isToday = _isToday(date);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          if (isToday)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: kPrimary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text('OGGI', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            )
                          else
                            Text(
                              DateFormat('EEEE d MMMM', 'it').format(date),
                              style: TextStyle(
                                color: date.isBefore(DateTime.now()) ? kTextDim : kText,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (dayNotes.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: kWarning.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: kWarning.withOpacity(0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.sticky_note_2_outlined, color: kWarning, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                dayNotes.map((n) => n.text).join(' · '),
                                style: const TextStyle(color: kWarning, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
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
                      final courseColor = courseColorMap[l.courseId];

                      return Card(
                        color: kCard,
                        margin: const EdgeInsets.only(bottom: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: showCourseBadge && courseColor != null
                                ? courseColor.withOpacity(0.6)
                                : color.withOpacity(0.2),
                            width: showCourseBadge ? 1.5 : 1,
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 48,
                            height: 40,
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: slotTime == null
                                ? Text('${l.timeSlot}ª',
                                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12))
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(slotTime.start,
                                          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
                                      Text(slotTime.end, style: TextStyle(color: color, fontSize: 10)),
                                    ],
                                  ),
                          ),
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showCourseBadge)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    courseById[l.courseId]?.title ?? '',
                                    style: TextStyle(
                                      color: courseColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              Text(displayTopic,
                                  style: const TextStyle(color: kText, fontSize: 13),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                          subtitle: Text(
                              'M${_refService.moduleLabel(l.moduleNumber)} · ${isTheory ? "Teoria" : "Pratica"} · $hoursStr${l.taskId != null ? ' · Task ${taskNames[l.taskId] ?? l.taskId}' : ''}',
                              style: const TextStyle(color: kTextDim, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          trailing: l.confirmed
                              ? const Icon(Icons.check_circle, color: kAccent, size: 18)
                              : const Icon(Icons.schedule, color: kTextDim, size: 18),
                        ),
                      );
                    }),
                    const SizedBox(height: 4),
                  ],
                );
              },
            ),
    );
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }
}
