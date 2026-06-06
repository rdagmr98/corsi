import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/course_service.dart';
import '../../services/schedule_service.dart';
import '../../theme.dart';

class AttendeeAttendanceScreen extends ConsumerStatefulWidget {
  final String userId;
  const AttendeeAttendanceScreen({super.key, required this.userId});

  @override
  ConsumerState<AttendeeAttendanceScreen> createState() => _AttendeeAttendanceScreenState();
}

class _AttendeeAttendanceScreenState extends ConsumerState<AttendeeAttendanceScreen> {
  final _courseService = CourseService();
  final _scheduleService = ScheduleService();
  final _attendanceService = AttendanceService();

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

    final stats = _attendanceService.computeAbsences(course.id, widget.userId);
    final lessons = _scheduleService.getLessonsForCourse(course.id);
    final records = _attendanceService.getRecordsForAttendee(course.id, widget.userId);
    final recordMap = {for (final r in records) r.scheduleId: r};
    final total = stats['total'] ?? 0;
    final absent = stats['absent'] ?? 0;
    final present = total - absent;
    final pct = total > 0 ? present / total : 1.0;

    return RefreshIndicator(
      onRefresh: _reload,
      color: kWarning,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Column(
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
                  Card(
                    color: kCard,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: pct >= 0.75 ? kAccent.withOpacity(0.3) : kError.withOpacity(0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _stat('$present', 'Presenti', kAccent),
                              _stat('$absent', 'Assenze', kError),
                              _stat('$total', 'Totale', kText),
                              _stat('${(pct * 100).toStringAsFixed(0)}%', 'Presenza', pct >= 0.75 ? kAccent : kError),
                            ],
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: pct,
                            backgroundColor: kSurface,
                            color: pct >= 0.75 ? kAccent : kError,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final l = lessons[i];
                  final r = recordMap[l.id];
                  final confirmed = r != null;
                  final present2 = r?.present ?? false;
                  final justified = r?.justification != null;

                  Color statusColor;
                  IconData statusIcon;
                  String statusText;
                  if (!confirmed) {
                    statusColor = kTextDim;
                    statusIcon = Icons.schedule;
                    statusText = 'Non registrata';
                  } else if (present2) {
                    statusColor = kAccent;
                    statusIcon = Icons.check_circle;
                    statusText = 'Presente';
                  } else if (justified) {
                    statusColor = kWarning;
                    statusIcon = Icons.warning_amber;
                    statusText = 'Giustificata';
                  } else {
                    statusColor = kError;
                    statusIcon = Icons.cancel;
                    statusText = 'Assente';
                  }

                  return Card(
                    color: kCard,
                    margin: const EdgeInsets.only(bottom: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    child: ListTile(
                      dense: true,
                      leading: Icon(statusIcon, color: statusColor, size: 20),
                      title: Text('M${l.moduleNumber} ${l.topic}',
                          style: const TextStyle(color: kText, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(DateFormat('dd/MM/yyyy').format(l.date),
                          style: const TextStyle(color: kTextDim, fontSize: 11)),
                      trailing: Text(statusText, style: TextStyle(color: statusColor, fontSize: 11)),
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

  Widget _stat(String value, String label, Color color) => Column(
    children: [
      Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: kTextDim, fontSize: 11)),
    ],
  );
}
