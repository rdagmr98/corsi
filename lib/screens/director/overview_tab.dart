import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/course_service.dart';
import '../../services/reference_service.dart';
import '../../services/schedule_service.dart';
import '../../theme.dart';

class DirectorOverviewTab extends ConsumerStatefulWidget {
  final String userId;
  const DirectorOverviewTab({super.key, required this.userId});

  @override
  ConsumerState<DirectorOverviewTab> createState() => _DirectorOverviewTabState();
}

class _DirectorOverviewTabState extends ConsumerState<DirectorOverviewTab> {
  final _courseService = CourseService();
  final _refService = ReferenceService();
  final _scheduleService = ScheduleService();
  List<Course> _courses = [];
  Course? _selected;

  @override
  void initState() {
    super.initState();
    _load();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(
            children: [
              Text('I miei corsi', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
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
                ),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.refresh, color: kTextDim), onPressed: _reload),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_selected == null)
          const Expanded(
            child: Center(child: Text('Nessun corso assegnato', style: TextStyle(color: kTextDim))),
          )
        else
          Expanded(child: _buildCourseOverview(_selected!)),
      ],
    );
  }

  Widget _buildCourseOverview(Course course) {
    final typeInfo = _refService.getEffectiveCourseType(course.courseTypeId, course.extensionTypeId);
    final taughtHours = _scheduleService.computeModuleHoursTaught(course.id);
    final totalTheory = typeInfo?.totalTheoryHours ?? 0;
    final totalPractical = typeInfo?.totalPracticalHours ?? 0;

    double doneTotal = 0, doneTotalT = 0, doneTotalP = 0;
    double totalHours = 0;
    if (typeInfo != null) {
      final rawT = <int, double>{};
      final rawP = <int, double>{};
      for (final l in _scheduleService.getLessonsForCourse(course.id)) {
        if (!l.confirmed) continue;
        if (l.type != 'pratica') {
          rawT[l.moduleNumber] = (rawT[l.moduleNumber] ?? 0) + 1;
        } else {
          rawP[l.moduleNumber] = (rawP[l.moduleNumber] ?? 0) + 1;
        }
      }
      for (final m in typeInfo.modules) {
        final t = m.totalHours.toDouble();
        final raw = taughtHours[m.number] ?? 0.0;
        totalHours += t;
        doneTotal += t > 0 && raw > t ? t : raw;
        final rt = rawT[m.number] ?? 0.0;
        final rp = rawP[m.number] ?? 0.0;
        doneTotalT += m.theoryHours > 0 && rt > m.theoryHours ? m.theoryHours.toDouble() : rt;
        doneTotalP += m.practicalHours > 0 && rp > m.practicalHours ? m.practicalHours.toDouble() : rp;
      }
    } else {
      doneTotal = taughtHours.values.fold(0.0, (a, b) => a + b);
    }
    final progress = totalHours > 0 ? doneTotal / totalHours : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header card
          Card(
            color: kCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(course.title,
                            style: const TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        if (typeInfo != null)
                          Text(typeInfo.name, style: const TextStyle(color: kTextDim, fontSize: 12)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _statusPill(course.courseStatus),
                            const SizedBox(width: 8),
                            if (course.startDate != null)
                              Text('Inizio: ${DateFormat('dd/MM/yyyy').format(course.startDate!)}',
                                  style: const TextStyle(color: kTextDim, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      Text('${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                          style: const TextStyle(color: kPrimary, fontSize: 32, fontWeight: FontWeight.bold)),
                      const Text('completato', style: TextStyle(color: kTextDim, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Progress bar
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            backgroundColor: kSurface,
            color: kPrimary,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 24),
          // Stats row
          Row(
            children: [
              _statCard('Frequentatori', '${course.attendeeIds.length}', Icons.people),
              const SizedBox(width: 12),
              _statCard('Istruttori', '${course.instructorIds.length}', Icons.school),
              const SizedBox(width: 12),
              _statCard('Ore teoria', '$totalTheory', Icons.menu_book),
              const SizedBox(width: 12),
              _statCard('Ore pratica', '$totalPractical', Icons.handyman),
              const SizedBox(width: 12),
              _statCard('Ore svolte', '${doneTotal.toInt()}', Icons.check_circle_outline,
                  onTap: () => _showHoursDetail(context, doneTotal, doneTotalT, doneTotalP)),
            ],
          ),
          const SizedBox(height: 24),
          // Module progress
          if (typeInfo != null) ...[
            Text('Avanzamento per modulo',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...typeInfo.modules.map((m) {
              final rawDone = taughtHours[m.number] ?? 0.0;
              final total = m.totalHours.toDouble();
              // Le ore oltre il piano sono recuperi: il contatore resta al massimo
              // al monte ore ufficiale del modulo.
              final done = total > 0 && rawDone > total ? total : rawDone;
              final p = total > 0 ? done / total : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text('M${m.displayCode}',
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: kTextDim, fontSize: 12)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.name, style: const TextStyle(color: kText, fontSize: 12)),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: p.clamp(0.0, 1.0),
                            backgroundColor: kSurface,
                            color: p >= 1.0 ? kAccent : kPrimary,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 64,
                      child: Text('${done.toInt()}/${total.toInt()}h',
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: kTextDim, fontSize: 11)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _statusPill(CourseStatus s) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: _statusColor(s).withOpacity(0.15),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(s.label, style: TextStyle(color: _statusColor(s), fontSize: 11)),
  );

  Color _statusColor(CourseStatus s) => switch (s) {
    CourseStatus.planning => kWarning,
    CourseStatus.active => kAccent,
    CourseStatus.completed => kPrimary,
    CourseStatus.archived => kTextDim,
  };

  void _showHoursDetail(BuildContext context, double total, double theory, double practical) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Ore svolte', style: TextStyle(color: kText, fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _hoursRow('Totale', total.toInt(), kPrimary),
            const Divider(color: kBorder, height: 16),
            _hoursRow('Teoria', theory.toInt(), kPrimary),
            _hoursRow('Pratica', practical.toInt(), kAccent),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: kPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _hoursRow(String label, int value, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: kTextDim, fontSize: 13)),
        Text('$value h', style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    ),
  );

  Widget _statCard(String label, String value, IconData icon, {VoidCallback? onTap}) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Card(
        color: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Icon(icon, color: kPrimary, size: 20),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(color: kText, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(label,
                        style: const TextStyle(color: kTextDim, fontSize: 11),
                        textAlign: TextAlign.center),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 3),
                    const Icon(Icons.info_outline, color: kTextDim, size: 10),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
