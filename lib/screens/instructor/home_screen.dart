import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/schedule_models.dart';
import '../../models/user_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/course_service.dart';
import '../../services/grade_service.dart';
import '../../services/notification_service.dart';
import '../../services/reference_service.dart';
import '../../services/schedule_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';
import '../../widgets/collapsible_day.dart';
import '../../widgets/lesson_tile.dart';
import '../../widgets/status_card.dart';

/// Home istruttore: le due currency in alto (al tocco lo storico), la giornata
/// con la registrazione presenze, poi le prossime lezioni a giorni collassati.
class InstructorHomeScreen extends ConsumerStatefulWidget {
  final String userId;
  const InstructorHomeScreen({super.key, required this.userId});

  @override
  ConsumerState<InstructorHomeScreen> createState() => _InstructorHomeScreenState();
}

class _InstructorHomeScreenState extends ConsumerState<InstructorHomeScreen> {
  final _scheduleService = ScheduleService();
  final _attendanceService = AttendanceService();
  final _courseService = CourseService();
  final _userService = UserService();
  final _gradeService = GradeService();
  final _notifService = NotificationService();
  final _refService = ReferenceService();
  List<ScheduledLesson> _today = [];
  List<ScheduledLesson> _upcoming = [];
  List<SlotNote> _notes = [];
  Set<String>? _open; // giorni espansi (yyyy-MM-dd)

  @override
  void initState() {
    super.initState();
    _generateDayBeforeReminders();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute.isCurrentOf(context); // ricarica anche al ritorno da uno storico
    _load();
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
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    setState(() {
      _today = _scheduleService.getLessonsRelevantForInstructorToday(widget.userId);
      _upcoming = _scheduleService
          .getAllRelevantLessonsForInstructor(widget.userId)
          .where((l) => !l.date.isBefore(tomorrow))
          .toList();
      _notes = _courseService
          .getCoursesForInstructor(widget.userId)
          .expand((c) => _scheduleService.getNotesForCourse(c.id))
          .where((n) => !n.date.isBefore(DateTime(now.year, now.month, now.day)))
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
                      title: Text(a.fullName, style: const TextStyle(color: kText)),
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
    final uid = widget.userId;
    final teachH = _gradeService.getConfirmedLessonHoursRollingYear(uid) +
        _gradeService.getManualTeachingHoursRollingYear(uid);
    final profH = _gradeService.getProfessionalUpdateHoursLast2Years(uid);
    final me = _userService.findById(uid);
    final daaExpiry = me?.daaExpiry;
    final grace = me == null ? (teach: false, prof: false) : _gradeService.ojtGrace(me);
    final daaOk = daaExpiry == null || (me?.goOverride ?? false) || daaExpiry.isAfter(DateTime.now());

    final describer = LessonDescriber([..._today, ..._upcoming]);
    final dayKey = DateFormat('yyyy-MM-dd');
    final todayKey = dayKey.format(DateTime.now());
    final notesByDate = <String, List<SlotNote>>{};
    for (final n in _notes) {
      notesByDate.putIfAbsent(dayKey.format(n.date), () => []).add(n);
    }
    final byDate = <String, List<ScheduledLesson>>{};
    for (final l in _upcoming) {
      byDate.putIfAbsent(dayKey.format(l.date), () => []).add(l);
    }
    for (final g in byDate.values) {
      g.sort((a, b) => a.timeSlot.compareTo(b.timeSlot));
    }
    final dates = {...byDate.keys, ...notesByDate.keys.where((d) => d != todayKey)}.toList()..sort();
    // Aperto all'avvio solo il primo giorno, gli altri al tap.
    final open = _open ??= {if (dates.isNotEmpty) dates.first};
    final todayNotes = notesByDate[todayKey] ?? [];

    final sectionStyle = Theme.of(context)
        .textTheme
        .titleLarge
        ?.copyWith(color: kText, fontWeight: FontWeight.w700, letterSpacing: -0.3);

    String fmt(double h) => h == h.roundToDouble() ? h.toStringAsFixed(0) : h.toStringAsFixed(1);

    Widget currency(String title, String subtitle, double hours, double required, bool ok, String route) =>
        StatusCard(
          title: title,
          subtitle: subtitle,
          value: '${fmt(hours)} h',
          badge: ok ? 'GO' : 'NO GO',
          footer: ok ? 'Minimo ${fmt(required)} h' : 'Mancano ${fmt(required - hours)} h',
          color: ok ? kAccent : kError,
          onTap: () => context.go(route),
        );

    return RefreshIndicator(
      onRefresh: _reload,
      color: kPrimary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text('Currency', style: sectionStyle),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: currency('Insegnamento', 'Ultimi 365 giorni', teachH, 6,
                      teachH >= 6 || grace.teach, '/instructor/insegnamento'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: currency('Aggiornamento', 'Ultimi 2 anni', profH, 35,
                      profH >= 35 || grace.prof, '/instructor/aggiornamenti'),
                ),
              ],
            ),
          ),
          if (daaExpiry != null) ...[
            const SizedBox(height: 12),
            _daaCard(daaExpiry, daaOk),
          ],
          if (me != null && (me.goOverride || me.currencyLostAt != null || me.ojtKind != null)) ...[
            const SizedBox(height: 12),
            _serviceStatusCard(me),
          ],
          const SizedBox(height: 28),
          Text('Oggi', style: sectionStyle),
          Text(DateFormat('EEEE d MMMM', 'it').format(DateTime.now()),
              style: const TextStyle(color: kTextDim, fontSize: 13)),
          const SizedBox(height: 12),
          if (todayNotes.isNotEmpty) _notesBox(todayNotes),
          if (_today.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Nessuna lezione oggi', style: TextStyle(color: kTextDim)),
            )
          else
            for (final l in _today)
              describer.tile(
                l,
                action: l.confirmed
                    ? null
                    : ElevatedButton.icon(
                        onPressed: () => _confirmLesson(l),
                        icon: const Icon(Icons.how_to_reg, size: 16),
                        label: const Text('Registra presenze'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
              ),
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
                accent: kPrimary,
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

  Widget _serviceStatusCard(AppUser me) {
    final ojt = me.ojtSummary;
    return Card(
      color: kCard,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: (me.goOverride ? kWarning : kError).withOpacity(0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Stato di servizio',
                style: TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (me.currencyLostAt != null)
              Text(
                'Perdita currency: ${DateFormat('dd/MM/yyyy').format(me.currencyLostAt!)}',
                style: const TextStyle(color: kError, fontSize: 12),
              ),
            if (ojt != null) ...[
              if (me.currencyLostAt != null) const SizedBox(height: 4),
              Text(
                '$ojt${me.goOverride ? ' (GO attivo)' : ''}',
                style: const TextStyle(color: kWarning, fontSize: 12),
              ),
              if (me.ojtNote?.trim().isNotEmpty == true)
                Text(me.ojtNote!,
                    style: const TextStyle(color: kTextDim, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _daaCard(DateTime expiry, bool ok) {
    final color = ok ? kAccent : kError;
    return Card(
      color: kCard,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.verified_user, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Aggiornamento biennale DAAA (M10)',
                  style: TextStyle(color: kText, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                'Scade: ${DateFormat('dd/MM/yyyy').format(expiry)}',
                style: TextStyle(color: color, fontSize: 12),
              ),
            ],
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              ok ? 'GO' : 'SCADUTA',
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ]),
      ),
    );
  }
}
