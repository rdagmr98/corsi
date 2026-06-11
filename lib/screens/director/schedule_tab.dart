import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
import '../../models/reference_models.dart';
import '../../models/schedule_models.dart';
import '../../models/user_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/course_service.dart';
import '../../services/gh_db_service.dart';
import '../../services/grade_service.dart';
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
  final _gradeService = GradeService();

  List<Course> _courses = [];
  Course? _selected;
  DateTime _weekStart = _mondayOf(DateTime.now());
  List<ScheduledLesson> _weekLessons = [];
  CourseTypeInfo? _typeInfo;
  List<ScheduledLesson> _allCourseLessons = [];

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
      _allCourseLessons = _scheduleService.getLessonsForCourse(_selected!.id)
          .where((l) => l.timeSlot > 0).toList();
      _typeInfo = _refService.getEffectiveCourseType(_selected!.courseTypeId, _selected!.extensionTypeId);
    });
  }

  String _normSubCode(String code) => ScheduleService.normalizeSubCode(code);

  /// GO/NO GO per istruttore (stessa formula di currency_tab):
  /// override, oppure ≥6h insegnamento/anno + ≥35h agg. professionale/2 anni
  /// + DAA non scaduta.
  Map<String, bool> _computeGoMap(List<AppUser> instructors) {
    final now = DateTime.now();
    return {
      for (final u in instructors)
        u.id: u.goOverride ||
            (_gradeService.getTeachingHoursRollingYear(u.id) >= 6 &&
                _gradeService.getProfessionalUpdateHoursLast2Years(u.id) >= 35 &&
                (u.daaExpiry == null || u.daaExpiry!.isAfter(now))),
    };
  }

  /// Voci del menu istruttore: solo gli abilitati AMC per quel sottomodulo e
  /// tipo (teoria/pratica), GO prima dei NO GO, poi per cognome. Se la griglia
  /// AMC non ha nessuno per quel codice, mostra tutti gli istruttori del corso.
  List<DropdownMenuItem<String?>> _instructorItems({
    required List<AppUser> instructors,
    required String submoduleCode,
    required String type,
    required Map<String, bool> goMap,
    String? current,
  }) {
    final qualified = _scheduleService.qualifiedInstructorIds(submoduleCode, type);
    var list = instructors.where((i) => qualified.contains(i.id)).toList();
    if (list.isEmpty) list = List.of(instructors);
    if (current != null && !list.any((i) => i.id == current)) {
      list.addAll(instructors.where((i) => i.id == current));
    }
    list.sort((a, b) {
      final ga = (goMap[a.id] ?? false) ? 0 : 1;
      final gb = (goMap[b.id] ?? false) ? 0 : 1;
      if (ga != gb) return ga - gb;
      return a.cognome.toLowerCase().compareTo(b.cognome.toLowerCase());
    });
    return [
      const DropdownMenuItem(value: null, child: Text('— Da assegnare —')),
      ...list.map((i) {
        final go = goMap[i.id] ?? false;
        return DropdownMenuItem<String?>(
          value: i.id,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: (go ? kAccent : kError).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(go ? 'GO' : 'NO GO',
                    style: TextStyle(
                        color: go ? kAccent : kError,
                        fontSize: 9,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 6),
              Flexible(child: Text(i.fullName, overflow: TextOverflow.ellipsis)),
            ],
          ),
        );
      }),
    ];
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
    _load();
  }

  Future<void> _addLesson(
    DateTime date,
    int slot, {
    int? presetModule,
    String? presetSubmodule,
    String? presetType,
    String? presetInstructor,
  }) async {
    if (_selected == null || _typeInfo == null) return;
    final instructors = _userService.getInstructors()
        .where((u) => _selected!.instructorIds.contains(u.id))
        .toList();

    // Count all scheduled hours (confirmed + unconfirmed) per submodule and module
    final doneLessons = _allCourseLessons;
    final doneT = <String, int>{};
    final doneP = <String, int>{};
    final confT = <String, int>{};
    final confP = <String, int>{};
    final doneTotalByModule = <int, int>{};
    for (final l in doneLessons) {
      final c = _normSubCode(l.submoduleCode);
      if (l.isTheory) {
        doneT[c] = (doneT[c] ?? 0) + 1;
        if (l.confirmed) confT[c] = (confT[c] ?? 0) + 1;
      } else {
        doneP[c] = (doneP[c] ?? 0) + 1;
        if (l.confirmed) confP[c] = (confP[c] ?? 0) + 1;
      }
      doneTotalByModule[l.moduleNumber] = (doneTotalByModule[l.moduleNumber] ?? 0) + 1;
    }

    // Only offer modules where confirmed total < planned total (skip constraint when ref hours = 0)
    final availableModules = _typeInfo!.modules.where((m) {
      if (m.totalHours == 0) return true;
      final done = doneTotalByModule[m.number] ?? 0;
      return done < m.totalHours;
    }).toList();

    if (availableModules.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tutte le lezioni del corso sono già completate.')),
        );
      }
      return;
    }

    int? selectedModule = presetModule != null &&
            availableModules.any((m) => m.number == presetModule)
        ? presetModule
        : availableModules.first.number;
    String? selectedSubmodule = presetSubmodule;
    String type = presetType ?? 'teoria';
    String? selectedInstructor =
        instructors.any((i) => i.id == presetInstructor) ? presetInstructor : null;
    final goMap = _computeGoMap(instructors);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final module = selectedModule != null
              ? availableModules.firstWhere((m) => m.number == selectedModule,
                  orElse: () => availableModules.first)
              : null;

          final availableSubs = module?.submodules.where((s) {
            // Unconstrained submodules (no reference hours) are always available
            if (s.theoryHours == 0 && s.practicalHours == 0) return true;
            final nc = _normSubCode(s.code);
            final schedT = doneT[nc] ?? 0;
            final schedP = doneP[nc] ?? 0;
            final cT = confT[nc] ?? 0;
            final cP = confP[nc] ?? 0;
            // Exclude if all scheduled lessons are confirmed (director considers it done)
            if ((schedT + schedP) > 0 && cT >= schedT && cP >= schedP) return false;
            // Include if reference hours remain
            return (s.theoryHours - schedT) > 0 || (s.practicalHours - schedP) > 0;
          }).toList() ?? [];

          if (selectedSubmodule != null &&
              !availableSubs.any((s) => s.code == selectedSubmodule)) {
            // preset (Salva e continua) non più disponibile: passa al prossimo
            selectedSubmodule = null;
          }
          if (selectedSubmodule == null && availableSubs.isNotEmpty) {
            selectedSubmodule = availableSubs.first.code;
            final first = availableSubs.first;
            final fnc = _normSubCode(first.code);
            if (first.theoryHours > 0 && (first.theoryHours - (doneT[fnc] ?? 0)) <= 0) type = 'pratica';
            else type = 'teoria';
          }

          final selSub = availableSubs.firstWhere(
              (s) => s.code == selectedSubmodule,
              orElse: () => availableSubs.isNotEmpty ? availableSubs.first : module!.submodules.first);
          final unconstrained = selSub.theoryHours == 0 && selSub.practicalHours == 0;
          final selNc = _normSubCode(selSub.code);
          final remT = unconstrained ? 1 : (selSub.theoryHours    - (doneT[selNc] ?? 0));
          final remP = unconstrained ? 1 : (selSub.practicalHours - (doneP[selNc] ?? 0));
          if (type == 'teoria' && remT <= 0 && remP > 0) type = 'pratica';
          if (type == 'pratica' && remP <= 0 && remT > 0) type = 'teoria';

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
                  const SizedBox(height: 8),
                  if (_selected!.attendeeIds.length > 15)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: kWarning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: kWarning.withOpacity(0.4)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.group, color: kWarning, size: 14),
                        const SizedBox(width: 6),
                        Text('${_selected!.attendeeIds.length} studenti — richiesti 2 istruttori',
                            style: const TextStyle(color: kWarning, fontSize: 11)),
                      ]),
                    ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<int>(
                    value: selectedModule,
                    dropdownColor: kSurface,
                    style: const TextStyle(color: kText),
                    decoration: const InputDecoration(labelText: 'Modulo', isDense: true),
                    items: availableModules
                        .map((m) => DropdownMenuItem(
                              value: m.number,
                              child: Text('M${m.displayCode} - ${m.name}',
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
                        final snc = _normSubCode(s.code);
                        final free = s.theoryHours == 0 && s.practicalHours == 0;
                        final rT = s.theoryHours    - (doneT[snc] ?? 0);
                        final rP = s.practicalHours - (doneP[snc] ?? 0);
                        final tag = free
                            ? 'T:${doneT[snc]??0}h P:${doneP[snc]??0}h'
                            : [if (rT > 0) '${rT}T', if (rP > 0) '${rP}P'].join(' ');
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
                          final vnc = _normSubCode(v);
                          if (s.theoryHours == 0 && s.practicalHours == 0) {
                            type = 'teoria';
                          } else {
                            type = (s.theoryHours - (doneT[vnc] ?? 0)) > 0 ? 'teoria' : 'pratica';
                          }
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
                    isExpanded: true,
                    style: const TextStyle(color: kText),
                    decoration: const InputDecoration(labelText: 'Istruttore', isDense: true),
                    items: _instructorItems(
                      instructors: instructors,
                      submoduleCode: selSub.code,
                      type: type,
                      goMap: goMap,
                      current: selectedInstructor,
                    ),
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
              OutlinedButton.icon(
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
                  _refreshWeek();
                  final next = _nextFreeSlot(date, slot);
                  if (next == null) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Nessuno slot libero successivo trovato.')));
                    }
                    return;
                  }
                  if (mounted) {
                    _addLesson(next.$1, next.$2,
                        presetModule: selectedModule,
                        presetSubmodule: selectedSubmodule,
                        presetType: type,
                        presetInstructor: selectedInstructor);
                  }
                },
                icon: const Icon(Icons.fast_forward, size: 14),
                label: const Text('Salva e continua'),
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
                  _refreshWeek();
                },
                child: const Text('Aggiungi'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Prossimo slot libero dopo [slot] di [date]: stesso giorno se possibile,
  /// altrimenti primo slot del giorno lavorativo successivo (saltando weekend,
  /// giorni esclusi e venerdì oltre la 3ª ora).
  (DateTime, int)? _nextFreeSlot(DateTime date, int slot) {
    if (_typeInfo == null) return null;
    final excluded = _selected?.excludedDates ?? const [];
    String fmt(DateTime x) =>
        '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    bool occupied(DateTime day, int s) =>
        _allCourseLessons.any((l) => _sameDay(l.date, day) && l.timeSlot == s);

    var d = DateTime(date.year, date.month, date.day);
    var after = slot;
    for (var i = 0; i < 366; i++) {
      final daySlots = _typeInfo!.schedule
          .slotsForWeekday(d.weekday)
          .map((t) => t.slot)
          .where((s) => d.weekday != DateTime.friday || s <= 3)
          .toList()
        ..sort();
      for (final s in daySlots) {
        if (s <= after) continue;
        if (!occupied(d, s)) return (d, s);
      }
      do {
        d = DateTime(d.year, d.month, d.day + 1);
      } while (d.weekday == DateTime.saturday ||
          d.weekday == DateTime.sunday ||
          excluded.contains(fmt(d)));
      after = 0;
    }
    return null;
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
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2030),
                            builder: (context, child) => Theme(
                              data: ThemeData.dark(), child: child!,
                            ),
                          );
                          if (d != null) {
                            final s = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                            if (!excluded.contains(s)) {
                              setDlg(() { excluded.add(s); excluded.sort(); });
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('Giorno', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final range = await showDateRangePicker(
                            context: ctx,
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2030),
                            initialDateRange: DateTimeRange(
                              start: DateTime.now(),
                              end: DateTime.now().add(const Duration(days: 7)),
                            ),
                            builder: (context, child) => Theme(
                              data: ThemeData.dark(), child: child!,
                            ),
                          );
                          if (range != null) {
                            var d = range.start;
                            while (!d.isAfter(range.end)) {
                              final s = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                              if (!excluded.contains(s)) excluded.add(s);
                              d = d.add(const Duration(days: 1));
                            }
                            excluded.sort();
                            setDlg(() {});
                          }
                        },
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                        icon: const Icon(Icons.date_range, size: 14),
                        label: const Text('Periodo', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  ],
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

  Future<void> _addRecovery(DateTime day) async {
    if (_selected == null) return;
    final attendees = _userService.getAllUsers()
        .where((u) => _selected!.attendeeIds.contains(u.id))
        .toList();
    if (attendees.isEmpty) return;

    final typeInfo = _typeInfo;
    if (typeInfo == null) return;

    final selectedAttendees = <String>{};
    int? selectedModule = typeInfo.modules.isNotEmpty ? typeInfo.modules.first.number : null;
    final user = ref.read(authProvider).currentUser;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: kCard,
          title: Text(
            'Recupero – ${DateFormat('dd/MM/yyyy').format(day)}',
            style: const TextStyle(color: kText, fontSize: 14),
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Modulo recuperato:', style: TextStyle(color: kTextDim, fontSize: 12)),
                const SizedBox(height: 6),
                DropdownButtonFormField<int>(
                  value: selectedModule,
                  dropdownColor: kSurface,
                  style: const TextStyle(color: kText),
                  decoration: const InputDecoration(isDense: true),
                  items: typeInfo.modules
                      .map((m) => DropdownMenuItem(value: m.number, child: Text('M${m.displayCode} – ${m.name}', overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setDlg(() => selectedModule = v),
                ),
                const SizedBox(height: 12),
                const Text('Frequentatori presenti al recupero:', style: TextStyle(color: kTextDim, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: attendees.map((a) {
                    final sel = selectedAttendees.contains(a.id);
                    return FilterChip(
                      label: Text(a.fullName, style: TextStyle(color: sel ? Colors.white : kTextDim, fontSize: 11)),
                      selected: sel,
                      selectedColor: kAccent.withOpacity(0.8),
                      backgroundColor: kSurface,
                      onSelected: (v) => setDlg(() {
                        if (v) selectedAttendees.add(a.id); else selectedAttendees.remove(a.id);
                      }),
                    );
                  }).toList(),
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
              onPressed: selectedAttendees.isEmpty || selectedModule == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      for (final id in selectedAttendees) {
                        await _attendanceService.saveRecovery(
                          courseId: _selected!.id,
                          attendeeId: id,
                          confirmedBy: user?.id ?? '',
                          recoveredModule: selectedModule!,
                          recoveryDate: day,
                        );
                      }
                      _refreshWeek();
                    },
              child: const Text('Salva recuperi'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteLesson(ScheduledLesson lesson) async {
    await _scheduleService.deleteLesson(lesson.id);
    _refreshWeek();
  }

  Future<void> _editLessonInstructor(ScheduledLesson lesson) async {
    if (_selected == null || _typeInfo == null) return;
    final instructors = _userService.getInstructors()
        .where((u) => _selected!.instructorIds.contains(u.id))
        .toList();

    final isTheory = lesson.isTheory;

    // Raccoglie codici sottomodulo con lezioni non confermate da questa data+slot in poi
    final remainingCodes = _allCourseLessons.where((l) {
      if (l.confirmed) return false;
      if (isTheory ? !l.isTheory : l.isTheory) return false;
      final sameDay = l.date.year == lesson.date.year &&
          l.date.month == lesson.date.month &&
          l.date.day == lesson.date.day;
      if (sameDay) return l.timeSlot >= lesson.timeSlot;
      return l.date.isAfter(lesson.date);
    }).map((l) => l.submoduleCode).toSet();

    // Mappa codice → (numero modulo, nome) dal reference
    final refSubInfo = <String, (int, String)>{};
    for (final m in _typeInfo!.modules) {
      for (final s in m.submodules) {
        refSubInfo[s.code] = (m.number, s.name);
      }
    }

    // Costruisce opzioni: sempre il sottomodulo corrente + quelli futuri non confermati
    final submoduleOptions = <(String, String)>[];
    final seenCodes = <String>{};
    for (final code in [lesson.submoduleCode, ...remainingCodes]) {
      if (!seenCodes.add(code)) continue;
      final info = refSubInfo[code];
      final label = info != null ? 'M${info.$1} $code – ${info.$2}' : code;
      submoduleOptions.add((code, label));
    }

    String? selectedInstructor = lesson.instructorId;
    String selectedSubmodule = lesson.submoduleCode;
    bool recompile = true;
    final goMap = _computeGoMap(instructors);
    final lessonType = isTheory ? 'teoria' : 'pratica';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: kCard,
          title: Text(
            'M${_refService.moduleLabel(lesson.moduleNumber)} · ${lesson.submoduleCode}',
            style: const TextStyle(color: kText, fontSize: 14),
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selected!.attendeeIds.length > 15)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: kWarning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: kWarning.withOpacity(0.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.group, color: kWarning, size: 14),
                      const SizedBox(width: 6),
                      Text('${_selected!.attendeeIds.length} studenti — richiesti 2 istruttori',
                          style: const TextStyle(color: kWarning, fontSize: 11)),
                    ]),
                  ),
                DropdownButtonFormField<String>(
                  value: selectedSubmodule,
                  dropdownColor: kSurface,
                  isExpanded: true,
                  style: const TextStyle(color: kText, fontSize: 12),
                  decoration: const InputDecoration(labelText: 'Sottomodulo', isDense: true),
                  items: submoduleOptions.map((e) => DropdownMenuItem(
                    value: e.$1,
                    child: Text(e.$2, overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (v) => setDlg(() => selectedSubmodule = v ?? selectedSubmodule),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: selectedInstructor,
                  dropdownColor: kSurface,
                  isExpanded: true,
                  style: const TextStyle(color: kText),
                  decoration: const InputDecoration(labelText: 'Istruttore', isDense: true),
                  items: _instructorItems(
                    instructors: instructors,
                    submoduleCode: selectedSubmodule,
                    type: lessonType,
                    goMap: goMap,
                    current: selectedInstructor,
                  ),
                  onChanged: (v) => setDlg(() => selectedInstructor = v),
                ),
                if (selectedSubmodule != lesson.submoduleCode) ...[
                  const SizedBox(height: 4),
                  CheckboxListTile(
                    value: recompile,
                    onChanged: (v) => setDlg(() => recompile = v ?? true),
                    title: const Text('Rigenera lezioni non confermate dal giorno dopo',
                        style: TextStyle(color: kText, fontSize: 12)),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla', style: TextStyle(color: kTextDim)),
            ),
            if (!lesson.confirmed)
              OutlinedButton.icon(
                onPressed: selectedInstructor == null
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        if (selectedInstructor != lesson.instructorId) {
                          await _scheduleService.updateLesson(
                              lesson.copyWith(instructorId: selectedInstructor));
                        }
                        final user = ref.read(authProvider).currentUser;
                        await _scheduleService.confirmLesson(
                            lesson.id, user?.id ?? '');
                        _refreshWeek();
                      },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kAccent),
                  foregroundColor: kAccent,
                ),
                icon: const Icon(Icons.task_alt, size: 14),
                label: const Text('Valida ora'),
              ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final subChanged = selectedSubmodule != lesson.submoduleCode;
                int newModuleNum = lesson.moduleNumber;
                if (subChanged) {
                  for (final m in _typeInfo!.modules) {
                    if (m.submodules.any((s) => s.code == selectedSubmodule)) {
                      newModuleNum = m.number;
                      break;
                    }
                  }
                }
                await _scheduleService.updateLesson(lesson.copyWith(
                  instructorId: selectedInstructor,
                  submoduleCode: selectedSubmodule,
                  moduleNumber: newModuleNum,
                  topic: selectedSubmodule,
                ));
                if (subChanged && recompile) {
                  final nextDay = lesson.date.add(const Duration(days: 1));
                  await _scheduleService.deleteUnconfirmedLessonsFrom(_selected!.id, nextDay);
                  await _generateRemaining();
                } else {
                  _refreshWeek();
                }
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteUnconfirmedLessons() async {
    if (_selected == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Cancella lezioni non svolte', style: TextStyle(color: kError)),
        content: const Text(
          'Questa operazione cancellerà tutte le lezioni programmate ma non ancora confermate per questo corso.\n\nL\'operazione non è reversibile.',
          style: TextStyle(color: kText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla', style: TextStyle(color: kTextDim)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kError),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancella'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final deleted = await _scheduleService.deleteUnconfirmedLessons(_selected!.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$deleted lezioni non svolte cancellate.')),
      );
      _refreshWeek();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_courses.isEmpty) {
      return const Center(child: Text('Nessun corso assegnato', style: TextStyle(color: kTextDim)));
    }

    final weekDays = List.generate(7, (i) => _weekStart.add(Duration(days: i)));
    final allSlots = _typeInfo?.schedule.mondayThursday ?? [];
    final recoveryLessons = _weekLessons.where((l) => l.timeSlot == 0).toList();
    final regularLessons = _weekLessons.where((l) => l.timeSlot > 0).toList();
    final subNameMap = <String, String>{
      for (final m in _typeInfo?.modules ?? [])
        for (final s in m.submodules) s.code: s.name,
    };

    // Build progressive ordinal per lesson (sorted by date+slot, within submodule+type group)
    final sortedAll = [..._allCourseLessons]
        ..sort((a, b) {
          final dc = a.date.compareTo(b.date);
          return dc != 0 ? dc : a.timeSlot.compareTo(b.timeSlot);
        });
    final cntT = <String, int>{};
    final cntP = <String, int>{};
    final lessonOrdinals = <String, int>{};
    for (final l in sortedAll) {
      if (l.timeSlot == 0) continue;
      final nc = _normSubCode(l.submoduleCode);
      if (l.type != 'pratica') {
        cntT[nc] = (cntT[nc] ?? 0) + 1;
        lessonOrdinals[l.id] = cntT[nc]!;
      } else {
        cntP[nc] = (cntP[nc] ?? 0) + 1;
        lessonOrdinals[l.id] = cntP[nc]!;
      }
    }
    final subPlanT = <String, int>{};
    final subPlanP = <String, int>{};
    for (final m in _typeInfo?.modules ?? <ModuleInfo>[]) {
      for (final s in m.submodules) {
        final nc = _normSubCode(s.code);
        subPlanT[nc] = (subPlanT[nc] ?? 0) + s.theoryHours;
        subPlanP[nc] = (subPlanP[nc] ?? 0) + s.practicalHours;
      }
    }
    final instrNames = <String, String>{
      for (final u in _userService.getInstructors()) u.id: u.cognome,
    };

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
                '${DateFormat('dd/MM').format(_weekStart)} – ${DateFormat('dd/MM/yyyy').format(_weekStart.add(const Duration(days: 6)))}',
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
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _deleteUnconfirmedLessons,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: kError),
                    foregroundColor: kError,
                  ),
                  icon: const Icon(Icons.delete_sweep, size: 16),
                  label: const Text('Cancella non svolte', style: TextStyle(fontSize: 12)),
                ),
              ],
              IconButton(icon: const Icon(Icons.refresh, color: kTextDim), onPressed: _reload),
              ValueListenableBuilder<int>(
                valueListenable: GhDbService.pendingSaves,
                builder: (_, n, __) => n > 0
                    ? const Tooltip(
                        message: 'Salvataggio in corso…',
                        child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : ValueListenableBuilder<String?>(
                        valueListenable: GhDbService.saveError,
                        builder: (_, err, __) => err == null
                            ? const SizedBox(width: 14)
                            : Tooltip(
                                message: err,
                                child: const Icon(Icons.cloud_off,
                                    color: kError, size: 16),
                              ),
                      ),
              ),
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
                        ...weekDays.map(_dayHeaderCell),
                      ],
                    ),
                    // Riga recupero (slot 0) — sempre visibile
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
                          final isWeekend = day.weekday == DateTime.saturday ||
                              day.weekday == DateTime.sunday;
                          if (isWeekend) {
                            return TableCell(
                              child: Container(height: 50, color: kBorder.withOpacity(0.04)),
                            );
                          }
                          final recs = recoveryLessons.where((l) => _sameDay(l.date, day)).toList();
                          return TableCell(
                            child: InkWell(
                              onTap: () => _addRecovery(day),
                              child: Container(
                                height: 50,
                                margin: const EdgeInsets.all(2),
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: recs.isNotEmpty
                                      ? kWarning.withOpacity(0.12)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: recs.isNotEmpty
                                        ? kWarning.withOpacity(0.4)
                                        : kBorder.withOpacity(0.3),
                                    width: recs.isNotEmpty ? 1 : 0.5,
                                  ),
                                ),
                                child: recs.isNotEmpty
                                    ? Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('${recs.length} rec.',
                                              style: const TextStyle(color: kWarning, fontSize: 9, fontWeight: FontWeight.bold)),
                                        ],
                                      )
                                    : const Center(child: Icon(Icons.add, color: kBorder, size: 12)),
                              ),
                            ),
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
                                Text(slotStr, style: const TextStyle(color: kTextDim, fontSize: 9), softWrap: false, overflow: TextOverflow.visible),
                              ],
                            ),
                          ),
                          ...weekDays.map((day) {
                            final isWeekend = day.weekday == DateTime.saturday ||
                                day.weekday == DateTime.sunday;
                            if (isWeekend) {
                              return TableCell(
                                child: Container(
                                  height: 120,
                                  color: kBorder.withOpacity(0.04),
                                  child: const Center(
                                    child: Text('—', style: TextStyle(color: kBorder, fontSize: 10)),
                                  ),
                                ),
                              );
                            }
                            if (day.weekday == DateTime.friday && slot.slot > 3) {
                              return const TableCell(
                                child: SizedBox(height: 120, child: Center(
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
                                        height: 120,
                                        alignment: Alignment.center,
                                        child: const Icon(Icons.add, color: kBorder, size: 16),
                                      ),
                                    )
                                  : _lessonCell(lesson, subNameMap, instrNames,
                                      ordinals: lessonOrdinals,
                                      planT: subPlanT, planP: subPlanP),
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

  /// Intestazione giorno con pulsante "Valida N" quando ci sono ore non
  /// confermate con istruttore assegnato: il direttore le conferma in blocco.
  Widget _dayHeaderCell(DateTime d) {
    final pending = _weekLessons
        .where((l) =>
            _sameDay(l.date, d) &&
            l.timeSlot > 0 &&
            !l.confirmed &&
            l.instructorId != null)
        .toList();
    final highlight = _isToday(d);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highlight ? kPrimary.withOpacity(0.15) : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(DateFormat('EEE dd/MM', 'it').format(d),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: highlight ? kPrimary : kText,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              )),
          if (pending.isNotEmpty)
            Tooltip(
              message:
                  'Conferma le ${pending.length} ore del giorno con istruttore assegnato\nper conto degli istruttori',
              child: InkWell(
                onTap: () => _validateDay(d, pending),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.task_alt, size: 11, color: kAccent),
                      const SizedBox(width: 3),
                      Text('Valida ${pending.length}',
                          style: const TextStyle(
                              color: kAccent,
                              fontSize: 9,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _validateDay(DateTime day, List<ScheduledLesson> pending) async {
    final user = ref.read(authProvider).currentUser;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Valida giornata',
            style: TextStyle(color: kText, fontSize: 14)),
        content: Text(
          'Confermare ${pending.length} ore di lezione di '
          '${DateFormat('EEEE dd/MM/yyyy', 'it').format(day)} per conto degli istruttori assegnati?',
          style: const TextStyle(color: kText, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla', style: TextStyle(color: kTextDim)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Valida'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _scheduleService.confirmLessons(
        pending.map((l) => l.id).toList(), user?.id ?? '');
    _refreshWeek();
  }

  Widget _lessonCell(
    ScheduledLesson lesson,
    Map<String, String> subNames,
    Map<String, String> instrNames, {
    required Map<String, int> ordinals,
    required Map<String, int> planT,
    required Map<String, int> planP,
  }) {
    final isTheory = lesson.type != 'pratica';
    final nc = _normSubCode(lesson.submoduleCode);
    final base = moduleColor(lesson.moduleNumber);
    final color = lesson.confirmed ? base : base.withOpacity(0.5);

    final displayTopic = '$nc – ${subNames[nc] ?? lesson.topic}';

    final rawOrd = ordinals[lesson.id] ?? 1;
    final plan = isTheory ? (planT[nc] ?? 0) : (planP[nc] ?? 0);
    // Le ore oltre il piano ufficiale sono recuperi: il contatore non deve
    // mai superare il monte ore del programma.
    final isExtra = plan > 0 && rawOrd > plan;
    final conf = isExtra ? plan : rawOrd;
    final typeLabel = isTheory ? 'T' : 'P';
    final hoursStr = plan > 0
        ? '$typeLabel $conf/$plan h${isExtra ? ' (rec.)' : ''}'
        : '$typeLabel ${rawOrd}h';
    final instrName = lesson.instructorId != null
        ? (instrNames[lesson.instructorId!] ?? '?')
        : null;

    final tooltipMsg = [
      displayTopic,
      if (instrName != null) '👤 $instrName',
      hoursStr,
    ].join('\n');

    return GestureDetector(
      onTap: () => _editLessonInstructor(lesson),
      onSecondaryTap: () => _deleteLesson(lesson),
      child: Tooltip(
        message: tooltipMsg,
        waitDuration: const Duration(milliseconds: 500),
        child: Container(
        height: 120,
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
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(typeLabel,
                    style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 4),
              Text('M${_refService.moduleLabel(lesson.moduleNumber)}',
                  style: const TextStyle(color: kTextDim, fontSize: 9)),
              const Spacer(),
              if (lesson.confirmed) Icon(Icons.check_circle, color: color, size: 10),
              GestureDetector(
                onTap: () => _deleteLesson(lesson),
                child: const Icon(Icons.close, color: kError, size: 10),
              ),
            ]),
            const SizedBox(height: 2),
            Expanded(
              child: Text(displayTopic,
                  style: TextStyle(color: color, fontSize: 10),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis),
            ),
            Row(children: [
              Expanded(
                child: Text(hoursStr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: color.withOpacity(0.7),
                        fontSize: 9,
                        fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 2),
              if (instrName != null)
                Flexible(
                  child: Text(instrName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
                )
              else
                Icon(Icons.person_outline, size: 9, color: kBorder),
            ]),
          ],
        ),
      ),
    ));
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return _sameDay(d, now);
  }
}
