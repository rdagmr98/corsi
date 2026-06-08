import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
import '../../models/reference_models.dart';
import '../../models/schedule_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/course_service.dart';
import '../../services/reference_service.dart';
import '../../services/schedule_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';

class DirectorScheduleTab extends ConsumerStatefulWidget {
  final String userId;
  const DirectorScheduleTab({super.key, required this.userId});

  @override
  ConsumerState<DirectorScheduleTab> createState() => _DirectorScheduleTabState();
}

class _DirectorScheduleTabState extends ConsumerState<DirectorScheduleTab> {
  final _courseService = CourseService();
  final _refService = ReferenceService();
  final _scheduleService = ScheduleService();
  final _attendanceService = AttendanceService();
  final _userService = UserService();

  List<Course> _courses = [];
  Course? _selected;
  DateTime _weekStart = _mondayOf(DateTime.now());
  List<ScheduledLesson> _weekLessons = [];
  CourseTypeInfo? _typeInfo;

  static DateTime _mondayOf(DateTime d) {
    final diff = d.weekday - DateTime.monday;
    return DateTime(d.year, d.month, d.day - diff);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _courses = _courseService.getCoursesForDirector(widget.userId);
    if (_selected == null && _courses.isNotEmpty) _selected = _courses.first;
    _refreshWeek();
  }

  void _refreshWeek() {
    if (_selected == null) return;
    setState(() {
      _weekLessons = _scheduleService.getLessonsForWeek(_selected!.id, _weekStart);
      _typeInfo = _refService.getCourseType(_selected!.courseTypeId);
    });
  }

  Future<void> _reload() async {
    await ref.read(authProvider).reloadDb();
    _load();
  }

  void _prevWeek() {
    setState(() {
      _weekStart = _weekStart.subtract(const Duration(days: 7));
      _refreshWeek();
    });
  }

  void _nextWeek() {
    setState(() {
      _weekStart = _weekStart.add(const Duration(days: 7));
      _refreshWeek();
    });
  }

  Future<void> _generateRemaining() async {
    if (_selected == null || _typeInfo == null) return;
    final totalConfirmed = _scheduleService
        .getLessonsForCourse(_selected!.id)
        .where((l) => l.confirmed)
        .length;
    final hasRecovery = _attendanceService.courseHasAttendeesInRecovery(
      _selected!.id,
      _selected!.attendeeIds,
      totalConfirmed,
    );
    await _scheduleService.generateRemainingSchedule(
      courseId: _selected!.id,
      typeInfo: _typeInfo!,
      hasAttendeesInRecovery: hasRecovery,
      excludedDates: _selected!.excludedDates,
    );
    _reload();
  }

  Future<void> _addLesson(DateTime date, int slot) async {
    if (_selected == null || _typeInfo == null) return;
    final instructors = _userService.getInstructors()
        .where((u) => _selected!.instructorIds.contains(u.id))
        .toList();

    // Count confirmed hours per submodule to show only remaining lessons
    final doneLessons = _scheduleService
        .getLessonsForCourse(_selected!.id)
        .where((l) => l.confirmed)
        .toList();
    final doneT = <String, int>{};
    final doneP = <String, int>{};
    for (final l in doneLessons) {
      if (l.isTheory) doneT[l.submoduleCode] = (doneT[l.submoduleCode] ?? 0) + 1;
      else            doneP[l.submoduleCode] = (doneP[l.submoduleCode] ?? 0) + 1;
    }

    // Only offer modules/submodules with remaining hours
    final availableModules = _typeInfo!.modules.where((m) =>
        m.submodules.any((s) =>
            (s.theoryHours    - (doneT[s.code] ?? 0)) > 0 ||
            (s.practicalHours - (doneP[s.code] ?? 0)) > 0)
    ).toList();

    if (availableModules.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tutte le lezioni del corso sono già completate.')),
        );
      }
      return;
    }

    int? selectedModule = availableModules.first.number;
    String? selectedSubmodule;
    String type = 'teoria';
    String? selectedInstructor;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final module = selectedModule != null
              ? availableModules.firstWhere((m) => m.number == selectedModule,
                  orElse: () => availableModules.first)
              : null;

          final availableSubs = module?.submodules.where((s) =>
              (s.theoryHours    - (doneT[s.code] ?? 0)) > 0 ||
              (s.practicalHours - (doneP[s.code] ?? 0)) > 0).toList() ?? [];

          if (selectedSubmodule == null && availableSubs.isNotEmpty) {
            selectedSubmodule = availableSubs.first.code;
            // Auto-select type based on what's remaining
            final first = availableSubs.first;
            if ((first.theoryHours - (doneT[first.code] ?? 0)) <= 0) type = 'pratica';
            else type = 'teoria';
          }

          final selSub = availableSubs.firstWhere(
              (s) => s.code == selectedSubmodule,
              orElse: () => availableSubs.isNotEmpty ? availableSubs.first : module!.submodules.first);
          final remT = selSub.theoryHours    - (doneT[selSub.code] ?? 0);
          final remP = selSub.practicalHours - (doneP[selSub.code] ?? 0);

          return AlertDialog(
            backgroundColor: kCard,
            title: const Text('Aggiungi lezione', style: TextStyle(color: kText)),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(DateFormat('EEEE dd/MM/yyyy', 'it').format(date),
                      style: const TextStyle(color: kTextDim)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: selectedModule,
                    dropdownColor: kSurface,
                    style: const TextStyle(color: kText),
                    decoration: const InputDecoration(labelText: 'Modulo', isDense: true),
                    items: availableModules
                        .map((m) => DropdownMenuItem(
                              value: m.number,
                              child: Text('M${m.number} - ${m.name}',
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setDlg(() {
                      selectedModule = v;
                      selectedSubmodule = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  if (availableSubs.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: selectedSubmodule,
                      dropdownColor: kSurface,
                      style: const TextStyle(color: kText),
                      decoration: const InputDecoration(labelText: 'Sottomodulo', isDense: true),
                      items: availableSubs.map((s) {
                        final rT = s.theoryHours    - (doneT[s.code] ?? 0);
                        final rP = s.practicalHours - (doneP[s.code] ?? 0);
                        final tag = [if (rT > 0) '${rT}T', if (rP > 0) '${rP}P'].join(' ');
                        return DropdownMenuItem(
                          value: s.code,
                          child: Text('${s.code} - ${s.name}  ($tag)',
                              overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (v) => setDlg(() {
                        selectedSubmodule = v;
                        if (v != null) {
                          final s = availableSubs.firstWhere((x) => x.code == v);
                          type = (s.theoryHours - (doneT[v] ?? 0)) > 0 ? 'teoria' : 'pratica';
                        }
                      }),
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: type,
                    dropdownColor: kSurface,
                    style: const TextStyle(color: kText),
                    decoration: const InputDecoration(labelText: 'Tipo', isDense: true),
                    items: [
                      if (remT > 0)
                        const DropdownMenuItem(value: 'teoria', child: Text('Teoria')),
                      if (remP > 0)
                        const DropdownMenuItem(value: 'pratica', child: Text('Pratica')),
                    ],
                    onChanged: (v) => setDlg(() => type = v ?? type),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    value: selectedInstructor,
                    dropdownColor: kSurface,
                    style: const TextStyle(color: kText),
                    decoration: const InputDecoration(labelText: 'Istruttore', isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('— Da assegnare —')),
                      ...instructors.map(
                          (i) => DropdownMenuItem(value: i.id, child: Text(i.fullName))),
                    ],
                    onChanged: (v) => setDlg(() => selectedInstructor = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annulla', style: TextStyle(color: kTextDim)),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  if (selectedModule == null) return;
                  await _scheduleService.addLesson(
                    courseId: _selected!.id,
                    moduleNumber: selectedModule!,
                    submoduleCode: selectedSubmodule ?? '',
                    topic: selSub.name,
                    type: type,
                    date: date,
                    timeSlot: slot,
                    instructorId: selectedInstructor,
                  );
                  _reload();
                },
                child: const Text('Aggiungi'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showExcludedDates() async {
    if (_selected == null) return;
    final excluded = List<String>.from(_selected!.excludedDates)..sort();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: kCard,
          title: const Text('Giorni esclusi dalla pianificazione',
              style: TextStyle(color: kText, fontSize: 14)),
          content: SizedBox(
            width: 360,
            height: 380,
            child: Column(
              children: [
                const Text(
                  'Vacanze natalizie, pasquali, estive e festività.',
                  style: TextStyle(color: kTextDim, fontSize: 11),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2030),
                      builder: (context, child) => Theme(
                        data: ThemeData.dark(),
                        child: child!,
                      ),
                    );
                    if (d != null) {
                      final s =
                          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                      if (!excluded.contains(s)) {
                        setDlg(() { excluded.add(s); excluded.sort(); });
                      }
                    }
                  },
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Aggiungi giorno escluso', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: excluded.isEmpty
                      ? const Center(
                          child: Text('Nessun giorno escluso',
                              style: TextStyle(color: kTextDim, fontSize: 12)))
                      : ListView.builder(
                          itemCount: excluded.length,
                          itemBuilder: (_, i) {
                            final d = DateTime.tryParse(excluded[i]);
                            return ListTile(
                              dense: true,
                              title: Text(
                                d != null
                                    ? DateFormat('EEEE dd/MM/yyyy', 'it').format(d)
                                    : excluded[i],
                                style: const TextStyle(color: kText, fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: kError, size: 16),
                                onPressed: () => setDlg(() => excluded.removeAt(i)),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla', style: TextStyle(color: kTextDim)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final updated = _selected!.copyWith(excludedDates: excluded);
                await _courseService.updateCourse(updated);
                _load();
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteLesson(ScheduledLesson lesson) async {
    await _scheduleService.deleteLesson(lesson.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_courses.isEmpty) {
      return const Center(child: Text('Nessun corso assegnato', style: TextStyle(color: kTextDim)));
    }

    final weekDays = List.generate(5, (i) => _weekStart.add(Duration(days: i)));
    final allSlots = _typeInfo?.schedule.mondayThursday ?? [];
    // Controlla se ci sono lezioni di recupero nella settimana (slot 0)
    final recoveryLessons = _weekLessons.where((l) => l.timeSlot == 0).toList();
    final regularLessons = _weekLessons.where((l) => l.timeSlot > 0).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
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
                  onChanged: (id) {
                    setState(() => _selected = _courses.firstWhere((c) => c.id == id));
                    _refreshWeek();
                  },
                )
              else
                Text(_selected?.title ?? '', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: _prevWeek, color: kText),
              Text(
                '${DateFormat('dd/MM').format(_weekStart)} – ${DateFormat('dd/MM/yyyy').format(_weekStart.add(const Duration(days: 4)))}',
                style: const TextStyle(color: kText, fontSize: 13),
              ),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: _nextWeek, color: kText),
              const SizedBox(width: 8),
              if (_selected != null) ...[
                OutlinedButton.icon(
                  onPressed: _showExcludedDates,
                  icon: Icon(Icons.event_busy, size: 16,
                      color: _selected!.excludedDates.isNotEmpty ? kWarning : kTextDim),
                  label: Text(
                    'Giorni esclusi${_selected!.excludedDates.isNotEmpty ? ' (${_selected!.excludedDates.length})' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _generateRemaining,
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                  label: const Text('Genera lezioni rimanenti', style: TextStyle(fontSize: 12)),
                ),
              ],
              IconButton(icon: const Icon(Icons.refresh, color: kTextDim), onPressed: _reload),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Table(
                  border: TableBorder.all(color: kBorder, width: 0.5),
                  defaultColumnWidth: const FixedColumnWidth(160),
                  columnWidths: const {0: FixedColumnWidth(80)},
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: kSurface),
                      children: [
                        _headerCell('Ora'),
                        ...weekDays.map((d) => _headerCell(
                          DateFormat('EEE\ndd/MM', 'it').format(d),
                          highlight: _isToday(d),
                        )),
                      ],
                    ),
                    // Riga recupero (slot 0) — mostrata solo se esiste almeno un giorno con recupero
                    if (recoveryLessons.isNotEmpty)
                      TableRow(
                        decoration: BoxDecoration(color: kWarning.withOpacity(0.06)),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            child: const Column(
                              children: [
                                Icon(Icons.restore, color: kWarning, size: 12),
                                Text('Rec.', style: TextStyle(color: kWarning, fontSize: 9, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          ...weekDays.map((day) {
                            final rec = recoveryLessons
                                .where((l) => _sameDay(l.date, day))
                                .firstOrNull;
                            return TableCell(
                              child: rec != null
                                  ? Container(
                                      height: 50,
                                      margin: const EdgeInsets.all(2),
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: kWarning.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: kWarning.withOpacity(0.4)),
                                      ),
                                      child: const Text('Recupero', style: TextStyle(color: kWarning, fontSize: 10, fontWeight: FontWeight.bold)),
                                    )
                                  : const SizedBox(height: 50),
                            );
                          }),
                        ],
                      ),
                    ...allSlots.map((slot) {
                      final slotStr = '${slot.start}–${slot.end}';
                      return TableRow(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            child: Column(
                              children: [
                                Text('${slot.slot}ª', style: const TextStyle(color: kPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                                Text(slotStr, style: const TextStyle(color: kTextDim, fontSize: 9)),
                              ],
                            ),
                          ),
                          ...weekDays.map((day) {
                            if (day.weekday == DateTime.friday && slot.slot > 3) {
                              return const TableCell(
                                child: SizedBox(height: 70, child: Center(
                                  child: Text('—', style: TextStyle(color: kBorder)),
                                )),
                              );
                            }
                            final lesson = regularLessons
                                .where((l) => _sameDay(l.date, day) && l.timeSlot == slot.slot)
                                .firstOrNull;
                            return TableCell(
                              child: lesson == null
                                  ? InkWell(
                                      onTap: () => _addLesson(day, slot.slot),
                                      child: Container(
                                        height: 70,
                                        alignment: Alignment.center,
                                        child: const Icon(Icons.add, color: kBorder, size: 16),
                                      ),
                                    )
                                  : _lessonCell(lesson),
                            );
                          }),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerCell(String text, {bool highlight = false}) => Container(
    padding: const EdgeInsets.all(8),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: highlight ? kPrimary.withOpacity(0.15) : null,
    ),
    child: Text(text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: highlight ? kPrimary : kText,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        )),
  );

  Widget _lessonCell(ScheduledLesson lesson) {
    final isTheory = lesson.type != 'pratica';
    final color = lesson.confirmed
        ? (isTheory ? kPrimary : kAccent)
        : (isTheory ? kPrimary.withOpacity(0.6) : kAccent.withOpacity(0.6));
    return GestureDetector(
      onSecondaryTap: () => _deleteLesson(lesson),
      child: Container(
        height: 70,
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    isTheory ? 'T' : 'P',
                    style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'M${lesson.moduleNumber}',
                  style: const TextStyle(color: kTextDim, fontSize: 9),
                ),
                const Spacer(),
                if (lesson.confirmed)
                  const Icon(Icons.check_circle, color: kAccent, size: 10),
                GestureDetector(
                  onTap: () => _deleteLesson(lesson),
                  child: const Icon(Icons.close, color: kError, size: 10),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Expanded(
              child: Text(
                lesson.topic,
                style: TextStyle(color: color, fontSize: 10),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return _sameDay(d, now);
  }
}
