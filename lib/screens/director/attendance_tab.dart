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
import '../../services/reference_service.dart';
import '../../services/schedule_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';

class DirectorAttendanceTab extends ConsumerStatefulWidget {
  final String userId;
  const DirectorAttendanceTab({super.key, required this.userId});

  @override
  ConsumerState<DirectorAttendanceTab> createState() => _DirectorAttendanceTabState();
}

class _DirectorAttendanceTabState extends ConsumerState<DirectorAttendanceTab>
    with SingleTickerProviderStateMixin {
  final _courseService = CourseService();
  final _scheduleService = ScheduleService();
  final _attendanceService = AttendanceService();
  final _userService = UserService();
  final _refService = ReferenceService();

  late TabController _tabController;
  List<Course> _courses = [];
  Course? _selected;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _load() {
    setState(() {
      _courses = _courseService.getCoursesForDirector(widget.userId);
      if (_selected == null && _courses.isNotEmpty) _selected = _courses.first;
    });
  }

  Future<void> _reload() async {
    await ref.read(authProvider).reloadDb();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_courses.isEmpty) {
      return const Center(child: Text('Nessun corso assegnato', style: TextStyle(color: kTextDim)));
    }

    final course = _selected;
    if (course == null) return const SizedBox();

    final allLessons = _scheduleService.getLessonsForCourse(course.id);
    final attendees = _userService.getAllUsers()
        .where((u) => course.attendeeIds.contains(u.id))
        .toList()
      ..sort((a, b) => a.cognome.compareTo(b.cognome));
    final typeInfo = _refService.getEffectiveCourseType(course.courseTypeId, course.extensionTypeId, course.mamlCombinationId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
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
                  onChanged: (id) => setState(() {
                    _selected = _courses.firstWhere((c) => c.id == id);
                  }),
                )
              else
                Text('Presenze: ${_selected?.title ?? ''}',
                    style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(icon: const Icon(Icons.refresh, color: kTextDim), onPressed: _reload),
            ],
          ),
        ),
        const SizedBox(height: 4),
        TabBar(
          controller: _tabController,
          indicatorColor: kPrimary,
          labelColor: kPrimary,
          unselectedLabelColor: kTextDim,
          tabs: const [
            Tab(text: 'Per Frequentatore'),
            Tab(text: 'Per Lezione'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPerStudentView(course, attendees, allLessons, typeInfo),
              _buildPerLessonView(course, attendees, allLessons, typeInfo),
            ],
          ),
        ),
      ],
    );
  }

  // ── Per-student tab ──────────────────────────────────────────────────────

  Widget _buildPerStudentView(
    Course course,
    List<AppUser> attendees,
    List<ScheduledLesson> allLessons,
    CourseTypeInfo? typeInfo,
  ) {
    if (attendees.isEmpty) {
      return const Center(child: Text('Nessun frequentatore', style: TextStyle(color: kTextDim)));
    }

    final summaries = attendees.map((a) {
      final modStats = _attendanceService.computePerModuleStats(
        course.id, a.id, allLessons, modules: typeInfo?.modules);
      final totalAbsent = modStats.values.fold(0, (s, m) => s + (m['absent'] ?? 0));
      final totalUnrecovered = modStats.values.fold(0, (s, m) => s + (m['unrecovered'] ?? 0));
      final totalPlannedHours = typeInfo?.modules.fold(0, (s, m) => s + m.totalHours) ?? 0;
      final totalToRecover = modStats.values.fold(0, (s, m) => s + (m['toRecover'] ?? 0));
      final totalToRecoverT = modStats.values.fold(0, (s, m) => s + (m['toRecoverT'] ?? 0));
      final totalToRecoverP = modStats.values.fold(0, (s, m) => s + (m['toRecoverP'] ?? 0));
      final modulesToRecover = typeInfo == null
          ? <({ModuleInfo mod, int total, int theory, int practical})>[]
          : typeInfo.modules
              .where((m) => (modStats[m.number]?['toRecover'] ?? 0) > 0)
              .map((m) => (
                    mod: m,
                    total: modStats[m.number]?['toRecover'] ?? 0,
                    theory: modStats[m.number]?['toRecoverT'] ?? 0,
                    practical: modStats[m.number]?['toRecoverP'] ?? 0,
                  ))
              .toList();
      return _StudentAttendanceSummary(
        attendee: a,
        modStats: modStats,
        totalAbsent: totalAbsent,
        totalUnrecovered: totalUnrecovered,
        totalPlannedHours: totalPlannedHours,
        totalToRecover: totalToRecover,
        totalToRecoverT: totalToRecoverT,
        totalToRecoverP: totalToRecoverP,
        modulesToRecover: modulesToRecover,
      );
    }).toList();

    final regular = summaries.where((s) => s.totalToRecover == 0).toList()
      ..sort((a, b) {
        final cmp = b.totalUnrecovered.compareTo(a.totalUnrecovered);
        return cmp != 0 ? cmp : a.attendee.cognome.compareTo(b.attendee.cognome);
      });

    final toRecover = summaries.where((s) => s.totalToRecover > 0).toList()
      ..sort((a, b) {
        final cmp = b.totalToRecover.compareTo(a.totalToRecover);
        return cmp != 0 ? cmp : a.attendee.cognome.compareTo(b.attendee.cognome);
      });

    final totalPendingHours = toRecover.fold(0, (s, item) => s + item.totalToRecover);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildAttendancePanel(
                    title: 'In regola (${regular.length})',
                    subtitle: 'Nessun recupero obbligatorio pendente',
                    color: kAccent,
                    icon: Icons.check_circle_outline,
                    emptyText: 'Nessun frequentatore in regola',
                    items: regular,
                    course: course,
                    allLessons: allLessons,
                    typeInfo: typeInfo,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildAttendancePanel(
                    title: 'Da recuperare (${toRecover.length})',
                    subtitle: toRecover.isEmpty
                        ? 'Tutti i frequentatori sono in regola'
                        : '${totalPendingHours}h totali da recuperare · clicca un modulo per registrare il recupero',
                    color: toRecover.isEmpty ? kAccent : kError,
                    icon: toRecover.isEmpty ? Icons.verified_outlined : Icons.warning_amber_rounded,
                    emptyText: 'Nessun recupero pendente',
                    items: toRecover,
                    course: course,
                    allLessons: allLessons,
                    typeInfo: typeInfo,
                  ),
                ),
              ],
            ),
          );
        }

        // Fallback verticale su finestre strette: prima chi ha recuperi pendenti
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            _buildPanelHeader(
              title: 'Da recuperare (${toRecover.length})',
              subtitle: toRecover.isEmpty
                  ? 'Tutti i frequentatori sono in regola'
                  : '${totalPendingHours}h totali da recuperare',
              color: toRecover.isEmpty ? kAccent : kError,
              icon: toRecover.isEmpty ? Icons.verified_outlined : Icons.warning_amber_rounded,
            ),
            const SizedBox(height: 8),
            if (toRecover.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Nessun recupero pendente', style: TextStyle(color: kTextDim, fontSize: 13)),
              )
            else
              ...toRecover.map((s) => _buildStudentCard(course, s, allLessons, typeInfo)),
            const SizedBox(height: 16),
            _buildPanelHeader(
              title: 'In regola (${regular.length})',
              subtitle: 'Nessun recupero obbligatorio pendente',
              color: kAccent,
              icon: Icons.check_circle_outline,
            ),
            const SizedBox(height: 8),
            if (regular.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Nessun frequentatore in regola', style: TextStyle(color: kTextDim, fontSize: 13)),
              )
            else
              ...regular.map((s) => _buildStudentCard(course, s, allLessons, typeInfo)),
          ],
        );
      },
    );
  }

  Widget _buildAttendancePanel({
    required String title,
    required String subtitle,
    required Color color,
    required IconData icon,
    required String emptyText,
    required List<_StudentAttendanceSummary> items,
    required Course course,
    required List<ScheduledLesson> allLessons,
    required CourseTypeInfo? typeInfo,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: _buildPanelHeader(
              title: title,
              subtitle: subtitle,
              color: color,
              icon: icon,
            ),
          ),
          const Divider(height: 1, color: kBorder),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(emptyText, style: const TextStyle(color: kTextDim, fontSize: 13)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: items.length,
                    itemBuilder: (_, i) =>
                        _buildStudentCard(course, items[i], allLessons, typeInfo),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelHeader({
    required String title,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: kTextDim, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStudentCard(
    Course course,
    _StudentAttendanceSummary summary,
    List<ScheduledLesson> allLessons,
    CourseTypeInfo? typeInfo,
  ) {
    final a = summary.attendee;
    final modStats = summary.modStats;
    final totalAbsent = summary.totalAbsent;
    final totalUnrecovered = summary.totalUnrecovered;
    final totalPlannedHours = summary.totalPlannedHours;
    final totalToRecover = summary.totalToRecover;
    final totalToRecoverT = summary.totalToRecoverT;
    final totalToRecoverP = summary.totalToRecoverP;
    final presPct = totalPlannedHours > 0
        ? ((totalPlannedHours - totalAbsent) / totalPlannedHours * 100).toStringAsFixed(0)
        : '100';
    final absPct = totalPlannedHours > 0
        ? (totalAbsent / totalPlannedHours * 100).toStringAsFixed(0)
        : '0';
    final anyWarning = totalToRecover > 0;

    return Card(
      color: kCard,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: anyWarning ? kError.withValues(alpha: 0.35) : kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            leading: CircleAvatar(
              backgroundColor: anyWarning
                  ? kError.withValues(alpha: 0.15)
                  : kPrimary.withValues(alpha: 0.15),
              child: Text(
                a.cognome.isNotEmpty ? a.cognome[0].toUpperCase() : '?',
                style: TextStyle(
                    color: anyWarning ? kError : kPrimary, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(a.fullName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: kText, fontWeight: FontWeight.w500, fontSize: 14)),
            subtitle: Text(
              'Pres. $presPct% · Ass. $absPct% — $totalAbsent ore ass. · $totalUnrecovered non rec. su $totalPlannedHours ore prev.'
              '${totalToRecover > 0 ? '\nDa recuperare: ${totalToRecover}h'
                  '${totalToRecoverP > 0 ? ' · ${totalToRecoverP}h pratica (100%)' : ''}'
                  '${totalToRecoverT > 0 ? ' · ${totalToRecoverT}h teoria (oltre 10%)' : ''}' : ''}',
              style: TextStyle(color: anyWarning ? kError : kTextDim, fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.person_remove_outlined, color: kError, size: 18),
              tooltip: 'Espelli dal corso',
              onPressed: () => _expelStudent(course, a),
            ),
            children: typeInfo == null
                ? []
                : typeInfo.modules
                    .where((mod) =>
                        modStats.containsKey(mod.number) &&
                        (modStats[mod.number]!['total'] ?? 0) > 0)
                    .map((mod) =>
                        _buildModuleRow(course, a, allLessons, mod, modStats[mod.number]!, typeInfo))
                    .toList(),
          ),
          if (summary.modulesToRecover.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: summary.modulesToRecover.map((item) {
                  final parts = <String>[];
                  if (item.practical > 0) parts.add('${item.practical}h P');
                  if (item.theory > 0) parts.add('${item.theory}h T');
                  return ActionChip(
                    avatar: const Icon(Icons.add_circle_outline, size: 15, color: kError),
                    label: Text(
                      'M${item.mod.displayCode}: ${parts.join(' + ')}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: kText,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    tooltip: 'Registra recupero per ${item.mod.displayCode}',
                    backgroundColor: kError.withValues(alpha: 0.10),
                    side: BorderSide(color: kError.withValues(alpha: 0.35)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _addRecovery(course, a.id, item.mod),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _expelStudent(Course course, AppUser student) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Espelli frequentatore', style: TextStyle(color: kText)),
        content: Text(
          'Rimuovere ${student.fullName} dal corso "${course.title}"?\n\nI dati di presenze e voti verranno mantenuti.',
          style: const TextStyle(color: kTextDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla', style: TextStyle(color: kTextDim)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kError),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Espelli'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final updated = course.copyWith(
      attendeeIds: course.attendeeIds.where((id) => id != student.id).toList(),
    );
    await _courseService.updateCourse(updated);
    _reload();
  }

  Widget _buildModuleRow(
    Course course,
    AppUser a,
    List<ScheduledLesson> allLessons,
    ModuleInfo mod,
    Map<String, int> stats,
    CourseTypeInfo? typeInfo,
  ) {
    final absent      = stats['absent'] ?? 0;
    final recovered   = stats['recovered'] ?? 0;
    final unrecovered = stats['unrecovered'] ?? 0;
    final toRecover   = stats['toRecover'] ?? 0;
    final toRecoverT  = stats['toRecoverT'] ?? 0;
    final toRecoverP  = stats['toRecoverP'] ?? 0;
    final warn = toRecover > 0;
    final modPlan = mod.totalHours;
    final presPct = modPlan > 0
        ? ((modPlan - absent) / modPlan * 100).toStringAsFixed(0)
        : '100';
    final absPct = modPlan > 0
        ? (absent / modPlan * 100).toStringAsFixed(0)
        : '0';

    final details = absent > 0
        ? _attendanceService.absenceDetailsForModule(
            course.id, a.id, allLessons, mod.number, modules: [mod])
        : const <AbsenceDetail>[];

    String submoduleName(String? code) {
      if (code == null) return '';
      final nc = ScheduleService.normalizeSubCode(code);
      for (final s in mod.submodules) {
        if (ScheduleService.normalizeSubCode(s.code) == nc) return s.name;
      }
      return code;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.fromLTRB(24, 0, 8, 0),
          leading: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (warn ? kError : kPrimary).withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('M${mod.displayCode}',
                style: TextStyle(
                    color: warn ? kError : kPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
          title: Text(mod.name,
              style: const TextStyle(color: kText, fontSize: 12),
              overflow: TextOverflow.ellipsis),
          subtitle: warn
              ? Text(
                  [
                    'Ass. $absPct% · $unrecovered non rec.',
                    'Da recuperare: ${toRecover}h',
                    if (toRecoverP > 0) 'P: ${toRecoverP}h (100%)',
                    if (toRecoverT > 0) 'T: ${toRecoverT}h (oltre 10%)',
                  ].join(' — '),
                  style: const TextStyle(color: kError, fontSize: 11),
                )
              : Text(
                  absent == 0
                      ? 'Pres. 100% · Ass. 0% — nessuna assenza su $modPlan ore prev.'
                      : 'Pres. $presPct% · Ass. $absPct% — $absent ass. · $recovered rec. · $unrecovered non rec. / $modPlan ore prev.',
                  style: const TextStyle(color: kTextDim, fontSize: 11),
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (absent > 0)
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: kAccent, size: 20),
                  tooltip: 'Aggiungi recupero',
                  onPressed: () => _addRecovery(course, a.id, mod),
                ),
              if (recovered > 0)
                IconButton(
                  icon: const Icon(Icons.history, color: kTextDim, size: 20),
                  tooltip: 'Vedi recuperi',
                  onPressed: () => _showRecoveries(course, a.id, a.fullName, mod),
                ),
            ],
          ),
        ),
        if (details.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 0, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: details.map((d) {
                final color = d.isRecovered
                    ? kPrimary
                    : d.isTolerated
                        ? kTextDim
                        : kError;
                final statusText = d.isRecovered
                    ? 'Recuperata il ${DateFormat('dd/MM/yyyy').format(d.recoveryDate!)}'
                        '${d.recoveredSubmodule != null ? ' · ${d.recoveredSubmodule} – ${submoduleName(d.recoveredSubmodule)}' : ''}'
                    : d.isTolerated
                        ? 'Tollerata (entro 10%)'
                        : 'Da recuperare';
                final taskLabel = d.type == 'pratica'
                    ? _refService.taskLabelFor(typeInfo, d.lesson.taskId)
                    : null;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: kSurface,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          d.type == 'pratica' ? 'P' : 'T',
                          style: const TextStyle(
                              color: kTextDim, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('dd/MM/yyyy').format(d.lesson.date),
                        style: const TextStyle(color: kTextDim, fontSize: 11),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${d.lesson.submoduleCode}'
                          '${taskLabel != null ? ' · $taskLabel' : ''}'
                          ' · $statusText',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: d.needsRecovery ? FontWeight.w600 : FontWeight.normal),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Future<void> _addRecovery(Course course, String attendeeId, ModuleInfo mod) async {
    DateTime? selectedDate;
    String recoveryType = 'teoria';
    String? recoveredSubmodule;
    final user = ref.read(authProvider).currentUser;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: kCard,
          title: const Text('Aggiungi Recupero', style: TextStyle(color: kText)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Modulo: M${_refService.moduleLabel(mod.number)}',
                  style: const TextStyle(color: kTextDim, fontSize: 13)),
              const SizedBox(height: 12),
              const Text('Tipo ora recuperata:',
                  style: TextStyle(color: kTextDim, fontSize: 13)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  for (final t in const ['teoria', 'pratica'])
                    ChoiceChip(
                      label: Text(t == 'teoria' ? 'Teoria' : 'Pratica'),
                      selected: recoveryType == t,
                      onSelected: (_) => setDlg(() => recoveryType = t),
                      selectedColor: kPrimary.withValues(alpha: 0.25),
                      labelStyle: TextStyle(
                          color: recoveryType == t ? kPrimary : kTextDim,
                          fontSize: 12),
                      backgroundColor: kSurface,
                    ),
                ],
              ),
              if (mod.submodules.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Sottomodulo recuperato:',
                    style: TextStyle(color: kTextDim, fontSize: 13)),
                const SizedBox(height: 4),
                DropdownButtonFormField<String?>(
                  value: recoveredSubmodule,
                  isExpanded: true,
                  dropdownColor: kSurface,
                  style: const TextStyle(color: kText, fontSize: 12),
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— Non specificato —')),
                    ...mod.submodules.map((s) => DropdownMenuItem(
                          value: s.code,
                          child: Text('${s.code} – ${s.name}', overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (v) => setDlg(() => recoveredSubmodule = v),
                ),
              ],
              const SizedBox(height: 12),
              const Text('Data recupero:',
                  style: TextStyle(color: kTextDim, fontSize: 13)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    selectedDate != null
                        ? DateFormat('dd/MM/yyyy').format(selectedDate!)
                        : 'Non impostata',
                    style: const TextStyle(color: kText),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (d != null) setDlg(() => selectedDate = d);
                    },
                    child: const Text('Scegli'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla', style: TextStyle(color: kTextDim)),
            ),
            ElevatedButton(
              onPressed: selectedDate == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && selectedDate != null) {
      await _attendanceService.saveRecovery(
        courseId: course.id,
        attendeeId: attendeeId,
        confirmedBy: user?.id ?? '',
        recoveredModule: mod.number,
        recoveryDate: selectedDate!,
        recoveredType: recoveryType,
        recoveredSubmodule: recoveredSubmodule,
      );
      _reload();
    }
  }

  Future<void> _showRecoveries(
      Course course, String attendeeId, String name, ModuleInfo mod) async {
    final records = _attendanceService
        .getRecordsForAttendee(course.id, attendeeId)
        .where((r) => r.justification == 'recupero' && r.recoveredModule == mod.number)
        .toList();
    final typeInfo = _refService.getEffectiveCourseType(
        course.courseTypeId, course.extensionTypeId, course.mamlCombinationId);
    final lessons = _scheduleService.getLessonsForCourse(course.id);
    final byRec =
        _attendanceService.pairRecoveriesToAbsenceLessons(course.id, attendeeId, lessons);

    String submoduleName(String? code) {
      if (code == null) return '';
      final nc = ScheduleService.normalizeSubCode(code);
      for (final s in mod.submodules) {
        if (ScheduleService.normalizeSubCode(s.code) == nc) return s.name;
      }
      return code;
    }

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: Text('Recuperi M${_refService.moduleLabel(mod.number)} — $name',
            style: const TextStyle(color: kText)),
        content: SizedBox(
          width: 400,
          child: records.isEmpty
              ? const Text('Nessun recupero registrato.',
                  style: TextStyle(color: kTextDim))
              : ListView(
                  shrinkWrap: true,
                  children: records.map((r) {
                    final isPratica = (r.recoveredType ?? 'pratica') == 'pratica';
                    final taskLabel = isPratica
                        ? _refService.taskLabelFor(typeInfo, byRec[r.id]?.taskId)
                        : null;
                    final parts = <String>[
                      r.recoveryDate != null
                          ? DateFormat('dd/MM/yyyy').format(r.recoveryDate!)
                          : 'data n.d.',
                      if (r.recoveredType != null)
                        r.recoveredType == 'pratica' ? 'Pratica' : 'Teoria',
                      if (r.recoveredSubmodule != null)
                        '${r.recoveredSubmodule} – ${submoduleName(r.recoveredSubmodule)}',
                      if (taskLabel != null) taskLabel,
                    ];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.check_circle_outline,
                          color: kAccent, size: 18),
                      title: Text(
                        parts.join(' · '),
                        style: const TextStyle(color: kText, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: kError, size: 18),
                        onPressed: () async {
                          await _attendanceService.deleteRecovery(r.id);
                          if (ctx.mounted) Navigator.pop(ctx);
                          _reload();
                        },
                      ),
                    );
                  }).toList(),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Chiudi')),
        ],
      ),
    );
  }

  // ── Per-lesson tab (file controllo istruttori) ───────────────────────────

  Widget _buildPerLessonView(
    Course course,
    List<AppUser> attendees,
    List<ScheduledLesson> allLessons,
    CourseTypeInfo? typeInfo,
  ) {
    final confirmedLessons = allLessons
        .where((l) => l.confirmed && l.timeSlot > 0)
        .toList()
      ..sort((a, b) {
        final dc = a.date.compareTo(b.date);
        return dc != 0 ? dc : a.timeSlot.compareTo(b.timeSlot);
      });

    final allRecords = _attendanceService.getAllRecordsForCourse(course.id);
    final recoveryRecords = allRecords
        .where((r) => r.justification == 'recupero' && r.recoveredModule != null)
        .toList();

    final Map<String, List<AttendanceRecord>> recoveryByDate = {};
    for (final r in recoveryRecords) {
      if (r.recoveryDate != null) {
        final dk = DateFormat('yyyy-MM-dd').format(r.recoveryDate!);
        recoveryByDate.putIfAbsent(dk, () => []).add(r);
      }
    }

    final attendeeMap = {for (final a in attendees) a.id: a};
    // Per ogni frequentatore, l'abbinamento assenza→data di recupero (pool FIFO per modulo+tipo).
    final pairingByAttendee = {
      for (final a in attendees)
        a.id: _attendanceService.pairAbsenceRecoveries(course.id, a.id, allLessons),
    };

    final items = <Widget>[
      ...confirmedLessons.map((l) {
        final absentRecords = allRecords
            .where((r) => r.scheduleId == l.id && !r.present)
            .toList();
        return _buildLessonCard(l, absentRecords, attendeeMap, pairingByAttendee, typeInfo);
      }),
        if (recoveryByDate.isNotEmpty)
        _buildRecoverySection(course, recoveryByDate, attendeeMap, allLessons, typeInfo),
    ];

    if (items.isEmpty) {
      return const Center(
          child: Text('Nessuna lezione confermata', style: TextStyle(color: kTextDim)));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      children: items,
    );
  }

  Widget _buildLessonCard(
    ScheduledLesson l,
    List<AttendanceRecord> absentRecords,
    Map<String, AppUser> attendeeMap,
    Map<String, Map<String, DateTime>> pairingByAttendee,
    CourseTypeInfo? typeInfo,
  ) {
    final taskLabel = !l.isTheory
        ? _refService.taskLabelFor(typeInfo, l.taskId)
        : null;
    return Card(
      color: kCard,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kPrimary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'M${_refService.moduleLabel(l.moduleNumber)} · ${l.submoduleCode}'
                    '${taskLabel != null ? ' · $taskLabel' : ''}'
                    ' · S${l.timeSlot}',
                    style: const TextStyle(color: kPrimary, fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(DateFormat('dd/MM/yyyy').format(l.date),
                    style: const TextStyle(color: kTextDim, fontSize: 11)),
                const Spacer(),
                if (absentRecords.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: kError.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('${absentRecords.length} ass.',
                        style: const TextStyle(color: kError, fontSize: 10)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(l.topic,
                style: const TextStyle(color: kText, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            if (absentRecords.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Divider(color: kBorder, height: 1),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: absentRecords.map((r) {
                  final att = attendeeMap[r.attendeeId];
                  final recoveredOn = pairingByAttendee[r.attendeeId]?[l.id];
                  final color = recoveredOn != null ? kPrimary : kError;
                  final name = att?.fullName ?? r.attendeeId.substring(0, 8);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: color.withOpacity(0.3)),
                    ),
                    child: Text(
                      recoveredOn != null
                          ? '$name (rec. ${DateFormat('dd/MM/yyyy').format(recoveredOn)})'
                          : name,
                      style: TextStyle(color: color, fontSize: 11),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecoverySection(
    Course course,
    Map<String, List<AttendanceRecord>> recoveryByDate,
    Map<String, AppUser> attendeeMap,
    List<ScheduledLesson> allLessons,
    CourseTypeInfo? typeInfo,
  ) {
    final sortedDates = recoveryByDate.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Divider(color: kBorder),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'RECUPERI',
            style: TextStyle(
                color: kAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5),
          ),
        ),
        ...sortedDates.map((dk) {
          final recs = recoveryByDate[dk]!;
          final date = DateTime.parse(dk);
          return Card(
            color: kCard,
            margin: const EdgeInsets.only(bottom: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: kAccent.withOpacity(0.25)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.replay, color: kAccent, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('dd/MM/yyyy').format(date),
                        style: const TextStyle(
                            color: kAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...recs.map((r) {
                    final att = attendeeMap[r.attendeeId];
                    final typ = r.recoveredType == 'pratica'
                        ? 'P'
                        : (r.recoveredType == 'teoria' ? 'T' : null);
                    final isPratica = (r.recoveredType ?? 'pratica') == 'pratica';
                    final byRec = isPratica
                        ? _attendanceService.pairRecoveriesToAbsenceLessons(
                            course.id, r.attendeeId, allLessons)
                        : const <String, ScheduledLesson>{};
                    final taskLabel = isPratica
                        ? _refService.taskLabelFor(typeInfo, byRec[r.id]?.taskId)
                        : null;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        children: [
                          Flexible(child: Text(
                            att?.fullName ?? r.attendeeId.substring(0, 8),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: kText, fontSize: 12),
                          )),
                          const SizedBox(width: 8),
                          const Text('→',
                              style: TextStyle(color: kTextDim, fontSize: 12)),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: kAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'M${r.recoveredModule}'
                                '${typ != null ? ' · $typ' : ''}'
                                '${r.recoveredSubmodule != null ? ' · ${r.recoveredSubmodule}' : ''}'
                                '${taskLabel != null ? ' · $taskLabel' : ''}',
                                style: const TextStyle(
                                    color: kAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// Riepilogo precomputato delle presenze e dei recuperi di un frequentatore.
class _StudentAttendanceSummary {
  final AppUser attendee;
  final Map<int, Map<String, int>> modStats;
  final int totalAbsent;
  final int totalUnrecovered;
  final int totalPlannedHours;
  final int totalToRecover;
  final int totalToRecoverT;
  final int totalToRecoverP;
  final List<({ModuleInfo mod, int total, int theory, int practical})> modulesToRecover;

  const _StudentAttendanceSummary({
    required this.attendee,
    required this.modStats,
    required this.totalAbsent,
    required this.totalUnrecovered,
    required this.totalPlannedHours,
    required this.totalToRecover,
    required this.totalToRecoverT,
    required this.totalToRecoverP,
    required this.modulesToRecover,
  });
}
