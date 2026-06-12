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
    // Stessa formula dell'admin (course_detail_screen): ore confermate cappate
    // al monte ore di ogni modulo, denominatore = somma monte ore dei moduli.
    double doneTotal = 0;
    double totalHours = 0;
    if (typeInfo != null) {
      for (final m in typeInfo.modules) {
        final t = m.totalHours.toDouble();
        final raw = taughtHours[m.number] ?? 0.0;
        totalHours += t;
        doneTotal += t > 0 && raw > t ? t : raw;
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
              _statCard('Ore svolte', '${doneTotal.toInt()}', Icons.check_circle_outline),
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
                      width: 40,
                      child: Text('M${m.displayCode}', style: const TextStyle(color: kTextDim, fontSize: 12)),
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
                    const SizedBox(width: 12),
                    Text('${done.toInt()}/${total.toInt()}h',
                        style: const TextStyle(color: kTextDim, fontSize: 11)),
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

  Widget _statCard(String label, String value, IconData icon) => Expanded(
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
            Text(label, style: const TextStyle(color: kTextDim, fontSize: 11), textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
