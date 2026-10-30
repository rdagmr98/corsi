import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/schedule_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/course_service.dart';
import '../../services/notification_service.dart';
import '../../services/reference_service.dart';
import '../../services/schedule_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';
import '../../widgets/mobile_ui.dart';

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
  final _notifService = NotificationService();
  List<ScheduledLesson> _todayLessons = [];
  List<SlotNote> _todayNotes = [];

  @override
  void initState() {
    super.initState();
    _load();
    _generateDayBeforeReminders();
  }

  Future<void> _generateDayBeforeReminders() async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final lessons = _scheduleService
        .getLessonsForInstructor(widget.userId)
        .where((l) =>
            !l.confirmed &&
            l.date.year == tomorrow.year &&
            l.date.month == tomorrow.month &&
            l.date.day == tomorrow.day)
        .toList();
    for (final l in lessons) {
      final course = _courseService.findById(l.courseId);
      await _notifService.notifyLessonReminder(
        instructorId: widget.userId,
        courseTitle: course?.title ?? '',
        dateLabel: DateFormat('dd/MM/yyyy').format(l.date),
        moduleLabel: l.topic.isNotEmpty ? l.topic : 'M${l.moduleNumber}',
      );
    }
  }

  void _load() {
    setState(() {
      _todayLessons = _scheduleService.getLessonsRelevantForInstructorToday(widget.userId);
      final today = DateTime.now();
      _todayNotes = _courseService.getCoursesForInstructor(widget.userId)
          .expand((c) => _scheduleService.getNotesForCourse(c.id))
          .where((n) => n.date.year == today.year &&
              n.date.month == today.month &&
              n.date.day == today.day)
          .toList();
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
                      // Cache già aggiornata: evita reloadDb (flush+re-fetch di tutti i JSON).
                      _load();
                      // Notifica in background — non blocca l'UI.
                      _notifService.notifyLessonValidated(
                        directorIds: course.directorIds,
                        instructorName: _userService.findById(widget.userId)?.fullName ?? widget.userId,
                        courseTitle: course.title,
                        dateLabel: DateFormat('dd/MM/yyyy').format(lesson.date),
                        moduleLabel: lesson.topic.isNotEmpty ? lesson.topic : 'M${lesson.moduleNumber}',
                      );
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
    final day = DateFormat('EEEE d MMMM yyyy', 'it').format(today);
    final toRegister = _todayLessons.where((l) => !l.confirmed).length;
    final count = _todayLessons.length;
    return RefreshIndicator(
      onRefresh: _reload,
      color: kPrimary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${day[0].toUpperCase()}${day.substring(1)}',
                      style: const TextStyle(
                          color: kText, fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    count == 0
                        ? 'Nessuna lezione in programma'
                        : '$count ${count == 1 ? 'lezione' : 'lezioni'} · '
                            '${toRegister == 0 ? 'tutte registrate' : '$toRegister da registrare'}',
                    style: TextStyle(
                        color: toRegister > 0 ? kWarning : kTextSoft, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          if (_todayLessons.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                _todayNotes.isEmpty ? Icons.check_circle_outline : Icons.event_busy,
                _todayNotes.isEmpty
                    ? 'Nessuna lezione oggi'
                    : 'Nessuna lezione: ${_todayNotes.map((n) => n.text).join(', ')}',
                color: kAccent,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final lesson = _todayLessons[i];
                    final isTheory = lesson.isTheory;
                    final color = isTheory ? kPrimary : kAccent;
                    final course = _courseService.findById(lesson.courseId);
                    final typeInfo = course == null
                        ? null
                        : _refService.getEffectiveCourseType(
                            course.courseTypeId, course.extensionTypeId, course.mamlCombinationId);
                    final task = lesson.taskId == null
                        ? null
                        : _refService.findTask(typeInfo, lesson.taskId);
                    final taskLabel = task != null
                        ? (task.name.isNotEmpty ? task.name : '${task.programTaskId}')
                        : lesson.taskId;
                    final slotTime = typeInfo?.schedule
                        .slotsForWeekday(lesson.date.weekday)
                        .where((t) => t.slot == lesson.timeSlot)
                        .firstOrNull;

                    return LessonCard(
                      color: moduleColor(lesson.moduleNumber),
                      slot: lesson.timeSlot,
                      isTheory: isTheory,
                      module: 'M${_refService.moduleLabel(lesson.moduleNumber)}',
                      topic: lesson.topic,
                      start: slotTime?.start,
                      end: slotTime?.end,
                      task: lesson.taskId == null ? null : '$taskLabel',
                      overline: course?.title,
                      confirmed: lesson.confirmed,
                      action: lesson.confirmed
                          ? null
                          : SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _confirmLesson(lesson),
                                icon: const Icon(Icons.how_to_reg, size: 18),
                                label: const Text('Registra presenze'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: color,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
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
