import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/course_service.dart';
import '../../services/schedule_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';

class DirectorAttendanceTab extends ConsumerStatefulWidget {
  final String userId;
  const DirectorAttendanceTab({super.key, required this.userId});

  @override
  ConsumerState<DirectorAttendanceTab> createState() => _DirectorAttendanceTabState();
}

class _DirectorAttendanceTabState extends ConsumerState<DirectorAttendanceTab> {
  final _courseService = CourseService();
  final _scheduleService = ScheduleService();
  final _attendanceService = AttendanceService();
  final _userService = UserService();

  List<Course> _courses = [];
  Course? _selected;

  @override
  void initState() {
    super.initState();
    _load();
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

    final attendees = _userService.getAllUsers()
        .where((u) => course.attendeeIds.contains(u.id))
        .toList();

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
        const SizedBox(height: 16),
        Expanded(
          child: attendees.isEmpty
              ? const Center(child: Text('Nessun frequentatore', style: TextStyle(color: kTextDim)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: attendees.length,
                  itemBuilder: (_, i) {
                    final a = attendees[i];
                    final absStats = _attendanceService.computeAbsences(course.id, a.id);
                    final total = absStats['total'] ?? 0;
                    final absent = absStats['absent'] ?? 0;
                    final unjustified = absStats['unjustified'] ?? 0;
                    final pct = total > 0 ? (absent / total * 100) : 0.0;
                    final warn = pct > 25;

                    return Card(
                      color: kCard,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: warn ? kError.withOpacity(0.3) : kBorder),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: warn ? kError.withOpacity(0.15) : kPrimary.withOpacity(0.15),
                          child: Text(
                            a.cognome.isNotEmpty ? a.cognome[0] : '?',
                            style: TextStyle(
                              color: warn ? kError : kPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(a.fullName, style: const TextStyle(color: kText, fontWeight: FontWeight.w500)),
                        subtitle: Text(
                          '$absent assenze su $total lezioni (${pct.toStringAsFixed(0)}%) · $unjustified non giustificate',
                          style: TextStyle(color: warn ? kError : kTextDim, fontSize: 12),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.visibility_outlined, color: kTextDim, size: 20),
                          onPressed: () => _showDetail(course, a.id, a.fullName),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showDetail(Course course, String attendeeId, String name) {
    final lessons = _scheduleService.getLessonsForCourse(course.id);
    final records = _attendanceService.getRecordsForAttendee(course.id, attendeeId);
    final recordMap = {for (final r in records) r.scheduleId: r};

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: Text('Presenze: $name', style: const TextStyle(color: kText)),
        content: SizedBox(
          width: 500,
          height: 500,
          child: ListView.builder(
            itemCount: lessons.length,
            itemBuilder: (_, i) {
              final l = lessons[i];
              final r = recordMap[l.id];
              final present = r?.present;
              return ListTile(
                dense: true,
                leading: Icon(
                  present == null ? Icons.help_outline : (present ? Icons.check : Icons.close),
                  color: present == null ? kTextDim : (present ? kAccent : kError),
                  size: 18,
                ),
                title: Text('M${l.moduleNumber} ${l.topic}',
                    style: const TextStyle(color: kText, fontSize: 12)),
                subtitle: Text(
                  DateFormat('dd/MM/yyyy').format(l.date),
                  style: const TextStyle(color: kTextDim, fontSize: 11),
                ),
                trailing: r != null && !r.present && r.justification != null
                    ? const Text('giustificata', style: TextStyle(color: kWarning, fontSize: 10))
                    : null,
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Chiudi')),
        ],
      ),
    );
  }
}
