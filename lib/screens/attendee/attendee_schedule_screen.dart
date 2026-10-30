import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
import '../../models/schedule_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/course_service.dart';
import '../../services/reference_service.dart';
import '../../services/schedule_service.dart';
import '../../theme.dart';
import '../../widgets/mobile_ui.dart';

class AttendeeScheduleScreen extends ConsumerStatefulWidget {
  final String userId;
  const AttendeeScheduleScreen({super.key, required this.userId});

  @override
  ConsumerState<AttendeeScheduleScreen> createState() => _AttendeeScheduleScreenState();
}

class _AttendeeScheduleScreenState extends ConsumerState<AttendeeScheduleScreen> {
  final _courseService = CourseService();
  final _scheduleService = ScheduleService();
  final _refService = ReferenceService();

  List<Course> _courses = [];
  Course? _selected;
  List<ScheduledLesson> _lessons = [];
  List<SlotNote> _notes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _courses = _courseService.getCoursesForAttendee(widget.userId);
      if (_selected == null && _courses.isNotEmpty) _selected = _courses.first;
      if (_selected != null) {
        final now = DateTime.now();
        _lessons = _scheduleService.getLessonsForCourse(_selected!.id)
            .where((l) => !l.date.isBefore(now.subtract(const Duration(days: 1))))
            .toList();
        _notes = _scheduleService.getNotesForCourse(_selected!.id)
            .where((n) => !n.date.isBefore(now.subtract(const Duration(days: 1))))
            .toList();
      }
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

    final grouped = <String, List<ScheduledLesson>>{};
    for (final l in _lessons) {
      final key = DateFormat('yyyy-MM-dd').format(l.date);
      grouped.putIfAbsent(key, () => []).add(l);
    }
    final notesByDate = <String, List<SlotNote>>{};
    for (final n in _notes) {
      final key = DateFormat('yyyy-MM-dd').format(n.date);
      notesByDate.putIfAbsent(key, () => []).add(n);
    }
    final dates = {...grouped.keys, ...notesByDate.keys}.toList()..sort();

    final effectiveType = _selected == null
        ? null
        : _refService.getEffectiveCourseType(_selected!.courseTypeId, _selected!.extensionTypeId, _selected!.mamlCombinationId);
    final taskNames = <int, String>{
      for (final m in effectiveType?.modules ?? [])
        for (final s in m.submodules)
          for (final t in s.practicalTasks)
            if (t.name.isNotEmpty) t.id: t.name,
    };

    return Column(
      children: [
        if (_courses.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: CourseSelector(
              courses: _courses,
              selectedId: _selected?.id,
              onSelected: (c) {
                _selected = c;
                _load();
              },
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            color: kAttendeeAccent,
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
                          DayHeader(date, accent: kAttendeeAccent),
                          if (dayNotes.isNotEmpty)
                            NoteBanner(dayNotes.map((n) => n.text).join(' · ')),
                          ...dayLessons.map((l) {
                            final slotTime = effectiveType?.schedule
                                .slotsForWeekday(l.date.weekday)
                                .where((t) => t.slot == l.timeSlot)
                                .firstOrNull;
                            return LessonCard(
                              color: moduleColor(l.moduleNumber),
                              slot: l.timeSlot,
                              isTheory: l.isTheory,
                              module: 'M${_refService.moduleLabel(l.moduleNumber)}',
                              topic: l.topic,
                              start: slotTime?.start,
                              end: slotTime?.end,
                              task: l.taskId != null ? '${taskNames[l.taskId] ?? l.taskId}' : null,
                              confirmed: l.confirmed,
                            );
                          }),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
