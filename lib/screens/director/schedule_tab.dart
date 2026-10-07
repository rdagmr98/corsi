import 'dart:async';
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
import '../../services/notification_service.dart';
import '../../services/reference_service.dart';
import '../../services/excel_export_service.dart';
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
  final _notifService = NotificationService();

  List<Course> _courses = [];
  Course? _selected;
  DateTime _weekStart = _mondayOf(DateTime.now());
  List<ScheduledLesson> _weekLessons = [];
  List<SlotNote> _weekNotes = [];
  CourseTypeInfo? _typeInfo;
  List<ScheduledLesson> _allCourseLessons = [];
  // Cognomi degli assenti per lezione della settimana (id lezione → cognomi).
  Map<String, List<String>> _weekAbsent = {};
  // Cambio settimana durante il trascinamento sui bordi laterali.
  Timer? _edgeTimer;
  Timer? _previewTimer;
  // Anteprima del riordino durante il trascinamento (id → data, ora), come
  // la ReorderableListView di gym_app. _shownPreview = quella dell'ultimo
  // build: le lezioni scivolano da lì alla nuova posizione.
  Map<String, (DateTime, int)> _preview = {};
  Map<String, (DateTime, int)> _shownPreview = {};
  String? _dragId;

  // Aritmetica a calendario (non Duration): con l'ora legale +7*24h da
  // lunedì 00:00 finiva a domenica 23:00 e la settimana partiva di domenica.
  static DateTime _mondayOf(DateTime d) {
    final diff = d.weekday - DateTime.monday;
    return DateTime(d.year, d.month, d.day - diff);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _edgeTimer?.cancel();
    _previewTimer?.cancel();
    super.dispose();
  }

  void _load() {
    _courses = _courseService.getCoursesForDirector(widget.userId);
    if (_selected == null) {
      if (_courses.isNotEmpty) _selected = _courses.first;
    } else {
      _selected = _courses.where((c) => c.id == _selected!.id).firstOrNull ?? _selected;
    }
    _refreshWeek();
    _ensureCoursePsDefaults();
  }

  /// Persiste header PS 3° BTC (da 66_PS) + default aula + backfill lezioni.
  Future<void> _ensureCoursePsDefaults() async {
    final c = _selected;
    if (c == null) return;
    final updated = await _courseService.ensurePsHeaderDefaults(c);
    if (!mounted) return;
    setState(() => _selected = updated);
    final def = updated.resolvedDefaultAula;
    if (def == null) return;
    if (updated.defaultAula == null) {
      await _courseService.updateCourse(updated.copyWith(defaultAula: def));
      if (!mounted) return;
      setState(() {
        _selected = _courseService.findById(c.id) ??
            updated.copyWith(defaultAula: def);
      });
    }
    final n = await _scheduleService.ensureLessonAulas(c.id, def);
    if (n > 0 && mounted) _refreshWeek();
  }

  Future<void> _showPsHeaderSettings() async {
    if (_selected == null) return;
    DateTime? start = _selected!.startDate;
    DateTime? end = _selected!.endDate;
    final durationCtrl = TextEditingController(
      text: _selected!.durationWeeks?.toString() ?? '',
    );
    final delayCtrl = TextEditingController(
      text: _selected!.delayWeeks?.toString() ?? '',
    );
    int aula = _selected!.resolvedDefaultAula ?? 3;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: kCard,
          title: const Text('Dati corso (Excel PS)',
              style: TextStyle(color: kText)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _psDateRow(
                  'DATA INIZIO CORSO',
                  start,
                  () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: start ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (d != null) setDlg(() => start = d);
                  },
                  () => setDlg(() => start = null),
                ),
                const SizedBox(height: 12),
                _psDateRow(
                  'DATA FINE CORSO (PIANIFICATA)',
                  end,
                  () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: end ?? start ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (d != null) setDlg(() => end = d);
                  },
                  () => setDlg(() => end = null),
                ),
                const SizedBox(height: 12),
                const Text('DURATA (n. settimane)',
                    style: TextStyle(color: kTextDim, fontSize: 12)),
                TextField(
                  controller: durationCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: kText),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'es. 86',
                  ),
                ),
                const SizedBox(height: 12),
                const Text('EVENTUALE RITARDO (N. SETT.)',
                    style: TextStyle(color: kTextDim, fontSize: 12)),
                TextField(
                  controller: delayCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: kText),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'vuoto se nessuno',
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Aula / classe default (1–7)',
                    style: TextStyle(color: kTextDim, fontSize: 12)),
                DropdownButtonFormField<int>(
                  value: aula,
                  dropdownColor: kSurface,
                  style: const TextStyle(color: kText),
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    for (var i = 1; i <= 7; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text('Aula $i',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setDlg(() => aula = v ?? aula),
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
                final dur = int.tryParse(durationCtrl.text.trim());
                final del = int.tryParse(delayCtrl.text.trim());
                Navigator.pop(ctx);
                final updated = _selected!.copyWith(
                  startDate: start,
                  endDate: end,
                  durationWeeks: dur,
                  delayWeeks: delayCtrl.text.trim().isEmpty ? null : del,
                  defaultAula: aula,
                );
                await _courseService.updateCourse(updated);
                if (!mounted) return;
                setState(() {
                  _selected = _courseService.findById(updated.id) ?? updated;
                });
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
    durationCtrl.dispose();
    delayCtrl.dispose();
  }

  Widget _psDateRow(
    String label,
    DateTime? value,
    VoidCallback onPick,
    VoidCallback onClear,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: kTextDim, fontSize: 12)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                value != null
                    ? DateFormat('dd/MM/yyyy').format(value)
                    : 'Non impostata',
                style: const TextStyle(color: kText, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(onPressed: onPick, child: const Text('Scegli')),
            if (value != null)
              TextButton(
                onPressed: onClear,
                child: const Text('Pulisci',
                    style: TextStyle(color: kTextDim)),
              ),
          ],
        ),
      ],
    );
  }

  void _refreshWeek() {
    if (_selected == null) return;
    _previewTimer?.cancel();
    setState(() {
      _weekLessons = _scheduleService.getLessonsForWeek(_selected!.id, _weekStart);
      _weekNotes = _scheduleService.getNotesForWeek(_selected!.id, _weekStart);
      _allCourseLessons = _scheduleService.getLessonsForCourse(_selected!.id)
          .where((l) => l.timeSlot > 0).toList();
      _typeInfo = _refService.getEffectiveCourseType(_selected!.courseTypeId, _selected!.extensionTypeId, _selected!.mamlCombinationId);
      final weekIds = {for (final l in _weekLessons) l.id};
      _weekAbsent = {};
      for (final r in _attendanceService.getAllRecords()) {
        if (r.present || !weekIds.contains(r.scheduleId)) continue;
        (_weekAbsent[r.scheduleId] ??= [])
            .add(_userService.findById(r.attendeeId)?.cognome ?? '?');
      }
      // Cambio settimana o salvataggio: i DragTarget vecchi spariscono senza onLeave.
      _preview = {};
      _dragId = null;
    });
  }

  String _normSubCode(String code) => ScheduleService.normalizeSubCode(code);

  // Evita lo ".0" superfluo per le ore intere, mantenendo i decimali (es. 1.5h) quando presenti.
  String _fmtNum(num n) => n == n.truncate() ? n.truncate().toString() : n.toString();

  /// Voci del menu istruttore: solo gli abilitati AMC per quel sottomodulo e
  /// tipo (teoria/pratica), GO prima dei NO GO, poi per cognome. Se la griglia
  /// AMC non ha nessuno per quel codice, mostra tutti gli istruttori del corso.
  /// GO/NO GO è per modulo: il DAA (scadenza NAM) conta solo su modulo 10.
  List<DropdownMenuItem<String?>> _instructorItems({
    required List<AppUser> instructors,
    required String submoduleCode,
    required String type,
    required int? moduleNumber,
    required DateTime date,
    required int timeSlot,
    String? current,
    String? excludeLessonId,
    dynamic taskId,
  }) {
    final qualified = _scheduleService.qualifiedInstructorIds(submoduleCode, type);
    var list = instructors.where((i) => qualified.contains(i.id)).toList();
    if (list.isEmpty) list = List.of(instructors);

    // Doppia prenotazione: un istruttore già assegnato altrove nella stessa
    // ora non è selezionabile, a meno che sia la stessa lezione/task pratico
    // e la somma frequentatori resti entro il limite aula (28 teoria/15 pratica).
    final nc = ScheduleService.normalizeSubCode(submoduleCode);
    final isTheory = type == 'teoria';
    final cap = isTheory ? 28 : 15;
    final myAttendees = _selected?.attendeeIds.length ?? 0;
    bool allowed(String instructorId) {
      if (instructorId == current) return true;
      final conflicts = _scheduleService.lessonsForInstructorAt(
          instructorId, date, timeSlot, excludeLessonId: excludeLessonId);
      for (final other in conflicts) {
        final sameLesson =
            ScheduleService.normalizeSubCode(other.submoduleCode) == nc &&
                other.isTheory == isTheory &&
                (isTheory || other.taskId == taskId);
        if (!sameLesson) return false;
        final otherAttendees =
            _courseService.findById(other.courseId)?.attendeeIds.length ?? 0;
        if (myAttendees + otherAttendees > cap) return false;
      }
      return true;
    }
    list = list.where((i) => allowed(i.id)).toList();

    if (current != null && !list.any((i) => i.id == current)) {
      list.addAll(instructors.where((i) => i.id == current));
    }
    list.sort((a, b) {
      final ga = _gradeService.isGo(a, moduleNumber: moduleNumber) ? 0 : 1;
      final gb = _gradeService.isGo(b, moduleNumber: moduleNumber) ? 0 : 1;
      if (ga != gb) return ga - gb;
      return a.cognome.toLowerCase().compareTo(b.cognome.toLowerCase());
    });
    return [
      const DropdownMenuItem(value: null, child: Text('— Da assegnare —')),
      ...list.map((i) {
        final go = _gradeService.isGo(i, moduleNumber: moduleNumber);
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
      _weekStart = _mondayOf(DateTime(_weekStart.year, _weekStart.month, _weekStart.day - 7));
      _refreshWeek();
    });
  }

  void _nextWeek() {
    setState(() {
      _weekStart = _mondayOf(DateTime(_weekStart.year, _weekStart.month, _weekStart.day + 7));
      _refreshWeek();
    });
  }

  // Salto diretto a una settimana qualsiasi (le frecce restano per il passo singolo).
  Future<void> _pickWeek() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _weekStart,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'Vai alla settimana del…',
    );
    if (d == null) return;
    _weekStart = _mondayOf(d);
    _refreshWeek();
  }

  void _goToday() {
    _weekStart = _mondayOf(DateTime.now());
    _refreshWeek();
  }

  Future<void> _generateRemaining() async {
    if (_selected == null || _typeInfo == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Genera lezioni rimanenti',
            style: TextStyle(color: kText, fontSize: 14)),
        content: const Text(
          'Verranno rigenerate le lezioni non ancora confermate di questo corso. '
          'Le lezioni confermate e quelle inserite a mano restano invariate.\n\nProcedere?',
          style: TextStyle(color: kText, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla', style: TextStyle(color: kTextDim)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Genera'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final hasRecovery = _attendanceService.courseHasAttendeesInRecovery(
      _selected!.id,
      _selected!.attendeeIds,
      _scheduleService.getLessonsForCourse(_selected!.id),
      modules: _typeInfo?.modules,
    );
    await _scheduleService.generateRemainingSchedule(
      courseId: _selected!.id,
      typeInfo: _typeInfo!,
      hasAttendeesInRecovery: hasRecovery,
      excludedDates: _selected!.excludedDates,
      defaultAula: _selected!.resolvedDefaultAula,
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
    // Gli istruttori sono assegnati a tutti i corsi: nessun filtro per corso.
    final instructors = _userService.getInstructors();

    // Count all scheduled hours (confirmed + unconfirmed) per submodule and module
    final doneLessons = _allCourseLessons;
    final doneT = <String, int>{};
    final doneP = <String, int>{};
    final doneTotalByModule = <int, int>{};
    for (final l in doneLessons) {
      final c = _normSubCode(l.submoduleCode);
      if (l.isTheory) {
        doneT[c] = (doneT[c] ?? 0) + 1;
      } else {
        doneP[c] = (doneP[c] ?? 0) + 1;
      }
      doneTotalByModule[l.moduleNumber] = (doneTotalByModule[l.moduleNumber] ?? 0) + 1;
    }

    // Un sottomodulo è proponibile finché restano ore del programma da
    // pianificare (T o P), confermate o no. Quelli senza monte ore (0/0)
    // sono sempre proponibili.
    List<SubmoduleInfo> subsFor(ModuleInfo m) => m.submodules.where((s) {
      if (s.theoryHours == 0 && s.practicalHours == 0) return true;
      final nc = _normSubCode(s.code);
      return (s.theoryHours - (doneT[nc] ?? 0)) > 0 ||
          (s.practicalHours - (doneP[nc] ?? 0)) > 0;
    }).toList();

    // Moduli proponibili: stesso criterio del generatore — il modulo è chiuso
    // quando ogni sottomodulo ha raggiunto il proprio monte ore. I moduli con
    // soli sottomoduli senza monte ore (0/0) si chiudono al raggiungimento
    // del totale del modulo.
    final availableModules = _typeInfo!.modules.where((m) {
      if (m.submodules.isEmpty) return true;
      final subs = subsFor(m);
      if (subs.isEmpty) return false;
      final onlyFree =
          subs.every((s) => s.theoryHours == 0 && s.practicalHours == 0);
      if (onlyFree &&
          m.totalHours > 0 &&
          (doneTotalByModule[m.number] ?? 0) >= m.totalHours) {
        return false;
      }
      return true;
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
    String? selectedInstructor2;
    dynamic selectedTaskId;
    int selectedAula = _selected!.resolvedDefaultAula ?? 3;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final module = selectedModule != null
              ? availableModules.firstWhere((m) => m.number == selectedModule,
                  orElse: () => availableModules.first)
              : null;

          final availableSubs =
              module == null ? <SubmoduleInfo>[] : subsFor(module);

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

          final SubmoduleInfo? selSub = availableSubs.isEmpty
              ? null
              : availableSubs.firstWhere((s) => s.code == selectedSubmodule,
                  orElse: () => availableSubs.first);
          final unconstrained = selSub == null ||
              (selSub.theoryHours == 0 && selSub.practicalHours == 0);
          final selNc = selSub == null ? '' : _normSubCode(selSub.code);
          final remT = unconstrained ? 1 : (selSub!.theoryHours    - (doneT[selNc] ?? 0));
          final remP = unconstrained ? 1 : (selSub!.practicalHours - (doneP[selNc] ?? 0));
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
                    isExpanded: true,
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
                      isExpanded: true,
                      style: const TextStyle(color: kText),
                      decoration: const InputDecoration(labelText: 'Sottomodulo', isDense: true),
                      items: availableSubs.map((s) {
                        final snc = _normSubCode(s.code);
                        final free = s.theoryHours == 0 && s.practicalHours == 0;
                        final rT = s.theoryHours    - (doneT[snc] ?? 0);
                        final rP = s.practicalHours - (doneP[snc] ?? 0);
                        final tag = free
                            ? 'T:${doneT[snc]??0}h P:${doneP[snc]??0}h'
                            : [if (rT > 0) 'restano ${rT}T', if (rP > 0) '${rP}P'].join(' ');
                        return DropdownMenuItem(
                          value: s.code,
                          child: Text('${s.code} ($tag) - ${s.name}',
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
                    onChanged: (v) => setDlg(() {
                      type = v ?? type;
                      if (type != 'pratica') selectedInstructor2 = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: selectedAula,
                    dropdownColor: kSurface,
                    isExpanded: true,
                    style: const TextStyle(color: kText),
                    decoration: InputDecoration(
                      labelText: type == 'pratica'
                          ? 'Aula (Excel pratica = HANGAR 6)'
                          : 'Aula',
                      isDense: true,
                    ),
                    items: [
                      for (var i = 1; i <= 7; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text('Aula $i',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) =>
                        setDlg(() => selectedAula = v ?? selectedAula),
                  ),
                  // Task dropdown per la pratica
                  if (type == 'pratica' && selSub != null && selSub.practicalTasks.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Builder(builder: (_) {
                      final nc = _normSubCode(selSub.code);
                      final taskRemaining = <dynamic, num>{};
                      for (final t in selSub.practicalTasks) {
                        final used = _allCourseLessons
                            .where((l) => !l.isTheory &&
                                _normSubCode(l.submoduleCode) == nc &&
                                l.taskId == t.id)
                            .length;
                        taskRemaining[t.id] = (t.plannedHours - used).clamp(0, t.plannedHours);
                      }
                      // Auto-set to first incomplete task if not set or task changed
                      if (selectedTaskId == null ||
                          !selSub.practicalTasks.any((t) => t.id == selectedTaskId)) {
                        final first = selSub.practicalTasks.firstWhere(
                            (t) => (taskRemaining[t.id] ?? 0) > 0,
                            orElse: () => selSub.practicalTasks.first);
                        selectedTaskId = first.id;
                      }
                      return DropdownButtonFormField<dynamic>(
                        value: selectedTaskId,
                        dropdownColor: kSurface,
                        isExpanded: true,
                        style: const TextStyle(color: kText),
                        decoration: const InputDecoration(labelText: 'Task pratica', isDense: true),
                        items: selSub.practicalTasks.map((t) {
                          final rem = taskRemaining[t.id] ?? 0;
                          return DropdownMenuItem<dynamic>(
                            value: t.id,
                            child: Text(
                                'Task ${t.id}${t.name.isNotEmpty ? " ${t.name}" : ""} – ${rem > 0 ? "${_fmtNum(rem)}/${_fmtNum(t.plannedHours)}h rim." : "completo"}',
                                style: TextStyle(
                                    color: rem > 0 ? kText : kTextDim,
                                    overflow: TextOverflow.ellipsis)),
                          );
                        }).toList(),
                        onChanged: (v) => setDlg(() => selectedTaskId = v),
                      );
                    }),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    value: selectedInstructor,
                    dropdownColor: kSurface,
                    isExpanded: true,
                    style: const TextStyle(color: kText),
                    decoration: InputDecoration(
                      labelText: (type == 'pratica' &&
                              _selected!.attendeeIds.length > 15)
                          ? 'Istruttore 1'
                          : 'Istruttore',
                      isDense: true,
                    ),
                    items: _instructorItems(
                      instructors: instructors,
                      submoduleCode: selSub?.code ?? '',
                      type: type,
                      moduleNumber: selectedModule,
                      current: selectedInstructor,
                      date: date,
                      timeSlot: slot,
                      taskId: type == 'pratica' ? selectedTaskId : null,
                    )
                        .where((i) =>
                            i.value == null || i.value != selectedInstructor2)
                        .toList(),
                    onChanged: (v) => setDlg(() => selectedInstructor = v),
                  ),
                  if (type == 'pratica' &&
                      _selected!.attendeeIds.length > 15) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: selectedInstructor2,
                      dropdownColor: kSurface,
                      isExpanded: true,
                      style: const TextStyle(color: kText),
                      decoration: const InputDecoration(
                          labelText: 'Istruttore 2', isDense: true),
                      items: _instructorItems(
                        instructors: instructors,
                        submoduleCode: selSub?.code ?? '',
                        type: type,
                        moduleNumber: selectedModule,
                        current: selectedInstructor2,
                        date: date,
                        timeSlot: slot,
                        taskId: selectedTaskId,
                      )
                          .where((i) =>
                              i.value == null || i.value != selectedInstructor)
                          .toList(),
                      onChanged: (v) => setDlg(() => selectedInstructor2 = v),
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
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  if (selectedModule == null) return;
                  final tid = type == 'pratica' ? selectedTaskId : null;
                  final id2 = type == 'pratica' &&
                          _selected!.attendeeIds.length > 15
                      ? selectedInstructor2
                      : null;
                  await _scheduleService.addLesson(
                    courseId: _selected!.id,
                    moduleNumber: selectedModule!,
                    submoduleCode: selectedSubmodule ?? '',
                    topic: selSub?.name ?? module?.name ?? '',
                    type: type,
                    date: date,
                    timeSlot: slot,
                    instructorId: selectedInstructor,
                    instructorId2: id2,
                    taskId: tid,
                    aula: selectedAula,
                  );
                  await _notifService.notifyLessonScheduled(
                    attendeeIds: _selected!.attendeeIds,
                    instructorId: selectedInstructor,
                    courseTitle: _selected!.title,
                    dateLabel: DateFormat('dd/MM/yyyy').format(date),
                    moduleLabel: selSub?.name ?? module?.name ?? '',
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
                  final tid = type == 'pratica' ? selectedTaskId : null;
                  final id2 = type == 'pratica' &&
                          _selected!.attendeeIds.length > 15
                      ? selectedInstructor2
                      : null;
                  await _scheduleService.addLesson(
                    courseId: _selected!.id,
                    moduleNumber: selectedModule!,
                    submoduleCode: selectedSubmodule ?? '',
                    topic: selSub?.name ?? module?.name ?? '',
                    type: type,
                    date: date,
                    timeSlot: slot,
                    instructorId: selectedInstructor,
                    instructorId2: id2,
                    taskId: tid,
                    aula: selectedAula,
                  );
                  await _notifService.notifyLessonScheduled(
                    attendeeIds: _selected!.attendeeIds,
                    instructorId: selectedInstructor,
                    courseTitle: _selected!.title,
                    dateLabel: DateFormat('dd/MM/yyyy').format(date),
                    moduleLabel: selSub?.name ?? module?.name ?? '',
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

  Future<void> _dropLesson(ScheduledLesson dragged, DateTime day, int slot) async {
    _previewTimer?.cancel();
    final moves = ScheduleService.planDrop(_allCourseLessons, dragged, day, slot);
    if (moves.isEmpty) return;

    // Istruttore già impegnato in un altro corso nella nuova ora: chiedi.
    final byId = {for (final l in _allCourseLessons) l.id: l};
    final conflicts = <String>[];
    for (final e in moves.entries) {
      final l = byId[e.key] ?? dragged;
      final (d, s) = e.value;
      for (final instr in [l.instructorId, l.instructorId2].whereType<String>()) {
        if (_scheduleService
            .lessonsForInstructorAt(instr, d, s)
            .any((o) => !moves.containsKey(o.id))) {
          conflicts.add('${DateFormat('EEE dd/MM', 'it').format(d)} $sª – '
              '${_normSubCode(l.submoduleCode)}');
        }
      }
    }
    if (conflicts.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kCard,
          title: const Text('Istruttore già impegnato',
              style: TextStyle(color: kText, fontSize: 14)),
          content: Text(
            'In queste ore l\'istruttore ha già lezione in un altro corso:\n'
            '${conflicts.take(10).join('\n')}'
            '${conflicts.length > 10 ? '\n… e altre ${conflicts.length - 10}' : ''}',
            style: const TextStyle(color: kTextDim, fontSize: 12),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annulla')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sposta comunque')),
          ],
        ),
      );
      if (ok != true) {
        _clearPreview();
        return;
      }
    }

    // L'anteprima resta a schermo fino al _refreshWeek: niente salto indietro.
    await _scheduleService.moveLessons(moves);
    _refreshWeek();
    if (mounted && moves.length > 1) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Lezione spostata, ${moves.length - 1} lezioni scalate')));
    }
  }

  /// L'anteprima (con le altre lezioni che scalano) parte solo dopo una breve
  /// sosta sulla stessa cella: passando di corsa non si muove nulla.
  void _setPreview(ScheduledLesson dragged, DateTime day, int slot) {
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        _preview = ScheduleService.planDrop(_allCourseLessons, dragged, day, slot);
        _dragId = dragged.id;
      });
    });
  }

  void _clearPreview() {
    _previewTimer?.cancel();
    if (_dragId == null || !mounted) return;
    setState(() {
      _preview = {};
      _dragId = null;
    });
  }

  /// Striscia laterale: tenendo una lezione trascinata sopra, cambia
  /// settimana dopo una pausa e poi ogni 1,4 s. Indietro non supera la
  /// settimana corrente (prima ci sono solo lezioni passate, bloccate).
  Widget _weekEdge({required bool next}) => DragTarget<ScheduledLesson>(
        onWillAcceptWithDetails: (_) {
          _edgeTimer?.cancel();
          _edgeTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
            if (next) {
              _nextWeek();
            } else if (_weekStart.isAfter(_mondayOf(DateTime.now()))) {
              _prevWeek();
            }
          });
          return true;
        },
        onLeave: (_) => _edgeTimer?.cancel(),
        onAcceptWithDetails: (_) => _edgeTimer?.cancel(),
        builder: (context, candidates, _) => candidates.isEmpty
            ? const SizedBox.expand()
            : Container(
                color: kPrimary.withOpacity(0.25),
                alignment: Alignment.center,
                child: Icon(next ? Icons.chevron_right : Icons.chevron_left,
                    color: kPrimary),
              ),
      );

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
    final typeInfo = _typeInfo;
    if (typeInfo == null) return;
    final attendees = _userService.getAllUsers()
        .where((u) => _selected!.attendeeIds.contains(u.id))
        .toList();
    if (attendees.isEmpty) return;

    // Bisogno reale per frequentatore/modulo (fonte canonica del corso):
    // teoria = ore oltre il 10% del modulo al netto dei recuperi, pratica =
    // 100% delle assenze non recuperate. Esce solo chi ha ore da recuperare.
    final allLessons = _scheduleService.getLessonsForCourse(_selected!.id);
    final moduleNumbers = {for (final m in typeInfo.modules) m.number};
    final need = <String, Map<int, ({int t, int p})>>{};
    for (final a in attendees) {
      final stats = _attendanceService.computePerModuleStats(
          _selected!.id, a.id, allLessons, modules: typeInfo.modules);
      stats.forEach((mod, s) {
        final t = s['toRecoverT'] ?? 0;
        final p = s['toRecoverP'] ?? 0;
        if (moduleNumbers.contains(mod) && (t > 0 || p > 0)) {
          (need[a.id] ??= {})[mod] = (t: t, p: p);
        }
      });
    }
    if (need.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessun frequentatore ha ore da recuperare')),
      );
      return;
    }

    // Ore da recuperare di un frequentatore; mod/type null = tutti.
    int hoursOf(String id, {int? mod, String? type}) {
      var h = 0;
      need[id]?.forEach((m, n) {
        if (mod != null && m != mod) return;
        if (type != 'pratica') h += n.t;
        if (type != 'teoria') h += n.p;
      });
      return h;
    }

    int? module;
    String? type;
    final sel = <String>{};

    // Chi è nello scope: i selezionati, altrimenti tutti quelli che devono recuperare.
    List<String> scope() => sel.isNotEmpty ? sel.toList() : need.keys.toList();
    int scopeHours(int mod, String tp) =>
        scope().fold(0, (s, id) => s + hoursOf(id, mod: mod, type: tp));
    List<int> modulesInScope() => [
          for (final m in typeInfo.modules)
            if (scope().any((id) => hoursOf(id, mod: m.number) > 0)) m.number,
        ];
    List<String> typesInScope() => [
          for (final tp in const ['pratica', 'teoria'])
            if (scope().any((id) => hoursOf(id, mod: module, type: tp) > 0)) tp,
        ];

    // Tiene coerenti modulo, tipo e selezione: mostra solo ciò che è da recuperare.
    void normalize() {
      final mods = modulesInScope();
      if (!mods.contains(module)) module = null;
      if (module == null && mods.length == 1) module = mods.first;
      if (module == null) {
        type = null;
        return;
      }
      sel.removeWhere((id) => hoursOf(id, mod: module) == 0);
      final types = typesInScope();
      if (!types.contains(type)) type = types.isEmpty ? null : types.first;
      sel.removeWhere((id) => hoursOf(id, mod: module, type: type) == 0);
    }

    normalize();
    final user = ref.read(authProvider).currentUser;

    Widget badge(String txt, Color c, bool selected) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: c.withOpacity(selected ? 0.3 : 0.15),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(txt,
              style: TextStyle(
                  color: selected ? Colors.white : c,
                  fontSize: 9,
                  fontWeight: FontWeight.bold)),
        );

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final types = module == null ? <String>[] : typesInScope();
          final shown = attendees
              .where((a) => hoursOf(a.id, mod: module, type: type) > 0)
              .toList()
            ..sort((a, b) {
              final pA = hoursOf(a.id, mod: module, type: 'pratica') > 0 ? 0 : 1;
              final pB = hoursOf(b.id, mod: module, type: 'pratica') > 0 ? 0 : 1;
              if (pA != pB) return pA - pB;
              return hoursOf(b.id, mod: module, type: type)
                  .compareTo(hoursOf(a.id, mod: module, type: type));
            });
          return AlertDialog(
            backgroundColor: kCard,
            title: Text(
              'Recupero – ${DateFormat('dd/MM/yyyy').format(day)}',
              style: const TextStyle(color: kText, fontSize: 14),
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Modulo recuperato:', style: TextStyle(color: kTextDim, fontSize: 12)),
                    const SizedBox(height: 6),
                    DropdownButton<int>(
                      value: module,
                      isExpanded: true,
                      dropdownColor: kSurface,
                      style: const TextStyle(color: kText),
                      hint: const Text('Scegli il modulo', style: TextStyle(color: kTextDim)),
                      items: [
                        for (final m in typeInfo.modules)
                          if (modulesInScope().contains(m.number))
                            DropdownMenuItem(
                              value: m.number,
                              child: Row(
                                children: [
                                  if (scopeHours(m.number, 'pratica') > 0) ...[
                                    badge('P ${scopeHours(m.number, 'pratica')}h', kError, false),
                                    const SizedBox(width: 4),
                                  ],
                                  if (scopeHours(m.number, 'teoria') > 0) ...[
                                    badge('T ${scopeHours(m.number, 'teoria')}h', kWarning, false),
                                    const SizedBox(width: 4),
                                  ],
                                  Flexible(
                                    child: Text('M${m.displayCode} – ${m.name}',
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                            ),
                      ],
                      onChanged: (v) => setDlg(() {
                        module = v;
                        normalize();
                      }),
                    ),
                    if (module != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        types.length > 1
                            ? 'Teoria e pratica da recuperare: scegli cosa si recupera'
                            : 'Si recupera:',
                        style: const TextStyle(color: kTextDim, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final tp in types)
                            ChoiceChip(
                              label: Text(
                                '${tp == 'pratica' ? 'Pratica' : 'Teoria'} · ${scopeHours(module!, tp)}h',
                                style: TextStyle(
                                    color: type == tp ? Colors.white : kText, fontSize: 11),
                              ),
                              selected: type == tp,
                              selectedColor: kAccent.withOpacity(0.8),
                              backgroundColor: kSurface,
                              onSelected: (_) => setDlg(() {
                                type = tp;
                                normalize();
                              }),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text('Frequentatori che devono recuperare:',
                        style: TextStyle(color: kTextDim, fontSize: 12)),
                    const SizedBox(height: 2),
                    const Text(
                      'Solo chi ha ore da recuperare (teoria oltre il 10%, pratica 100%). Scegliendo prima il frequentatore restano solo le sue materie.',
                      style: TextStyle(color: kTextDim, fontSize: 10, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final a in shown)
                          () {
                            final selected = sel.contains(a.id);
                            final p = hoursOf(a.id, mod: module, type: 'pratica');
                            final t = hoursOf(a.id, mod: module, type: 'teoria');
                            return FilterChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (p > 0 && type != 'teoria') ...[
                                    badge('P ${p}h', kError, selected),
                                    const SizedBox(width: 4),
                                  ],
                                  if (t > 0 && type != 'pratica') ...[
                                    badge('T ${t}h', kWarning, selected),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(a.fullName,
                                      style: TextStyle(
                                          color: selected ? Colors.white : kText,
                                          fontSize: 11)),
                                ],
                              ),
                              selected: selected,
                              selectedColor: kAccent.withOpacity(0.8),
                              backgroundColor: kSurface,
                              side: selected
                                  ? null
                                  : BorderSide(color: p > 0 ? kError : kWarning),
                              onSelected: (v) => setDlg(() {
                                if (v) {
                                  sel.add(a.id);
                                } else {
                                  sel.remove(a.id);
                                }
                                normalize();
                              }),
                            );
                          }(),
                      ],
                    ),
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
                onPressed: sel.isEmpty || module == null || type == null
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        for (final id in sel) {
                          await _attendanceService.saveRecovery(
                            courseId: _selected!.id,
                            attendeeId: id,
                            confirmedBy: user?.id ?? '',
                            recoveredModule: module!,
                            recoveryDate: day,
                            recoveredType: type,
                          );
                        }
                        _refreshWeek();
                      },
                child: const Text('Salva recuperi'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteLesson(ScheduledLesson lesson) async {
    await _scheduleService.deleteLesson(lesson.id);
    _refreshWeek();
  }

  Future<void> _editNote(DateTime date, int slot, SlotNote? existing) async {
    if (_selected == null) return;
    final ctrl = TextEditingController(text: existing?.text ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing != null ? 'Modifica nota' : 'Aggiungi nota'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Es. Solo 4 ore oggi — visita medica',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Elimina', style: TextStyle(color: kError)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result.isEmpty && existing != null) {
      await _scheduleService.deleteNote(existing.id);
    } else if (result.isNotEmpty) {
      await _scheduleService.addNote(
        courseId: _selected!.id,
        date: date,
        timeSlot: slot,
        text: result,
      );
    }
    _refreshWeek();
  }

  Future<void> _editLessonInstructor(ScheduledLesson lesson) async {
    if (_selected == null || _typeInfo == null) return;
    final instructors = _userService.getInstructors();

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
      final label = info != null
          ? 'M${_refService.moduleLabel(info.$1)} $code – ${info.$2}'
          : code;
      submoduleOptions.add((code, label));
    }

    String? selectedInstructor = lesson.instructorId;
    String? selectedInstructor2 = lesson.instructorId2;
    String selectedSubmodule = lesson.submoduleCode;
    bool recompile = true;
    final lessonType = isTheory ? 'teoria' : 'pratica';
    int selectedAula =
        lesson.aula ?? _selected!.resolvedDefaultAula ?? 3;

    // Assenze frequentatori per quest'ora: pre-compilate dai record esistenti.
    final attendees = _userService.getAllUsers()
        .where((u) => _selected!.attendeeIds.contains(u.id))
        .toList();
    final initialAbsent = <String>{
      for (final r in _attendanceService.getRecordsForLesson(lesson.id))
        if (!r.present) r.attendeeId,
    };
    final absent = <String>{...initialAbsent};

    Future<void> saveAbsences({required bool force}) async {
      // Su 'Salva' scrive solo se modificate (evita record per lezioni
      // future); alla validazione registra sempre l'appello completo.
      if (!force &&
          absent.length == initialAbsent.length &&
          absent.containsAll(initialAbsent)) {
        return;
      }
      final user = ref.read(authProvider).currentUser;
      await _attendanceService.saveAttendance(
        scheduleId: lesson.id,
        courseId: _selected!.id,
        attendeeIds: _selected!.attendeeIds,
        presence: {
          for (final id in _selected!.attendeeIds) id: !absent.contains(id),
        },
        confirmedBy: user?.id ?? '',
      );
    }

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
            child: SingleChildScrollView(
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
                DropdownButtonFormField<int>(
                  value: selectedAula,
                  dropdownColor: kSurface,
                  isExpanded: true,
                  style: const TextStyle(color: kText, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: isTheory
                        ? 'Aula'
                        : 'Aula (Excel pratica = HANGAR 6)',
                    isDense: true,
                  ),
                  items: [
                    for (var i = 1; i <= 7; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text('Aula $i',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) =>
                      setDlg(() => selectedAula = v ?? selectedAula),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: selectedInstructor,
                  dropdownColor: kSurface,
                  isExpanded: true,
                  style: const TextStyle(color: kText),
                  decoration: InputDecoration(
                    labelText: (!isTheory &&
                            _selected!.attendeeIds.length > 15)
                        ? 'Istruttore 1'
                        : 'Istruttore',
                    isDense: true,
                  ),
                  items: _instructorItems(
                    instructors: instructors,
                    submoduleCode: selectedSubmodule,
                    type: lessonType,
                    moduleNumber: refSubInfo[selectedSubmodule]?.$1,
                    current: selectedInstructor,
                    date: lesson.date,
                    timeSlot: lesson.timeSlot,
                    excludeLessonId: lesson.id,
                    taskId: lesson.taskId,
                  )
                      .where((i) =>
                          i.value == null || i.value != selectedInstructor2)
                      .toList(),
                  onChanged: (v) => setDlg(() => selectedInstructor = v),
                ),
                if (!isTheory && _selected!.attendeeIds.length > 15) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: selectedInstructor2,
                    dropdownColor: kSurface,
                    isExpanded: true,
                    style: const TextStyle(color: kText),
                    decoration: const InputDecoration(
                        labelText: 'Istruttore 2', isDense: true),
                    items: _instructorItems(
                      instructors: instructors,
                      submoduleCode: selectedSubmodule,
                      type: lessonType,
                      moduleNumber: refSubInfo[selectedSubmodule]?.$1,
                      current: selectedInstructor2,
                      date: lesson.date,
                      timeSlot: lesson.timeSlot,
                      excludeLessonId: lesson.id,
                      taskId: lesson.taskId,
                    )
                        .where((i) =>
                            i.value == null || i.value != selectedInstructor)
                        .toList(),
                    onChanged: (v) => setDlg(() => selectedInstructor2 = v),
                  ),
                ],
                if (attendees.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Assenti in quest\'ora:',
                        style: TextStyle(color: kTextDim, fontSize: 12)),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: attendees.map((a) {
                        final sel = absent.contains(a.id);
                        return FilterChip(
                          label: Text(a.fullName,
                              style: TextStyle(
                                  color: sel ? Colors.white : kTextDim,
                                  fontSize: 11)),
                          selected: sel,
                          selectedColor: kError.withOpacity(0.8),
                          checkmarkColor: Colors.white,
                          backgroundColor: kSurface,
                          onSelected: (v) => setDlg(() {
                            if (v) {
                              absent.add(a.id);
                            } else {
                              absent.remove(a.id);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  ),
                ],
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
                        final id2 = !isTheory &&
                                _selected!.attendeeIds.length > 15
                            ? selectedInstructor2
                            : null;
                        if (selectedInstructor != lesson.instructorId ||
                            id2 != lesson.instructorId2 ||
                            selectedAula != lesson.aula) {
                          await _scheduleService.updateLesson(lesson.copyWith(
                            instructorId: selectedInstructor,
                            instructorId2: id2,
                            aula: selectedAula,
                          ));
                        }
                        // La validazione registra sempre l'appello:
                        // tutti presenti tranne i segnati assenti.
                        await saveAbsences(force: true);
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
                String newTopic = lesson.topic;
                if (subChanged) {
                  for (final m in _typeInfo!.modules) {
                    final sub = m.submodules
                        .where((s) => s.code == selectedSubmodule)
                        .firstOrNull;
                    if (sub != null) {
                      newModuleNum = m.number;
                      newTopic = sub.name;
                      break;
                    }
                  }
                }
                await _scheduleService.updateLesson(lesson.copyWith(
                  instructorId: selectedInstructor,
                  instructorId2: !isTheory &&
                          _selected!.attendeeIds.length > 15
                      ? selectedInstructor2
                      : null,
                  submoduleCode: selectedSubmodule,
                  moduleNumber: newModuleNum,
                  topic: newTopic,
                  aula: selectedAula,
                ));
                if (selectedInstructor != null &&
                    selectedInstructor != lesson.instructorId) {
                  await _notifService.notifyLessonChanged(
                    instructorId: selectedInstructor!,
                    courseTitle: _selected!.title,
                    dateLabel: DateFormat('dd/MM/yyyy').format(lesson.date),
                    moduleLabel: newTopic,
                  );
                }
                await saveAbsences(force: false);
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

  Future<void> _exportWeeklyExcel() async {
    if (_selected == null) return;
    final course = _selected!;
    final subNameMap = <String, String>{
      for (final m in _typeInfo?.modules ?? [])
        for (final s in m.submodules) s.code: s.name,
    };
    final instructors = {
      for (final u in _userService.getInstructors()) u.id: u,
    };
    final directors = course.directorIds
        .map(_userService.findById)
        .whereType<AppUser>()
        .toList();
    final attendees = course.attendeeIds
        .map(_userService.findById)
        .whereType<AppUser>()
        .toList();
    try {
      await ExcelExportService.downloadWeeklySchedule(
        course: course,
        typeInfo: _typeInfo,
        weekStart: _weekStart,
        weekLessons: _weekLessons,
        weekNotes: _weekNotes,
        instructors: instructors,
        attendees: attendees,
        directors: directors,
        subNames: subNameMap,
        allCourseLessons: _allCourseLessons,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore generazione Excel: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_courses.isEmpty) {
      return const Center(child: Text('Nessun corso assegnato', style: TextStyle(color: kTextDim)));
    }

    final weekDays = List.generate(
        7, (i) => DateTime(_weekStart.year, _weekStart.month, _weekStart.day + i));
    final allSlots = _typeInfo?.schedule.mondayThursday ?? [];
    final recoveryLessons = _weekLessons.where((l) => l.timeSlot == 0).toList();
    final regularLessons = _weekLessons.where((l) => l.timeSlot > 0).toList();
    final shownBefore = _shownPreview;
    _shownPreview = _preview;
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
    final taskCnt = <String, int>{};
    // Key: "YYYY-MM-DD_slot_taskId" — deterministic across independent getAllLessons() calls
    final taskOrdinals = <String, int>{};
    for (final l in sortedAll) {
      if (!l.isTheory && l.taskId != null) {
        final k = l.taskId.toString();
        taskCnt[k] = (taskCnt[k] ?? 0) + 1;
        final dateStr = l.date.toIso8601String().split('T').first;
        taskOrdinals['${dateStr}_${l.timeSlot}_$k'] = taskCnt[k]!;
      }
    }
    final taskPlanMap = <int, double>{};
    for (final m in _typeInfo?.modules ?? <ModuleInfo>[]) {
      for (final s in m.submodules) {
        for (final t in s.practicalTasks) {
          taskPlanMap.putIfAbsent(t.id, () => t.plannedHours);
        }
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
              InkWell(
                onTap: _pickWeek,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.calendar_month, size: 16, color: kAccent),
                    const SizedBox(width: 6),
                    Text(
                      '${DateFormat('dd/MM').format(_weekStart)} – ${DateFormat('dd/MM/yyyy').format(DateTime(_weekStart.year, _weekStart.month, _weekStart.day + 6))}',
                      style: const TextStyle(color: kText, fontSize: 13),
                    ),
                  ]),
                ),
              ),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: _nextWeek, color: kText),
              IconButton(
                icon: const Icon(Icons.today, size: 18),
                tooltip: 'Settimana corrente',
                onPressed: _goToday,
                color: kTextDim,
              ),
              const SizedBox(width: 8),
              if (_selected != null)
                PopupMenuButton<String>(
                  tooltip: 'Impostazioni planner',
                  icon: const Icon(Icons.settings, size: 20, color: kTextDim),
                  color: kCard,
                  onSelected: (v) {
                    switch (v) {
                      case 'ps':
                        _showPsHeaderSettings();
                      case 'excluded':
                        _showExcludedDates();
                      case 'generate':
                        _generateRemaining();
                      case 'delete':
                        _deleteUnconfirmedLessons();
                      case 'excel':
                        _exportWeeklyExcel();
                    }
                  },
                  itemBuilder: (_) {
                    final n = _selected!.excludedDates.length;
                    return [
                      _menuItem('ps', Icons.edit_calendar, 'Dati corso PS'),
                      _menuItem('excluded', Icons.event_busy,
                          'Giorni esclusi${n > 0 ? ' ($n)' : ''}'),
                      _menuItem('excel', Icons.table_view, 'Excel PS'),
                      const PopupMenuDivider(),
                      _menuItem('generate', Icons.auto_fix_high, 'Genera lezioni rimanenti'),
                      _menuItem('delete', Icons.delete_sweep, 'Cancella non svolte',
                          color: kError),
                    ];
                  },
                ),
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
          child: Stack(
            fit: StackFit.expand,
            children: [
          // Griglia adattiva: colonne e righe riempiono lo spazio disponibile;
          // sotto i minimi restano gli scroll (finestre molto piccole).
          LayoutBuilder(builder: (context, box) {
            final dayW = ((box.maxWidth - 48 - 80) / 7).clamp(110.0, 400.0);
            // 120 = intestazione giorni + riga recuperi.
            final rowH = ((box.maxHeight - 120) / allSlots.length).clamp(84.0, 240.0);
            return Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Table(
                  border: TableBorder.all(color: kBorder, width: 0.5),
                  defaultColumnWidth: FixedColumnWidth(dayW),
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
                            if (!ScheduleService.isRegularSlot(day, slot.slot)) {
                              return TableCell(
                                child: InkWell(
                                  onTap: () => _addRecovery(day),
                                  child: Tooltip(
                                    message: 'Fuori orario regolare — disponibile per recuperi',
                                    waitDuration: const Duration(milliseconds: 500),
                                    child: Container(
                                      height: rowH,
                                      color: kWarning.withOpacity(0.05),
                                      child: const Center(
                                        child: Icon(Icons.restore, color: kWarning, size: 14),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }
                            final lesson = regularLessons
                                .where((l) => _sameDay(l.date, day) && l.timeSlot == slot.slot)
                                .firstOrNull;
                            // In anteprima: chi arriva qui, altrimenti chi c'è se non se ne va.
                            final shown = _preview.isEmpty
                                ? lesson
                                : _allCourseLessons.where((l) {
                                      final p = _preview[l.id];
                                      return p != null && _sameDay(p.$1, day) && p.$2 == slot.slot;
                                    }).firstOrNull ??
                                    (_preview.containsKey(lesson?.id) ? null : lesson);
                            final slotNote = _weekNotes
                                .where((n) => _sameDay(n.date, day) && n.timeSlot == slot.slot)
                                .firstOrNull;
                            final dayStr = DateFormat('yyyy-MM-dd').format(day);
                            return TableCell(
                              child: DragTarget<ScheduledLesson>(
                                onWillAcceptWithDetails: (d) {
                                  final ok = d.data.id != lesson?.id &&
                                      (lesson == null || !ScheduleService.isFrozen(lesson)) &&
                                      !(_selected?.excludedDates.contains(dayStr) ?? false);
                                  if (ok) _setPreview(d.data, day, slot.slot);
                                  return ok;
                                },
                                // Leave e enter arrivano nello stesso evento: un solo build.
                                onLeave: (_) => _clearPreview(),
                                onAcceptWithDetails: (d) =>
                                    _dropLesson(d.data, day, slot.slot),
                                builder: (context, candidates, _) => Container(
                                  foregroundDecoration: candidates.isEmpty
                                      ? null
                                      : BoxDecoration(
                                          border: Border.all(color: kPrimary, width: 2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                  child: shown == null
                                  ? InkWell(
                                      onTap: () => _addLesson(day, slot.slot),
                                      onSecondaryTap: () => _editNote(day, slot.slot, slotNote),
                                      onLongPress: () => _editNote(day, slot.slot, slotNote),
                                      child: SizedBox(
                                        height: rowH,
                                        child: Stack(children: [
                                          Align(
                                            alignment: slotNote != null ? Alignment.topLeft : Alignment.center,
                                            child: slotNote != null
                                                ? Padding(
                                                    padding: const EdgeInsets.fromLTRB(6, 6, 24, 6),
                                                    child: Text(slotNote.text,
                                                        style: const TextStyle(fontSize: 10, color: kWarning),
                                                        maxLines: ((rowH - 12) / 13).floor().clamp(1, 14),
                                                        overflow: TextOverflow.ellipsis),
                                                  )
                                                : const Icon(Icons.add, color: kBorder, size: 16),
                                          ),
                                          Positioned(
                                            top: 2,
                                            right: 2,
                                            child: GestureDetector(
                                              onTap: () => _editNote(day, slot.slot, slotNote),
                                              child: Padding(
                                                padding: const EdgeInsets.all(3),
                                                child: Icon(
                                                    slotNote != null
                                                        ? Icons.sticky_note_2
                                                        : Icons.sticky_note_2_outlined,
                                                    size: 12,
                                                    color: slotNote != null ? kWarning : kBorder),
                                              ),
                                            ),
                                          ),
                                        ]),
                                      ),
                                    )
                                  : _slide(shown, day, slot.slot, shownBefore,
                                      _lessonCell(shown, subNameMap, instrNames,
                                          ordinals: lessonOrdinals,
                                          planT: subPlanT, planP: subPlanP,
                                          taskOrdinals: taskOrdinals, taskPlanMap: taskPlanMap,
                                          height: rowH,
                                          note: slotNote,
                                          onNote: () => _editNote(day, slot.slot, slotNote))),
                                ),
                              ),
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
          );
          }),
              Positioned(left: 0, top: 0, bottom: 0, width: 28,
                  child: _weekEdge(next: false)),
              Positioned(right: 0, top: 0, bottom: 0, width: 28,
                  child: _weekEdge(next: true)),
            ],
          ),
        ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label,
          {Color color = kText}) =>
      PopupMenuItem<String>(
        value: value,
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: color, fontSize: 13)),
        ]),
      );

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

  /// Intestazione giorno con "Assenti" (giornata intera) e "Valida N"
  /// quando ci sono ore non confermate con istruttore assegnato.
  Widget _dayHeaderCell(DateTime d) {
    final dayLessons = _weekLessons
        .where((l) => _sameDay(l.date, d) && l.timeSlot > 0)
        .toList();
    final pending = dayLessons
        .where((l) => !l.confirmed && l.instructorId != null)
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
          if (dayLessons.isNotEmpty && _selected != null)
            Tooltip(
              message:
                  'Segna assenti per tutte le ore del giorno\n(le assenze orarie restano modificabili)',
              child: InkWell(
                onTap: () => _markDayAbsences(d, dayLessons),
                child: const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_off, size: 11, color: kError),
                      SizedBox(width: 3),
                      Text('Assenti',
                          style: TextStyle(
                              color: kError,
                              fontSize: 9,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
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

  /// Assenti su tutte le ore del giorno. Le assenze orarie già registrate
  /// restano; chi viene tolto dalla selezione giornata torna presente solo
  /// se era assente su tutte le ore (non tocca le assenze di una sola ora).
  Future<void> _markDayAbsences(
      DateTime day, List<ScheduledLesson> dayLessons) async {
    if (_selected == null || dayLessons.isEmpty) return;
    final attendees = _userService
        .getAllUsers()
        .where((u) => _selected!.attendeeIds.contains(u.id))
        .toList();
    if (attendees.isEmpty) return;

    final initialAbsent = <String>{
      for (final a in attendees)
        if (dayLessons.every((l) {
          final r = _attendanceService.getRecord(l.id, a.id);
          return r != null && !r.present;
        }))
          a.id,
    };
    final absent = <String>{...initialAbsent};

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: kCard,
          title: Text(
            'Assenti · ${DateFormat('EEE dd/MM', 'it').format(day)}',
            style: const TextStyle(color: kText, fontSize: 14),
          ),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Assenti per tutte le ${dayLessons.length} ore. '
                    'Per un\'assenza su una sola ora usa la modifica della cella.',
                    style: const TextStyle(color: kTextDim, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: attendees.map((a) {
                      final sel = absent.contains(a.id);
                      return FilterChip(
                        label: Text(a.fullName,
                            style: TextStyle(
                                color: sel ? Colors.white : kTextDim,
                                fontSize: 11)),
                        selected: sel,
                        selectedColor: kError.withOpacity(0.8),
                        checkmarkColor: Colors.white,
                        backgroundColor: kSurface,
                        onSelected: (v) => setDlg(() {
                          if (v) {
                            absent.add(a.id);
                          } else {
                            absent.remove(a.id);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla', style: TextStyle(color: kTextDim)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (absent.length == initialAbsent.length &&
        absent.containsAll(initialAbsent)) {
      return;
    }

    final add = absent.difference(initialAbsent);
    final remove = initialAbsent.difference(absent);
    final user = ref.read(authProvider).currentUser;
    final batch = <
        ({
          String scheduleId,
          String courseId,
          List<String> attendeeIds,
          Map<String, bool> presence,
        })>[];

    for (final lesson in dayLessons) {
      final hourAbsent = <String>{
        for (final r in _attendanceService.getRecordsForLesson(lesson.id))
          if (!r.present) r.attendeeId,
      };
      hourAbsent.addAll(add);
      hourAbsent.removeAll(remove);
      batch.add((
        scheduleId: lesson.id,
        courseId: _selected!.id,
        attendeeIds: _selected!.attendeeIds,
        presence: {
          for (final id in _selected!.attendeeIds) id: !hourAbsent.contains(id),
        },
      ));
    }

    await _attendanceService.saveAttendanceBatch(
      batch,
      confirmedBy: user?.id ?? '',
    );
    _refreshWeek();
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
          '${DateFormat('EEEE dd/MM/yyyy', 'it').format(day)} per conto degli istruttori assegnati?\n\n'
          'L\'appello userà le assenze già segnate (giornata o ora singola); '
          'gli altri frequentatori risultano presenti.',
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
    if (ok != true || _selected == null) return;

    // Un solo write records + un solo write schedules (niente N+1).
    await _attendanceService.saveAttendanceBatch(
      [
        for (final lesson in pending)
          (
            scheduleId: lesson.id,
            courseId: _selected!.id,
            attendeeIds: _selected!.attendeeIds,
            presence: {
              for (final id in _selected!.attendeeIds)
                id: _attendanceService.getRecord(lesson.id, id)?.present ?? true,
            },
          ),
      ],
      confirmedBy: user?.id ?? '',
    );
    await _scheduleService.confirmLessons(
        pending.map((l) => l.id).toList(), user?.id ?? '');
    _refreshWeek();
  }

  /// Fa scivolare la lezione dalla cella in cui era mostrata al build
  /// precedente; la trascinata resta in trasparenza dove cadrà.
  Widget _slide(ScheduledLesson l, DateTime day, int slot,
      Map<String, (DateTime, int)> before, Widget child) {
    if (l.id == _dragId) return Opacity(opacity: 0.3, child: child);
    final (fromDay, fromSlot) = before[l.id] ?? (l.date, l.timeSlot);
    // Ore/24 arrotondate: col cambio d'ora un giorno può durare 23 o 25 h.
    final dx = (fromDay.difference(day).inHours / 24).round().clamp(-7, 7);
    final dy = (fromSlot - slot).clamp(-6, 6);
    return TweenAnimationBuilder<Offset>(
      key: ValueKey(l.id),
      tween: Tween(begin: Offset(dx.toDouble(), dy.toDouble()), end: Offset.zero),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      builder: (_, o, c) => FractionalTranslation(translation: o, child: c),
      child: child,
    );
  }

  Widget _lessonCell(
    ScheduledLesson lesson,
    Map<String, String> subNames,
    Map<String, String> instrNames, {
    required Map<String, int> ordinals,
    required Map<String, int> planT,
    required Map<String, int> planP,
    required Map<String, int> taskOrdinals,
    required Map<int, double> taskPlanMap,
    required double height,
    required SlotNote? note,
    required VoidCallback onNote,
  }) {
    final isTheory = lesson.type != 'pratica';
    final nc = _normSubCode(lesson.submoduleCode);
    final base = moduleColor(lesson.moduleNumber);
    final color = lesson.confirmed ? base : base.withOpacity(0.5);

    final displayTopic = '$nc – ${subNames[nc] ?? lesson.topic}';

    final rawOrd = ordinals[lesson.id] ?? 1;
    final typeLabel = isTheory ? 'T' : 'P';
    final String hoursStr;
    if (!isTheory && lesson.taskId != null) {
      final taskPlan = taskPlanMap[lesson.taskId] ?? 0.0;
      final taskDateStr = lesson.date.toIso8601String().split('T').first;
      final taskKey = '${taskDateStr}_${lesson.timeSlot}_${lesson.taskId}';
      final taskOrd = taskOrdinals[taskKey] ?? rawOrd;
      hoursStr = taskPlan > 0
          ? 'P $taskOrd/${_fmtNum(taskPlan)}h'
          : 'P ${taskOrd}h';
    } else {
      final plan = isTheory ? (planT[nc] ?? 0) : (planP[nc] ?? 0);
      // Le ore oltre il piano ufficiale sono recuperi: il contatore non deve
      // mai superare il monte ore del programma.
      final isExtra = plan > 0 && rawOrd > plan;
      final conf = isExtra ? plan : rawOrd;
      hoursStr = plan > 0
          ? '$typeLabel $conf/$plan h${isExtra ? ' (rec.)' : ''}'
          : '$typeLabel ${rawOrd}h';
    }
    final instrName = lesson.instructorId != null
        ? (instrNames[lesson.instructorId!] ?? '?')
        : null;
    final instrName2 = lesson.instructorId2 != null
        ? (instrNames[lesson.instructorId2!] ?? '?')
        : null;
    final instrLabel = [
      if (instrName != null) instrName,
      if (instrName2 != null) instrName2,
    ].join(' · ');

    final task = lesson.taskId != null ? _refService.findTask(_typeInfo, lesson.taskId) : null;
    final absentNames = _weekAbsent[lesson.id] ?? const <String>[];
    final tooltipMsg = [
      displayTopic,
      if (task != null && task.name.isNotEmpty) '🔧 Task ${task.programTaskId}: ${task.name}',
      if (instrLabel.isNotEmpty) '👤 $instrLabel',
      if (absentNames.isNotEmpty) 'Assenti (${absentNames.length}): ${absentNames.join(', ')}',
      if (note != null) 'Nota: ${note.text}',
      hoursStr,
    ].join('\n');
    // Righe disponibili al titolo: cresce con la cella, cede spazio alla nota.
    final topicLines =
        ((height - 56 - (note != null ? 26 : 0)) / 13).floor().clamp(1, 9);

    final cell = GestureDetector(
      onTap: () => _editLessonInstructor(lesson),
      onSecondaryTap: () => _deleteLesson(lesson),
      child: Tooltip(
        message: tooltipMsg,
        waitDuration: const Duration(milliseconds: 500),
        child: Container(
        height: height,
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
                    style: const TextStyle(
                        color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 4),
              Text('M${_refService.moduleLabel(lesson.moduleNumber)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 9)),
              const Spacer(),
              if (absentNames.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: kWarning.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.person_off, color: kWarning, size: 10),
                    const SizedBox(width: 2),
                    Text('${absentNames.length}',
                        style: const TextStyle(
                            color: kWarning, fontSize: 9, fontWeight: FontWeight.bold)),
                  ]),
                ),
                const SizedBox(width: 3),
              ],
              if (lesson.confirmed)
                const Icon(Icons.check_circle, color: kAccent, size: 10),
              GestureDetector(
                onTap: onNote,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                      note != null
                          ? Icons.sticky_note_2
                          : Icons.sticky_note_2_outlined,
                      color: note != null ? kWarning : Colors.white38,
                      size: 12),
                ),
              ),
              GestureDetector(
                onTap: () => _deleteLesson(lesson),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: const Icon(Icons.close, color: kError, size: 14),
                ),
              ),
            ]),
            const SizedBox(height: 2),
            Expanded(
              child: Text(displayTopic,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                  maxLines: topicLines,
                  overflow: TextOverflow.ellipsis),
            ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(note.text,
                    style: const TextStyle(color: kWarning, fontSize: 9),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            Row(children: [
              Expanded(
                child: Text(hoursStr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 9,
                        fontWeight: FontWeight.w500)),
              ),
              if (lesson.taskId != null) ...[
                const SizedBox(width: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: kAccent.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                      'T${lesson.taskId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                ),
              ],
              const SizedBox(width: 2),
              if (instrLabel.isNotEmpty)
                Flexible(
                  child: Text(instrLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                )
              else
                const Icon(Icons.person_outline, size: 9, color: Colors.white54),
            ]),
          ],
        ),
      ),
    ));
    // Confermate = presenze già registrate su quella data/ora: non si spostano.
    if (lesson.confirmed) return cell;
    return Draggable<ScheduledLesson>(
      data: lesson,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 156,
          height: 60,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: base, width: 1.5),
          ),
          child: Text(displayTopic,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 10)),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: cell),
      child: cell,
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return _sameDay(d, now);
  }
}
