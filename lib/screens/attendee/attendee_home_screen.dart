import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
import '../../models/schedule_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/course_service.dart';
import '../../services/grade_service.dart';
import '../../services/reference_service.dart';
import '../../services/schedule_service.dart';
import '../../theme.dart';
import '../../widgets/collapsible_day.dart';
import '../../widgets/lesson_tile.dart';
import '../../widgets/status_card.dart';
import 'attendee_attendance_screen.dart';
import 'attendee_grades_screen.dart';

/// Home frequentatore come quella istruttore (modello AVES Tecnici): presenze
/// e voti in alto (al tocco il dettaglio), la giornata, poi le prossime
/// lezioni a giorni collassati.
class AttendeeHomeScreen extends ConsumerStatefulWidget {
  final String userId;
  const AttendeeHomeScreen({super.key, required this.userId});

  @override
  ConsumerState<AttendeeHomeScreen> createState() => _AttendeeHomeScreenState();
}

class _AttendeeHomeScreenState extends ConsumerState<AttendeeHomeScreen> {
  final _courseService = CourseService();
  final _scheduleService = ScheduleService();
  final _attendanceService = AttendanceService();
  final _gradeService = GradeService();
  final _refService = ReferenceService();

  List<Course> _courses = [];
  Course? _selected;
  Set<String>? _open; // giorni espansi (yyyy-MM-dd)

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _courses = _courseService.getCoursesForAttendee(widget.userId);
      _selected = _courses.where((c) => c.id == _selected?.id).firstOrNull ?? _courses.firstOrNull;
    });
  }

  Future<void> _reload() async {
    await ref.read(authProvider).reloadDb();
    _load();
  }

  Future<void> _push(String title, Widget body) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(backgroundColor: kSurface, title: Text(title)),
        body: body,
      ),
    ));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final course = _selected;
    if (course == null) {
      return const Center(child: Text('Nessun corso attivo', style: TextStyle(color: kTextDim)));
    }
    final uid = widget.userId;
    final lessons = _scheduleService.getLessonsForCourse(course.id);
    final type = _refService.getEffectiveCourseType(course.courseTypeId, course.extensionTypeId, course.mamlCombinationId);

    // Stessi conti delle pagine Presenze e Voti.
    final stats = _attendanceService.computePerModuleStats(course.id, uid, lessons, modules: type?.modules);
    final confirmed = stats.values.fold(0, (s, m) => s + (m['confirmed'] ?? 0));
    final planned = type?.modules.fold<int>(0, (s, m) => s + m.totalHours) ?? confirmed;
    final completion = planned > 0 ? confirmed.clamp(0, planned) / planned : 0.0;
    final toRecover = stats.values.fold(0, (s, m) => s + (m['toRecover'] ?? 0));
    final hasGrades = _gradeService.getAttendeeSummary(course.id, uid).values.any((s) => s.hasGrades);
    final avg = _gradeService.getGraduationScore(course.id, uid);
    final rank = _gradeService
            .getCourseRanking(course.id, course.attendeeIds)
            .where((r) => r.attendeeId == uid)
            .firstOrNull
            ?.rank ??
        0;
    final gradeColor = !hasGrades ? kPrimary : (avg >= 22.5 ? kAccent : kError);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dayKey = DateFormat('yyyy-MM-dd');
    final todayKey = dayKey.format(today);
    final upcoming = lessons.where((l) => !l.date.isBefore(today)).toList();
    final describer = LessonDescriber(upcoming);
    final byDate = <String, List<ScheduledLesson>>{};
    for (final l in upcoming) {
      byDate.putIfAbsent(dayKey.format(l.date), () => []).add(l);
    }
    for (final g in byDate.values) {
      g.sort((a, b) => a.timeSlot.compareTo(b.timeSlot));
    }
    final notesByDate = <String, List<SlotNote>>{};
    for (final n in _scheduleService.getNotesForCourse(course.id).where((n) => !n.date.isBefore(today))) {
      notesByDate.putIfAbsent(dayKey.format(n.date), () => []).add(n);
    }
    final todayLessons = byDate[todayKey] ?? [];
    final todayNotes = notesByDate[todayKey] ?? [];
    final dates = {...byDate.keys, ...notesByDate.keys}.where((d) => d != todayKey).toList()..sort();
    // Aperto all'avvio solo il primo giorno, gli altri al tap.
    final open = _open ??= {if (dates.isNotEmpty) dates.first};

    final sectionStyle = Theme.of(context)
        .textTheme
        .titleLarge
        ?.copyWith(color: kText, fontWeight: FontWeight.w700, letterSpacing: -0.3);

    return RefreshIndicator(
      onRefresh: _reload,
      color: kWarning,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (_courses.length > 1) ...[
            DropdownButton<String>(
              value: course.id,
              dropdownColor: kSurface,
              style: const TextStyle(color: kText),
              isExpanded: true,
              underline: const SizedBox(),
              items: _courses
                  .map((c) => DropdownMenuItem(
                      value: c.id, child: Text(c.title, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (id) => setState(() {
                _selected = _courses.firstWhere((c) => c.id == id);
                _open = null;
              }),
            ),
            const SizedBox(height: 8),
          ],
          Text('Situazione', style: sectionStyle),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: StatusCard(
                    title: 'Presenze',
                    subtitle: 'Corso completato',
                    value: '${(completion * 100).round()}%',
                    progress: completion,
                    footer: toRecover > 0 ? 'Da recuperare: $toRecover h' : 'Niente da recuperare',
                    color: toRecover > 0 ? kError : kAccent,
                    onTap: () => _push('Presenze', AttendeeAttendanceScreen(userId: uid, courseId: course.id)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatusCard(
                    title: 'Voti',
                    subtitle: 'Media graduatoria',
                    value: hasGrades ? avg.toStringAsFixed(2) : '—',
                    progress: hasGrades ? avg / 30 : 0,
                    footer: hasGrades && rank > 0
                        ? 'Posizione $rank° / ${course.attendeeIds.length}'
                        : 'Nessun voto',
                    color: gradeColor,
                    onTap: () => _push('Voti', AttendeeGradesScreen(userId: uid, courseId: course.id)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text('Oggi', style: sectionStyle),
          Text(DateFormat('EEEE d MMMM', 'it').format(now),
              style: const TextStyle(color: kTextDim, fontSize: 13)),
          const SizedBox(height: 12),
          if (todayNotes.isNotEmpty) _notesBox(todayNotes),
          if (todayLessons.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Nessuna lezione oggi', style: TextStyle(color: kTextDim)),
            )
          else
            for (final l in todayLessons) describer.tile(l),
          const SizedBox(height: 28),
          Text('Prossime lezioni', style: sectionStyle),
          const SizedBox(height: 12),
          if (dates.isEmpty)
            const Text('Nessuna lezione programmata', style: TextStyle(color: kTextDim))
          else
            for (final d in dates)
              CollapsibleDay(
                date: DateTime.parse(d),
                isToday: false,
                accent: kWarning,
                summary: _summary(byDate[d] ?? []),
                hasNotes: notesByDate[d]?.isNotEmpty ?? false,
                expanded: open.contains(d),
                onToggle: () => setState(() {
                  if (!open.remove(d)) open.add(d);
                }),
                children: [
                  if (notesByDate[d] != null) _notesBox(notesByDate[d]!),
                  for (final l in byDate[d] ?? <ScheduledLesson>[]) describer.tile(l),
                ],
              ),
        ],
      ),
    );
  }

  String _summary(List<ScheduledLesson> lessons) {
    if (lessons.isEmpty) return '';
    final modules = lessons.map((l) => 'M${_refService.moduleLabel(l.moduleNumber)}').toSet();
    return '${lessons.length} ${lessons.length == 1 ? 'ora' : 'ore'} · ${modules.join(' · ')}';
  }

  Widget _notesBox(List<SlotNote> notes) => Container(
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
              child: Text(notes.map((n) => n.text).join(' · '),
                  style: const TextStyle(color: kWarning, fontSize: 12)),
            ),
          ],
        ),
      );
}
