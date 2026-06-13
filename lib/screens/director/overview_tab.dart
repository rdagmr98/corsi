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
    final rawT = <int, double>{};
    final rawP = <int, double>{};
    final subRawT = <String, double>{};
    final subRawP = <String, double>{};
    if (typeInfo != null) {
      for (final l in _scheduleService.getLessonsForCourse(course.id)) {
        if (!l.confirmed) continue;
        if (l.type != 'pratica') {
          rawT[l.moduleNumber] = (rawT[l.moduleNumber] ?? 0) + 1;
          final nc = ScheduleService.normalizeSubCode(l.submoduleCode);
          if (nc.isNotEmpty) subRawT[nc] = (subRawT[nc] ?? 0) + 1;
        } else {
          rawP[l.moduleNumber] = (rawP[l.moduleNumber] ?? 0) + 1;
          final nc = ScheduleService.normalizeSubCode(l.submoduleCode);
          if (nc.isNotEmpty) subRawP[nc] = (subRawP[nc] ?? 0) + 1;
        }
      }
      for (final m in typeInfo.modules) {
        totalHours += m.totalHours;
        for (final sub in m.submodules) {
          final nc = ScheduleService.normalizeSubCode(sub.code);
          final st = (subRawT[nc] ?? 0.0).clamp(0.0, sub.theoryHours.toDouble());
          final sp = (subRawP[nc] ?? 0.0).clamp(0.0, sub.practicalHours.toDouble());
          doneTotal += st + sp;
          doneTotalT += st;
          doneTotalP += sp;
        }
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
                  onTap: () => _showHoursDetail(context, doneTotal, doneTotalT, doneTotalP,
                      totalHours, totalTheory.toDouble(), totalPractical.toDouble())),
            ],
          ),
          const SizedBox(height: 24),
          // Module progress
          if (typeInfo != null) ...[
            Text('Avanzamento per modulo',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...typeInfo.modules.map((m) {
              double doneT = 0, doneP = 0;
              for (final sub in m.submodules) {
                final nc = ScheduleService.normalizeSubCode(sub.code);
                doneT += (subRawT[nc] ?? 0.0).clamp(0.0, sub.theoryHours.toDouble());
                doneP += (subRawP[nc] ?? 0.0).clamp(0.0, sub.practicalHours.toDouble());
              }
              final total = m.totalHours.toDouble();
              final done = doneT + doneP;
              final pT = total > 0 ? doneT / total : 0.0;
              final pP = total > 0 ? doneP / total : 0.0;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showModuleDetail(context, m, doneT, doneP, subRawT, subRawP),
                child: Padding(
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
                            splitBar(pT, pP, height: 4),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 60,
                        child: Text('${done.toInt()}/${total.toInt()}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: kTextDim, fontSize: 11)),
                      ),
                    ],
                  ),
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

  void _showHoursDetail(BuildContext context, double done, double doneT, double doneP,
      double planTotal, double planT, double planP) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Ore svolte', style: TextStyle(color: kText, fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _hoursRow('Totale', done.toInt(), planTotal.toInt(), kText),
            const Divider(color: kBorder, height: 16),
            _hoursRow('Teoria', doneT.toInt(), planT.toInt(), kPrimary),
            _hoursRow('Pratica', doneP.toInt(), planP.toInt(), kAccent),
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

  void _showModuleDetail(BuildContext context, dynamic m, double doneT, double doneP,
      Map<String, double> subRawT, Map<String, double> subRawP) {
    final planT = (m.theoryHours as num).toDouble();
    final planP = (m.practicalHours as num).toDouble();
    final subs = m.submodules as List;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('M${m.displayCode}',
              style: const TextStyle(color: kPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          Text(m.name as String, style: const TextStyle(color: kTextDim, fontSize: 12)),
        ]),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _hoursRow('Totale', (doneT + doneP).toInt(), (planT + planP).toInt(), kText),
              const Divider(color: kBorder, height: 16),
              _hoursRow('Teoria', doneT.toInt(), planT.toInt(), kPrimary),
              if (planP > 0) _hoursRow('Pratica', doneP.toInt(), planP.toInt(), kAccent),
              if (subs.isNotEmpty) ...[
                const Divider(color: kBorder, height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Per sottomodulo',
                      style: TextStyle(color: kTextDim, fontSize: 11)),
                ),
                const SizedBox(height: 4),
                ...subs.map((s) {
                  final sPlanT = (s.theoryHours as num).toDouble();
                  final sPlanP = (s.practicalHours as num).toDouble();
                  final nc = ScheduleService.normalizeSubCode(s.code as String);
                  final rawST = subRawT[nc] ?? 0.0;
                  final rawSP = subRawP[nc] ?? 0.0;
                  final sDoneT = rawST > sPlanT ? sPlanT : rawST;
                  final sDoneP = rawSP > sPlanP ? sPlanP : rawSP;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${s.code}  ${s.name}',
                            style: const TextStyle(color: kText, fontSize: 11, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Row(children: [
                          const SizedBox(width: 8),
                          const SizedBox(width: 12, child: Text('T', style: TextStyle(color: kTextDim, fontSize: 11))),
                          Text('${sDoneT.toInt()} / ${sPlanT.toInt()}h',
                              style: const TextStyle(color: kPrimary, fontSize: 11)),
                          const Spacer(),
                          Text(sPlanT > 0 ? '${(sDoneT / sPlanT * 100).round()}%' : '—',
                              style: const TextStyle(color: kPrimary, fontSize: 11)),
                        ]),
                        if (sPlanP > 0) Row(children: [
                          const SizedBox(width: 8),
                          const SizedBox(width: 12, child: Text('P', style: TextStyle(color: kTextDim, fontSize: 11))),
                          Text('${sDoneP.toInt()} / ${sPlanP.toInt()}h',
                              style: const TextStyle(color: kAccent, fontSize: 11)),
                          const Spacer(),
                          Text('${(sDoneP / sPlanP * 100).round()}%',
                              style: const TextStyle(color: kAccent, fontSize: 11)),
                        ]),
                      ],
                    ),
                  );
                }),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Chiudi', style: TextStyle(color: kPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _hoursRow(String label, int done, int plan, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(width: 56, child: Text(label, style: const TextStyle(color: kTextDim, fontSize: 13))),
        Expanded(
          child: Text('$done / $plan ore',
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
        ),
        Text(
          plan > 0 ? '${(done / plan * 100).round()}%' : '—',
          style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold),
        ),
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
