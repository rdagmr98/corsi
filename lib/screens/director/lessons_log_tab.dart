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

class DirectorLessonsLogTab extends ConsumerStatefulWidget {
  final String userId;
  const DirectorLessonsLogTab({super.key, required this.userId});

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
    _courses = _courseService.getCoursesForDirector(widget.userId);
    if (_selected == null && _courses.isNotEmpty) _selected = _courses.first;
    _refresh();
  }

  void _refresh() {
    if (_selected == null) return;
    setState(() {
      _typeInfo = _refService.getEffectiveCourseType(_selected!.courseTypeId, _selected!.extensionTypeId);
      _allLessons = _scheduleService.getLessonsForCourse(_selected!.id)
          .where((l) => l.confirmed && l.timeSlot > 0)
          .toList();
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
    if (_fSubmodule == null) return const [];
    for (final s in _submodulesForFilter) {
      if (_normSub(s.code) == _fSubmodule) return s.practicalTasks;
    }
    return const [];
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

  @override
  Widget build(BuildContext context) {
    if (_courses.isEmpty) {
      return const Center(child: Text('Nessun corso assegnato', style: TextStyle(color: kTextDim)));
    }
    final filtered = _filtered;
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
                    _clearFilters();
                    _refresh();
                  },
                )
              else
                Text(_selected?.title ?? '', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              Text('${filtered.length} lezioni', style: const TextStyle(color: kTextDim, fontSize: 12)),
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
                  itemBuilder: (_, i) => _lessonRow(filtered[i]),
                ),
        ),
      ],
    );
  }

  Widget _labeled(String label, Widget child) => SizedBox(
        width: 180,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: kTextDim, fontSize: 11)),
            const SizedBox(height: 4),
            child,
          ],
        ),
      );

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
    );
  }

  Widget _filterBar() {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
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
                    child: Text('T${t.id} – ${t.name}', overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: _fSubmodule == null ? null : (v) => setState(() => _fTaskId = v),
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

  Widget _lessonRow(ScheduledLesson l) {
    final absentees = _absentees(l);
    final taskName = _refService.taskName(_typeInfo, l.taskId);
    final isPratica = l.type == 'pratica';
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
          SizedBox(
            width: 76,
            child: Text(
              DateFormat('dd/MM/yyyy').format(l.date),
              style: const TextStyle(color: kText, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: (isPratica ? kAccent : kPrimary).withOpacity(0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              isPratica ? 'P' : 'T',
              style: TextStyle(
                  color: isPratica ? kAccent : kPrimary, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'M${_moduleLabel(l.moduleNumber)} · ${l.submoduleCode}',
                  style: const TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _subName(l.submoduleCode),
                  style: const TextStyle(color: kTextDim, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          if (l.taskId != null) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Text(
                taskName != null ? 'T${l.taskId} – $taskName' : 'T${l.taskId}',
                style: const TextStyle(color: kTextDim, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              l.instructorId != null ? (_instructorNameById[l.instructorId] ?? '—') : '— Da assegnare —',
              style: const TextStyle(color: kTextDim, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: absentees.isEmpty
                ? const Text(
                    'Tutti presenti',
                    style: TextStyle(color: kAccent, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  )
                : Text(
                    'Assenti: ${absentees.map((a) => a.cognome).join(', ')}',
                    style: const TextStyle(color: kWarning, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
          ),
        ],
      ),
    );
  }
}
