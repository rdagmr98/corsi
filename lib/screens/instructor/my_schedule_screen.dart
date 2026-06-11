import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/schedule_models.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
    _lessons = _scheduleService.getAllRelevantLessonsForInstructor(widget.userId)
        .where((l) => !l.date.isBefore(DateTime.now().subtract(const Duration(days: 7))))
        .toList();
  });

  Future<void> _reload() async {
    await ref.read(authProvider).reloadDb();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    String normCode(String code) => ScheduleService.normalizeSubCode(code);

    final courseTypeMap = <String, String>{
      for (final c in _courseService.getAllCourses()) c.id: c.courseTypeId,
    };
    final subNamesPerType = <String, Map<String, String>>{};
    final subSchedTPerType = <String, Map<String, int>>{};
    final subSchedPPerType = <String, Map<String, int>>{};
    for (final l in _lessons) {
      if (l.timeSlot == 0) continue;
      final typeId = courseTypeMap[l.courseId] ?? '';
      subNamesPerType.putIfAbsent(typeId, () {
        final ti = _refService.getCourseType(typeId);
        return <String, String>{
          for (final m in ti?.modules ?? [])
            for (final s in m.submodules) s.code: s.name,
        };
      });
      final nc = normCode(l.submoduleCode);
      if (l.isTheory) {
        subSchedTPerType.putIfAbsent(typeId, () => {});
        subSchedTPerType[typeId]![nc] = (subSchedTPerType[typeId]![nc] ?? 0) + 1;
      } else {
        subSchedPPerType.putIfAbsent(typeId, () => {});
        subSchedPPerType[typeId]![nc] = (subSchedPPerType[typeId]![nc] ?? 0) + 1;
      }
    }
    final subPlanPerType = <String, Map<String, ({int t, int p})>>{};
    for (final typeId in subNamesPerType.keys) {
      final ti = _refService.getCourseType(typeId);
      subPlanPerType[typeId] = {
        for (final m in ti?.modules ?? [])
          for (final s in m.submodules)
            s.code: (
              t: s.theoryHours > 0    ? s.theoryHours    : (subSchedTPerType[typeId]?[s.code] ?? 0),
              p: s.practicalHours > 0 ? s.practicalHours : (subSchedPPerType[typeId]?[s.code] ?? 0),
            ),
      };
    }

    final grouped = <String, List<ScheduledLesson>>{};
    for (final l in _lessons) {
      final key = DateFormat('yyyy-MM-dd').format(l.date);
      grouped.putIfAbsent(key, () => []).add(l);
    }
    final dates = grouped.keys.toList()..sort();

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
                final dayLessons = grouped[dates[i]]!;
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
                    ...dayLessons.map((l) {
                      final isTheory = l.isTheory;
                      final color = moduleColor(l.moduleNumber);
                      final typeId = courseTypeMap[l.courseId] ?? '';
                      final nc = normCode(l.submoduleCode);
                      final subNames = subNamesPerType[typeId] ?? {};
                      final planMap = subPlanPerType[typeId] ?? {};
                      final plan = planMap[nc];
                      final schedT = subSchedTPerType[typeId]?[nc] ?? 0;
                      final schedP = subSchedPPerType[typeId]?[nc] ?? 0;
                      final rawSched = isTheory ? schedT : schedP;
                      final planCount = isTheory ? (plan?.t ?? 0) : (plan?.p ?? 0);
                      // Ore oltre il piano = recuperi: il contatore non supera il piano.
                      final schedCount =
                          planCount > 0 && rawSched > planCount ? planCount : rawSched;
                      final typeLabel = isTheory ? 'T' : 'P';
                      final hoursStr = planCount > 0
                          ? '$typeLabel $schedCount/$planCount h'
                          : '$typeLabel ${schedCount}h';

                      String displayTopic = l.topic;
                      if (RegExp(r'^\d').hasMatch(l.topic) && l.topic.contains('.')) {
                        displayTopic = subNames[normCode(l.topic)] ?? subNames[nc] ?? l.topic;
                      }

                      return Card(
                        color: kCard,
                        margin: const EdgeInsets.only(bottom: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: color.withOpacity(0.2)),
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${l.timeSlot}ª',
                              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          title: Text(displayTopic, style: const TextStyle(color: kText, fontSize: 13)),
                          subtitle: Text('M${l.moduleNumber} · ${isTheory ? "Teoria" : "Pratica"} · $hoursStr',
                              style: const TextStyle(color: kTextDim, fontSize: 11)),
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
