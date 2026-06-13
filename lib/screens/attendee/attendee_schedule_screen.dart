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
      return const Center(child: Text('Nessun corso attivo', style: TextStyle(color: kTextDim)));
    }

    final grouped = <String, List<ScheduledLesson>>{};
    for (final l in _lessons) {
      final key = DateFormat('yyyy-MM-dd').format(l.date);
      grouped.putIfAbsent(key, () => []).add(l);
    }
    final dates = grouped.keys.toList()..sort();

    return Column(
      children: [
        if (_courses.length > 1)
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButton<String>(
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
                _load();
              }),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            color: kWarning,
            child: dates.isEmpty
                ? const Center(child: Text('Nessuna lezione programmata', style: TextStyle(color: kTextDim)))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
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
                            child: isToday
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: kWarning,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text('OGGI', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                                  )
                                : Text(
                                    DateFormat('EEEE d MMMM', 'it').format(date),
                                    style: const TextStyle(color: kTextDim, fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                          ),
                          ...dayLessons.map((l) {
                            final isTheory = l.isTheory;
                            final color = moduleColor(l.moduleNumber);
                            return Card(
                              color: kCard,
                              margin: const EdgeInsets.only(bottom: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(color: color.withOpacity(0.2)),
                              ),
                              child: ListTile(
                                leading: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('${l.timeSlot}ª', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
                                    Text(isTheory ? 'T' : 'P', style: TextStyle(color: color, fontSize: 10)),
                                  ],
                                ),
                                title: Text(l.topic,
                                    style: const TextStyle(color: kText, fontSize: 13),
                                    maxLines: 2),
                                subtitle: Text('M${_refService.moduleLabel(l.moduleNumber)}', style: const TextStyle(color: kTextDim, fontSize: 11)),
                                trailing: l.confirmed
                                    ? const Icon(Icons.check_circle, color: kAccent, size: 16)
                                    : null,
                              ),
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

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }
}
