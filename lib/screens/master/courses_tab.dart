import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
import '../../models/user_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/course_service.dart';
import '../../services/grade_service.dart';
import '../../services/pdf_export_service.dart';
import '../../services/reference_service.dart';
import '../../services/schedule_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';
import 'course_detail_screen.dart';

class CoursesTab extends ConsumerStatefulWidget {
  const CoursesTab({super.key});

  @override
  ConsumerState<CoursesTab> createState() => _CoursesTabState();
}

class _CoursesTabState extends ConsumerState<CoursesTab> {
  final _courseService = CourseService();
  final _refService = ReferenceService();
  final _userService = UserService();
  final _scheduleService = ScheduleService();
  final _gradeService = GradeService();
  final _attendanceService = AttendanceService();
  List<Course> _courses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _courses = _courseService.getAllCourses();
      _loading = false;
    });
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    await ref.read(authProvider).reloadDb();
    _load();
  }

  Color _statusColor(CourseStatus s) => switch (s) {
    CourseStatus.planning => kWarning,
    CourseStatus.active => kAccent,
    CourseStatus.completed => kPrimary,
    CourseStatus.archived => kTextDim,
  };

  Future<void> _showCourseDialog({Course? course}) async {
    final courseTypes = _refService.getCourseTypes();
    final users = _userService.getAllUsers();
    final existingDirectors = users.where((u) => u.userRole == UserRole.courseDirector).toList();
    final instructors = users.where((u) => u.userRole == UserRole.instructor).toList();
    final attendees = users.where((u) => u.userRole == UserRole.attendee).toList();
    final isNew = course == null;

    String? selectedType = course?.courseTypeId ?? (courseTypes.isNotEmpty ? courseTypes.first.id : null);
    final titleCtrl     = TextEditingController(text: course?.title ?? '');
    DateTime? startDate = course?.startDate;
    Set<String> selectedDirectors  = Set.from(course?.directorIds ?? []);
    Set<String> selectedInstructors = Set.from(course?.instructorIds ?? []);
    Set<String> selectedAttendees  = Set.from(course?.attendeeIds ?? []);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: kCard,
          title: Text(isNew ? 'Nuovo Corso' : 'Modifica Corso',
              style: const TextStyle(color: kText)),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Tipo corso'),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    dropdownColor: kSurface,
                    style: const TextStyle(color: kText),
                    decoration: const InputDecoration(isDense: true),
                    items: courseTypes
                        .map((t) => DropdownMenuItem(value: t.id, child: Text(t.code)))
                        .toList(),
                    onChanged: (v) => setDlg(() => selectedType = v),
                  ),
                  const SizedBox(height: 12),
                  _label('Titolo'),
                  TextField(
                    controller: titleCtrl,
                    style: const TextStyle(color: kText),
                    decoration: const InputDecoration(isDense: true, hintText: 'es. 4° BTC'),
                  ),
                  const SizedBox(height: 12),
                  _label('Data inizio'),
                  Row(
                    children: [
                      Text(
                        startDate != null
                            ? DateFormat('dd/MM/yyyy').format(startDate!)
                            : 'Non impostata',
                        style: const TextStyle(color: kText),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: startDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (d != null) setDlg(() => startDate = d);
                        },
                        child: const Text('Scegli'),
                      ),
                    ],
                  ),
                  const Divider(color: kBorder, height: 28),
                  // ── DIRETTORE ───────────────────────────────────────────
                  _label('Direttore del corso'),
                  if (existingDirectors.isEmpty)
                    const Text(
                      'Nessun direttore disponibile. Crea prima un utente con ruolo "Direttore corso" dalla scheda Utenti.',
                      style: TextStyle(color: kWarning, fontSize: 11),
                    )
                  else
                    _multiSelect(existingDirectors, selectedDirectors, setDlg),
                  const Divider(color: kBorder, height: 28),
                  _label('Istruttori'),
                  _multiSelect(instructors, selectedInstructors, setDlg),
                  const SizedBox(height: 12),
                  _label('Frequentatori'),
                  _multiSelect(attendees, selectedAttendees, setDlg),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla', style: TextStyle(color: kTextDim)),
            ),
            ElevatedButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty || selectedType == null) return;
                final masterId = ref.read(authProvider).currentUser?.id ?? '';

                Navigator.pop(ctx);
                if (isNew) {
                  await _courseService.createCourse(
                    courseTypeId: selectedType!,
                    title: title,
                    createdBy: masterId,
                    startDate: startDate,
                    directorIds: selectedDirectors.toList(),
                    instructorIds: selectedInstructors.toList(),
                    attendeeIds: selectedAttendees.toList(),
                  );
                } else {
                  await _courseService.updateCourse(course!.copyWith(
                    courseTypeId: selectedType,
                    title: title,
                    startDate: startDate,
                    directorIds: selectedDirectors.toList(),
                    instructorIds: selectedInstructors.toList(),
                    attendeeIds: selectedAttendees.toList(),
                  ));
                }
                _reload();
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: const TextStyle(color: kTextDim, fontSize: 12)),
  );

  Widget _multiSelect(List<AppUser> users, Set<String> selected, StateSetter setDlg) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: users.map((u) {
        final sel = selected.contains(u.id);
        return FilterChip(
          label: Text(u.fullName, style: TextStyle(color: sel ? Colors.white : kTextDim, fontSize: 11)),
          selected: sel,
          selectedColor: kPrimary,
          backgroundColor: kSurface,
          checkmarkColor: Colors.white,
          onSelected: (v) => setDlg(() {
            if (v) selected.add(u.id); else selected.remove(u.id);
          }),
        );
      }).toList(),
    );
  }

  Future<void> _deleteCourse(Course c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Elimina corso', style: TextStyle(color: kText)),
        content: Text('Eliminare "${c.title}"?', style: const TextStyle(color: kTextDim)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kError),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _courseService.deleteCourse(c.id);
      _reload();
    }
  }

  Future<void> _extendCourse(Course c) async {
    final extId = c.courseTypeId == 'b1' ? 'b1mil' : 'b2mil';
    final milType = _refService.getCourseType(extId);
    if (milType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tipo $extId non trovato in reference.json'), backgroundColor: kError),
      );
      return;
    }
    final modCodes = milType.modules.map((m) => 'M${m.displayCode}').join(', ');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: Text('Estendi ${c.courseTypeId.toUpperCase()} con moduli MIL',
            style: const TextStyle(color: kText)),
        content: Text(
          'Verranno aggiunti al programma i moduli militari: $modCodes '
          '(${milType.totalHours}h totali).\n\nQuesti moduli compariranno nel calendario, '
          'nelle presenze e nei voti.',
          style: const TextStyle(color: kTextDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla', style: TextStyle(color: kTextDim)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Estendi'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _courseService.updateCourse(c.copyWith(extensionTypeId: extId));
    _reload();
  }

  Future<void> _changeStatus(Course c, String newStatus) async {
    if (newStatus == 'archived') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A2A3A),
          title: const Text('Archivia corso', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Verrà generato e scaricato il PDF con tutti i dati probanti del corso.\n\n'
            'Gli account dei frequentatori del corso verranno eliminati '
            '(esclusi quelli iscritti ad altri corsi non archiviati).\n\nProcedere?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Archivia e scarica PDF'),
            ),
          ],
        ),
      );
      if (confirm != true) return;

      final typeInfo = _refService.getEffectiveCourseType(c.courseTypeId, c.extensionTypeId);
      final lessons = _scheduleService.getLessonsForCourse(c.id);
      final allUsers = _userService.getAllUsers();
      final attendees = allUsers.where((u) => c.attendeeIds.contains(u.id)).toList();
      final instructors = allUsers.where((u) => c.instructorIds.contains(u.id)).toList();

      try {
        await PdfExportService.downloadCourseReport(
          course: c,
          typeInfo: typeInfo,
          lessons: lessons,
          attendees: attendees,
          instructors: instructors,
          gradeService: _gradeService,
          attendanceService: _attendanceService,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Errore generazione PDF: $e'),
              backgroundColor: kError,
            ),
          );
        }
        return;
      }
    }

    if (newStatus == 'active') await _courseService.activateCourse(c.id);
    else if (newStatus == 'completed') await _courseService.completeCourse(c.id);
    else await _courseService.updateCourse(c.copyWith(status: newStatus));

    if (newStatus == 'archived') await _deleteArchivedAttendees(c);
    _reload();
  }

  // Elimina gli account dei frequentatori di un corso archiviato,
  // tranne quelli ancora iscritti ad altri corsi non archiviati.
  Future<void> _deleteArchivedAttendees(Course c) async {
    final otherCourses =
        _courseService.getAllCourses().where((o) => o.id != c.id && o.status != 'archived');
    final stillEnrolled = <String>{
      for (final o in otherCourses) ...o.attendeeIds,
    };
    final toDelete = c.attendeeIds.where((id) => !stillEnrolled.contains(id)).toList();
    await _userService.deleteUsers(toDelete);
    if (toDelete.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Eliminati ${toDelete.length} account frequentatori'),
          backgroundColor: kAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: kPrimary));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(
            children: [
              Text('Corsi', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, color: kTextDim),
                onPressed: _reload,
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _showCourseDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuovo corso'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _courses.isEmpty
              ? const Center(child: Text('Nessun corso', style: TextStyle(color: kTextDim)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _courses.length,
                  itemBuilder: (_, i) {
                    final c = _courses[i];
                    final typeInfo = _refService.getEffectiveCourseType(c.courseTypeId, c.extensionTypeId);
                    final color = _statusColor(c.courseStatus);
                    return Card(
                      color: kCard,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: color.withOpacity(0.3)),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => showDialog(
                          context: context,
                          barrierDismissible: true,
                          builder: (_) => MasterCourseDetailScreen(course: c),
                        ),
                        child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          width: 4,
                          height: 40,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        title: Row(
                          children: [
                            Flexible(child: Text(c.title, style: const TextStyle(color: kText, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 8),
                            if (typeInfo != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: kPrimary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(typeInfo.code, style: const TextStyle(color: kPrimary, fontSize: 10)),
                              ),
                            if (c.extensionTypeId != null) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: kWarning.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('+MIL', style: TextStyle(color: kWarning, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(c.courseStatus.label, style: TextStyle(color: color, fontSize: 11)),
                            ),
                            const SizedBox(width: 8),
                            Flexible(child: Text(
                              c.startDate != null
                                  ? 'Inizio: ${DateFormat('dd/MM/yyyy').format(c.startDate!)}'
                                  : 'Data da definire',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: kTextDim, fontSize: 12),
                            )),
                            const SizedBox(width: 8),
                            Text(
                              '${c.attendeeIds.length} freq. · ${c.instructorIds.length} istr.',
                              style: const TextStyle(color: kTextDim, fontSize: 12),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PopupMenuButton<String>(
                              color: kSurface,
                              tooltip: 'Cambia stato',
                              icon: const Icon(Icons.swap_horiz, color: kTextDim, size: 20),
                              onSelected: (s) => _changeStatus(c, s),
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'planning', child: Text('Pianificazione', style: TextStyle(color: kText))),
                                const PopupMenuItem(value: 'active', child: Text('Attiva', style: TextStyle(color: kText))),
                                const PopupMenuItem(value: 'completed', child: Text('Completato', style: TextStyle(color: kText))),
                                const PopupMenuItem(value: 'archived', child: Text('Archiviato', style: TextStyle(color: kText))),
                              ],
                            ),
                            if (c.extensionTypeId == null && (c.courseTypeId == 'b1' || c.courseTypeId == 'b2'))
                              IconButton(
                                icon: const Icon(Icons.military_tech_outlined, color: kWarning, size: 20),
                                tooltip: 'Estendi con moduli MIL',
                                onPressed: () => _extendCourse(c),
                              ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: kTextDim, size: 20),
                              onPressed: () => _showCourseDialog(course: c),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: kError, size: 20),
                              onPressed: () => _deleteCourse(c),
                            ),
                          ],
                        ),
                      ), // ListTile
                      ), // InkWell
                    );
                  },
                ),
        ),
      ],
    );
  }
}
