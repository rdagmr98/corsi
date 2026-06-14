import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/schedule_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/course_service.dart';
import '../../services/reference_service.dart';
import '../../services/schedule_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';

class InstructorTodayScreen extends ConsumerStatefulWidget {
  final String userId;
  const InstructorTodayScreen({super.key, required this.userId});

  @override
  ConsumerState<InstructorTodayScreen> createState() => _InstructorTodayScreenState();
}

class _InstructorTodayScreenState extends ConsumerState<InstructorTodayScreen> {
  final _scheduleService = ScheduleService();
  final _attendanceService = AttendanceService();
  final _courseService = CourseService();
  final _userService = UserService();
  final _refService = ReferenceService();
  List<ScheduledLesson> _todayLessons = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _todayLessons = _scheduleService.getLessonsRelevantForInstructorToday(widget.userId);
    });
  }

  Future<void> _reload() async {
    await ref.read(authProvider).reloadDb();
    _load();
  }

  Future<void> _confirmLesson(ScheduledLesson lesson) async {
    final course = _courseService.findById(lesson.courseId);
    if (course == null) return;
    final attendees = _userService.getAllUsers()
        .where((u) => course.attendeeIds.contains(u.id))
        .toList();

    final presence = <String, bool>{
      for (final a in attendees) a.id: true,
    };

    await showModalBottomSheet(
      context: context,
      backgroundColor: kCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scroll) => Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kTextDim,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Conferma presenza', style: Theme.of(context).textTheme.titleMedium),
                    Text(lesson.topic, style: const TextStyle(color: kTextDim, fontSize: 13)),
                  ],
                ),
              ),
              const Divider(color: kBorder),
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  itemCount: attendees.length,
                  itemBuilder: (_, i) {
                    final a = attendees[i];
                    final present = presence[a.id] ?? true;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: present ? kAccent.withOpacity(0.15) : kError.withOpacity(0.15),
                        child: Text(
                          a.cognome.isNotEmpty ? a.cognome[0] : '?',
                          style: TextStyle(color: present ? kAccent : kError),
                        ),
                      ),
                      title: Text(a.fullName, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kText)),
                      trailing: Switch(
                        value: present,
                        activeColor: kAccent,
                        onChanged: (v) => setSheet(() => presence[a.id] = v),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _attendanceService.saveAttendance(
                        scheduleId: lesson.id,
                        courseId: lesson.courseId,
                        attendeeIds: attendees.map((a) => a.id).toList(),
                        presence: presence,
                        confirmedBy: widget.userId,
                      );
                      await _scheduleService.confirmLesson(lesson.id, widget.userId);
                      _reload();
                    },
                    child: const Text('Conferma presenze'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return RefreshIndicator(
      onRefresh: _reload,
      color: kPrimary,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Text(
                DateFormat('EEEE d MMMM yyyy', 'it').format(today),
                style: const TextStyle(color: kTextDim, fontSize: 13),
              ),
            ),
          ),
          if (_todayLessons.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline, color: kAccent, size: 48),
                    SizedBox(height: 12),
                    Text('Nessuna lezione oggi', style: TextStyle(color: kTextDim)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final lesson = _todayLessons[i];
                    final isTheory = lesson.isTheory;
                    final color = isTheory ? kPrimary : kAccent;
                    final course = _courseService.findById(lesson.courseId);

                    return Card(
                      color: kCard,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: lesson.confirmed ? kAccent.withOpacity(0.4) : color.withOpacity(0.3),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isTheory ? 'TEORIA' : 'PRATICA',
                                    style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('M${_refService.moduleLabel(lesson.moduleNumber)}', style: const TextStyle(color: kTextDim, fontSize: 12)),
                                if (lesson.taskId != null) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: kAccent.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('Task ${lesson.taskId}',
                                        style: const TextStyle(color: kAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                                const Spacer(),
                                Text('${lesson.timeSlot}ª ora', style: const TextStyle(color: kTextDim, fontSize: 12)),
                                if (lesson.confirmed)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 6),
                                    child: Icon(Icons.check_circle, color: kAccent, size: 16),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(lesson.topic, style: const TextStyle(color: kText, fontWeight: FontWeight.w500)),
                            if (course != null) ...[
                              const SizedBox(height: 4),
                              Text(course.title, style: const TextStyle(color: kTextDim, fontSize: 12)),
                            ],
                            if (!lesson.confirmed) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => _confirmLesson(lesson),
                                  icon: const Icon(Icons.how_to_reg, size: 16),
                                  label: const Text('Registra presenze'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: color,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: _todayLessons.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
