import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
import '../../models/reference_models.dart';
import '../../models/schedule_models.dart';
import '../../models/user_models.dart';
import '../../services/attendance_service.dart';
import '../../services/course_service.dart';
import '../../services/reference_service.dart';
import '../../services/schedule_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';

/// Recupero raggruppato per data+modulo+tipo+sottomodulo: più frequentatori
/// che recuperano la stessa cosa nello stesso giorno appaiono in un'unica riga.
class _RecoveryEntry {
  final DateTime date;
  final int moduleNumber;
  final String? type; // 'teoria' | 'pratica' | null
  final String? submoduleCode;
  final List<AppUser> attendees;
  final List<AttendanceRecord> records;

  const _RecoveryEntry({
    required this.date,
    required this.moduleNumber,
    required this.type,
    required this.submoduleCode,
    required this.attendees,
    required this.records,
  });
}

/// Voce dello storico unificato: una lezione reale oppure un recupero.
class _LogEntry {
  final ScheduledLesson? lesson;
  final _RecoveryEntry? recovery;

  _LogEntry.lesson(ScheduledLesson l)
      : lesson = l,
        recovery = null;
  _LogEntry.recovery(_RecoveryEntry r)
      : lesson = null,
        recovery = r;

  DateTime get date => lesson?.date ?? recovery!.date;
}

class DirectorLessonsLogTab extends ConsumerStatefulWidget {
  final String userId;
  /// Se valorizzato (es. admin), usa questi corsi al posto di quelli del direttore.
  final List<Course>? coursesOverride;
  /// Blocca il selettore su un corso (es. dettaglio corso admin).
  final String? fixedCourseId;

  const DirectorLessonsLogTab({
    super.key,
    required this.userId,
    this.coursesOverride,
    this.fixedCourseId,
  });

  @override
  ConsumerState<DirectorLessonsLogTab> createState() => _DirectorLessonsLogTabState();
}

class _DirectorLessonsLogTabState extends ConsumerState<DirectorLessonsLogTab> {
  final _courseService = CourseService();
  final _refService = ReferenceService();
  final _scheduleService = ScheduleService();
  final _attendanceService = AttendanceService();
  final _userService = UserService();

  List<Course> _courses = [];
  Course? _selected;
  CourseTypeInfo? _typeInfo;
  List<ScheduledLesson> _allLessons = [];
  Map<String, int> _ordinals = {};
  List<AppUser> _attendees = [];
  List<AppUser> _instructors = [];
  final Map<String, String> _instructorNameById = {};

  DateTime? _fDateFrom;
  DateTime? _fDateTo;
  int? _fModule;
  String? _fSubmodule;
  String? _fTaskId;
  String? _fInstructorId;
  String? _fAbsentId;
  String? _fRecoveringId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _courses = widget.coursesOverride ?? _courseService.getCoursesForDirector(widget.userId);
    if (widget.fixedCourseId != null) {
      Course? fixed;
      for (final c in _courses) {
        if (c.id == widget.fixedCourseId) {
          fixed = c;
          break;
        }
      }
      _selected = fixed ?? (_courses.isNotEmpty ? _courses.first : null);
    } else if (_selected == null && _courses.isNotEmpty) {
      _selected = _courses.first;
    }
    _refresh();
  }

  void _refresh() {
    if (_selected == null) return;
    setState(() {
      _typeInfo = _refService.getEffectiveCourseType(_selected!.courseTypeId, _selected!.extensionTypeId, _selected!.mamlCombinationId);
      _allLessons = _scheduleService.getLessonsForCourse(_selected!.id)
          .where((l) => l.confirmed && l.timeSlot > 0)
          .toList();
      _ordinals = ScheduleService.ordinals(_allLessons, _ordKey);
      _attendees = _userService.getAllUsers().where((u) => _selected!.attendeeIds.contains(u.id)).toList();
      final usedInstructorIds = _allLessons.map((l) => l.instructorId).whereType<String>().toSet();
      _instructorNameById
        ..clear()
        ..addEntries(_userService.getInstructors().map((i) => MapEntry(i.id, i.fullName)));
      _instructors = _userService.getInstructors().where((i) => usedInstructorIds.contains(i.id)).toList()
        ..sort((a, b) => a.cognome.toLowerCase().compareTo(b.cognome.toLowerCase()));
    });
  }

  String _normSub(String code) => ScheduleService.normalizeSubCode(code);

  void _clearFilters() {
    setState(() {
      _fDateFrom = null;
      _fDateTo = null;
      _fModule = null;
      _fSubmodule = null;
      _fTaskId = null;
      _fInstructorId = null;
      _fAbsentId = null;
      _fRecoveringId = null;
    });
  }

  ModuleInfo? get _selectedModuleInfo {
    if (_fModule == null) return null;
    for (final m in _typeInfo?.modules ?? const <ModuleInfo>[]) {
      if (m.number == _fModule) return m;
    }
    return null;
  }

  List<SubmoduleInfo> get _submodulesForFilter => _selectedModuleInfo?.submodules ?? const [];

  List<PracticalTask> get _tasksForFilter {
    final allModules = _typeInfo?.modules ?? const <ModuleInfo>[];
    final filteredModules = _fModule != null
        ? allModules.where((m) => m.number == _fModule).toList()
        : allModules;
    final tasks = <PracticalTask>[];
    final seen = <int>{};
    for (final m in filteredModules) {
      final subs = _fSubmodule != null
          ? m.submodules.where((s) => _normSub(s.code) == _fSubmodule).toList()
          : m.submodules;
      for (final s in subs) {
        for (final t in s.practicalTasks) {
          if (seen.add(t.id)) tasks.add(t);
        }
      }
    }
    return tasks;
  }

  PracticalTask? _findTask(int taskId) {
    for (final m in _typeInfo?.modules ?? const <ModuleInfo>[]) {
      for (final s in m.submodules) {
        for (final t in s.practicalTasks) {
          if (t.id == taskId) return t;
        }
      }
    }
    return null;
  }

  /// Contatore ore: per task se la pratica ne ha uno nel programma, altrimenti
  /// per sottomodulo e tipo (stesso criterio del monte ore in `_lessonRow`).
  String _ordKey(ScheduledLesson l) {
    final isPratica = l.type == 'pratica';
    if (isPratica && l.taskId != null && _findTask(l.taskId!) != null) return 'task|${l.taskId}';
    return '${isPratica ? 'P' : 'T'}|${_normSub(l.submoduleCode)}';
  }

  String _moduleLabel(int number) {
    for (final m in _typeInfo?.modules ?? const <ModuleInfo>[]) {
      if (m.number == number) return m.displayCode;
    }
    return '$number';
  }

  String _subName(String code) {
    final nc = _normSub(code);
    for (final m in _typeInfo?.modules ?? const <ModuleInfo>[]) {
      for (final s in m.submodules) {
        if (_normSub(s.code) == nc) return s.name;
      }
    }
    return '';
  }

  SubmoduleInfo? _subInfo(String code) {
    final nc = _normSub(code);
    for (final m in _typeInfo?.modules ?? const <ModuleInfo>[]) {
      for (final s in m.submodules) {
        if (_normSub(s.code) == nc) return s;
      }
    }
    return null;
  }

  List<AppUser> _absentees(ScheduledLesson l) {
    final ids = _attendanceService
        .getRecordsForLesson(l.id)
        .where((r) => !r.present)
        .map((r) => r.attendeeId)
        .toSet();
    return _attendees.where((a) => ids.contains(a.id)).toList();
  }

  List<ScheduledLesson> get _filtered {
    var list = _allLessons.where((l) {
      if (_fDateFrom != null && l.date.isBefore(_fDateFrom!)) return false;
      if (_fDateTo != null && l.date.isAfter(_fDateTo!)) return false;
      if (_fModule != null && l.moduleNumber != _fModule) return false;
      if (_fSubmodule != null && _normSub(l.submoduleCode) != _fSubmodule) return false;
      if (_fTaskId != null && l.taskId?.toString() != _fTaskId) return false;
      if (_fInstructorId != null && l.instructorId != _fInstructorId) return false;
      return true;
    }).toList();

    if (_fAbsentId != null) {
      list = list
          .where((l) => _attendanceService
              .getRecordsForLesson(l.id)
              .any((r) => r.attendeeId == _fAbsentId && !r.present))
          .toList();
    }

    if (_fRecoveringId != null && _selected != null) {
      final stats = _attendanceService.computePerModuleStats(
          _selected!.id, _fRecoveringId!, _allLessons, modules: _typeInfo?.modules);
      final modsInRecovero = {
        for (final e in stats.entries) if ((e.value['toRecover'] ?? 0) > 0) e.key,
      };
      list = list.where((l) => modsInRecovero.contains(l.moduleNumber)).toList();
    }

    list.sort((a, b) {
      final c = b.date.compareTo(a.date);
      return c != 0 ? c : b.timeSlot.compareTo(a.timeSlot);
    });
    return list;
  }

  List<_RecoveryEntry> get _recoveryEntries {
    if (_selected == null) return const [];
    final records = _attendanceService.getRecoveriesForCourse(_selected!.id);
    final groups = <String, List<AttendanceRecord>>{};
    for (final r in records) {
      final d = r.recoveryDate;
      if (d == null || r.recoveredModule == null) continue;
      final subKey = r.recoveredSubmodule != null ? _normSub(r.recoveredSubmodule!) : '';
      final key = '${d.toIso8601String().split('T').first}|${r.recoveredModule}|${r.recoveredType ?? ''}|$subKey';
      groups.putIfAbsent(key, () => []).add(r);
    }
    return groups.values.map((g) {
      final first = g.first;
      final ids = g.map((r) => r.attendeeId).toSet();
      final attendees = _attendees.where((a) => ids.contains(a.id)).toList()
        ..sort((a, b) => a.cognome.toLowerCase().compareTo(b.cognome.toLowerCase()));
      return _RecoveryEntry(
        date: first.recoveryDate!,
        moduleNumber: first.recoveredModule!,
        type: first.recoveredType,
        submoduleCode: first.recoveredSubmodule,
        attendees: attendees,
        records: g,
      );
    }).toList();
  }

  List<_RecoveryEntry> get _filteredRecoveries {
    if (_fTaskId != null || _fInstructorId != null || _fAbsentId != null) return const [];
    return _recoveryEntries.where((r) {
      if (_fDateFrom != null && r.date.isBefore(_fDateFrom!)) return false;
      if (_fDateTo != null && r.date.isAfter(_fDateTo!)) return false;
      if (_fModule != null && r.moduleNumber != _fModule) return false;
      if (_fSubmodule != null &&
          (r.submoduleCode == null || _normSub(r.submoduleCode!) != _fSubmodule)) {
        return false;
      }
      if (_fRecoveringId != null && !r.attendees.any((a) => a.id == _fRecoveringId)) {
        return false;
      }
      return true;
    }).toList();
  }

  List<_LogEntry> get _mergedEntries {
    final list = <_LogEntry>[
      ..._filtered.map(_LogEntry.lesson),
      ..._filteredRecoveries.map(_LogEntry.recovery),
    ];
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (_courses.isEmpty) {
      return const Center(child: Text('Nessun corso assegnato', style: TextStyle(color: kTextDim)));
    }
    final filtered = _mergedEntries;
    final hasFilters = _fDateFrom != null ||
        _fDateTo != null ||
        _fModule != null ||
        _fSubmodule != null ||
        _fTaskId != null ||
        _fInstructorId != null ||
        _fAbsentId != null ||
        _fRecoveringId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Row(
            children: [
              if (widget.fixedCourseId == null && _courses.length > 1)
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
                    _clearFilters();
                    _refresh();
                  },
                )
              else
                Text(_selected?.title ?? '', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              Text('${filtered.length} voci', style: const TextStyle(color: kTextDim, fontSize: 12)),
              if (hasFilters) ...[
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off, size: 16),
                  label: const Text('Pulisci filtri'),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _filterBar(),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1, color: kBorder),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('Nessuna lezione trovata', style: TextStyle(color: kTextDim)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final e = filtered[i];
                    return e.lesson != null
                        ? _lessonRow(e.lesson!)
                        : _recoveryRow(e.recovery!);
                  },
                ),
        ),
      ],
    );
  }

  /// Filtro con etichetta sopra: largo [width] o, senza, quota della riga dei filtri.
  Widget _labeled(String label, Widget child, {double? width}) {
    final col = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: kTextDim, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        child,
      ],
    );
    return width != null ? SizedBox(width: width, child: col) : Expanded(child: col);
  }

  Widget _dateButton(String label, DateTime? value, ValueChanged<DateTime?> onChanged) {
    return _labeled(
      label,
      OutlinedButton(
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (picked != null) onChanged(picked);
        },
        child: Text(
          value != null ? DateFormat('dd/MM/yyyy').format(value) : '— Tutte —',
          style: const TextStyle(fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      width: 130,
    );
  }

  Widget _filterBar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        _dateButton('Da', _fDateFrom, (d) => setState(() => _fDateFrom = d)),
        _dateButton('A', _fDateTo, (d) => setState(() => _fDateTo = d)),
        _labeled(
          'Modulo',
          DropdownButtonFormField<int?>(
            value: _fModule,
            isExpanded: true,
            dropdownColor: kSurface,
            style: const TextStyle(color: kText, fontSize: 12),
            decoration: const InputDecoration(isDense: true),
            items: [
              const DropdownMenuItem(value: null, child: Text('— Tutti —')),
              ...(_typeInfo?.modules ?? const <ModuleInfo>[]).map((m) => DropdownMenuItem(
                    value: m.number,
                    child: Text('M${m.displayCode} – ${m.name}', overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: (v) => setState(() {
              _fModule = v;
              _fSubmodule = null;
              _fTaskId = null;
            }),
          ),
        ),
        _labeled(
          'Sottomodulo',
          DropdownButtonFormField<String?>(
            value: _fSubmodule,
            isExpanded: true,
            dropdownColor: kSurface,
            style: const TextStyle(color: kText, fontSize: 12),
            decoration: const InputDecoration(isDense: true),
            items: [
              const DropdownMenuItem(value: null, child: Text('— Tutti —')),
              ..._submodulesForFilter.map((s) => DropdownMenuItem(
                    value: _normSub(s.code),
                    child: Text('${s.code} – ${s.name}', overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: _fModule == null
                ? null
                : (v) => setState(() {
                      _fSubmodule = v;
                      _fTaskId = null;
                    }),
          ),
        ),
        _labeled(
          'ID Task',
          DropdownButtonFormField<String?>(
            value: _fTaskId,
            isExpanded: true,
            dropdownColor: kSurface,
            style: const TextStyle(color: kText, fontSize: 12),
            decoration: const InputDecoration(isDense: true),
            items: [
              const DropdownMenuItem(value: null, child: Text('— Tutti —')),
              ..._tasksForFilter.map((t) => DropdownMenuItem(
                    value: t.id.toString(),
                    child: Text(
                      t.name.isNotEmpty
                          ? 'Task ${t.programTaskId}: ${t.name}'
                          : 'Task ${t.programTaskId}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
            ],
            onChanged: (v) => setState(() => _fTaskId = v),
          ),
        ),
        _labeled(
          'Istruttore',
          DropdownButtonFormField<String?>(
            value: _fInstructorId,
            isExpanded: true,
            dropdownColor: kSurface,
            style: const TextStyle(color: kText, fontSize: 12),
            decoration: const InputDecoration(isDense: true),
            items: [
              const DropdownMenuItem(value: null, child: Text('— Tutti —')),
              ..._instructors.map((i) => DropdownMenuItem(
                    value: i.id,
                    child: Text(i.fullName, overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: (v) => setState(() => _fInstructorId = v),
          ),
        ),
        _labeled(
          'Frequentatore assente',
          DropdownButtonFormField<String?>(
            value: _fAbsentId,
            isExpanded: true,
            dropdownColor: kSurface,
            style: const TextStyle(color: kText, fontSize: 12),
            decoration: const InputDecoration(isDense: true),
            items: [
              const DropdownMenuItem(value: null, child: Text('— Nessuno —')),
              ..._attendees.map((a) => DropdownMenuItem(
                    value: a.id,
                    child: Text(a.fullName, overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: (v) => setState(() => _fAbsentId = v),
          ),
        ),
        _labeled(
          'Frequentatore in recupero',
          DropdownButtonFormField<String?>(
            value: _fRecoveringId,
            isExpanded: true,
            dropdownColor: kSurface,
            style: const TextStyle(color: kText, fontSize: 12),
            decoration: const InputDecoration(isDense: true),
            items: [
              const DropdownMenuItem(value: null, child: Text('— Nessuno —')),
              ..._attendees.map((a) => DropdownMenuItem(
                    value: a.id,
                    child: Text(a.fullName, overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: (v) => setState(() => _fRecoveringId = v),
          ),
        ),
      ],
    );
  }

  String _fmtHours(num h) => h == h.truncate() ? '${h.toInt()}' : '$h';

  // Colonne fisse condivise da lezioni e recuperi, così le righe restano allineate.
  static const double _dateW = 92, _leadW = 130, _sideW = 190;

  Widget _dateCell(DateTime d) => SizedBox(
        width: _dateW,
        child: Text(DateFormat('dd/MM/yyyy').format(d),
            style: const TextStyle(color: kText, fontSize: 12), overflow: TextOverflow.ellipsis),
      );

  Widget _chip(String text, Color color, {double size = 10}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(3)),
        child: Text(text, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.bold)),
      );

  Widget _typeChip(bool isPratica) => _chip(isPratica ? 'P' : 'T', isPratica ? kAccent : kPrimary);

  /// "M.. · codice   Nome sottomodulo" su una riga sola.
  Widget _subLine(int module, String? code) => Text.rich(
        TextSpan(children: [
          TextSpan(
            text: code != null ? 'M${_moduleLabel(module)} · $code' : 'M${_moduleLabel(module)}',
            style: const TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          if (code != null)
            TextSpan(text: '   ${_subName(code)}', style: const TextStyle(color: kTextDim, fontSize: 11)),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  Widget _sideText(String text, Color color) => Tooltip(
        message: text,
        child: Text(text, style: TextStyle(color: color, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
      );

  Widget _lessonRow(ScheduledLesson l) {
    final absentees = _absentees(l);
    final isPratica = l.type == 'pratica';
    final subInfo = _subInfo(l.submoduleCode);
    final task = (isPratica && l.taskId != null) ? _findTask(l.taskId!) : null;
    final taskLabel = isPratica ? _refService.taskLabelFor(_typeInfo, l.taskId) : null;
    final num totalHours = task != null
        ? task.plannedHours
        : (subInfo == null ? 0 : (isPratica ? subInfo.practicalHours : subInfo.theoryHours));
    // n-esima ora della lezione in ordine cronologico; oltre il piano è un recupero.
    final ord = _ordinals[l.id] ?? 0;
    final over = ord > totalHours;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: absentees.isNotEmpty ? kWarning.withOpacity(0.4) : kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dateCell(l.date),
          const SizedBox(width: 8),
          SizedBox(
            width: _leadW,
            child: Row(
              children: [
                _typeChip(isPratica),
                if (totalHours > 0) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: kSurface,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: kBorder),
                      ),
                      child: Text(
                        '${over ? _fmtHours(totalHours) : ord}/${_fmtHours(totalHours)}h${over ? ' (rec.)' : ''}',
                        style: const TextStyle(color: kTextDim, fontSize: 10, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _subLine(l.moduleNumber, l.submoduleCode),
                if (taskLabel != null)
                  Text(taskLabel,
                      style: const TextStyle(color: kTextDim, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: _sideW,
            child: _sideText(
              l.instructorId != null ? (_instructorNameById[l.instructorId] ?? '—') : '— Da assegnare —',
              kTextDim,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: _sideW,
            child: absentees.isEmpty
                ? _sideText('Tutti presenti', kAccent)
                : _sideText('Assenti: ${absentees.map((a) => a.cognome).join(', ')}', kWarning),
          ),
        ],
      ),
    );
  }

  Widget _recoveryRow(_RecoveryEntry r) {
    final isPratica = r.type == 'pratica';
    // Task dalla lezione pratica originale abbinata FIFO al recovery record.
    String? taskLabel;
    if (isPratica && _selected != null) {
      final labels = <String>{};
      final cache = <String, Map<String, ScheduledLesson>>{};
      for (final rec in r.records) {
        final byRec = cache.putIfAbsent(
          rec.attendeeId,
          () => _attendanceService.pairRecoveriesToAbsenceLessons(
              _selected!.id, rec.attendeeId, _allLessons),
        );
        final label = _refService.taskLabelFor(_typeInfo, byRec[rec.id]?.taskId);
        if (label != null) labels.add(label);
      }
      if (labels.isNotEmpty) taskLabel = labels.join(' · ');
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: kPrimary.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dateCell(r.date),
          const SizedBox(width: 8),
          SizedBox(
            width: _leadW,
            child: Row(
              children: [
                _chip('RECUPERO', kPrimary, size: 9),
                if (r.type != null) ...[const SizedBox(width: 6), _typeChip(isPratica)],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _subLine(r.moduleNumber, r.submoduleCode),
                if (taskLabel != null)
                  Text(taskLabel,
                      style: const TextStyle(color: kAccent, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: _sideW * 2 + 12,
            child: _sideText('Recuperato da: ${r.attendees.map((a) => a.cognome).join(', ')}', kPrimary),
          ),
        ],
      ),
    );
  }
}
