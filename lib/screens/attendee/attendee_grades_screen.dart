import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
import '../../models/grade_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/course_service.dart';
import '../../services/grade_service.dart';
import '../../services/reference_service.dart';
import '../../theme.dart';

class AttendeeGradesScreen extends ConsumerStatefulWidget {
  final String userId;
  const AttendeeGradesScreen({super.key, required this.userId});

  @override
  ConsumerState<AttendeeGradesScreen> createState() => _AttendeeGradesScreenState();
}

class _AttendeeGradesScreenState extends ConsumerState<AttendeeGradesScreen> {
  final _courseService = CourseService();
  final _gradeService = GradeService();
  final _refService = ReferenceService();

  List<Course> _courses = [];
  Course? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _courses = _courseService.getCoursesForAttendee(widget.userId);
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
      return const Center(child: Text('Nessun corso attivo', style: TextStyle(color: kTextDim)));
    }

    final course = _selected;
    if (course == null) return const SizedBox();

    final typeInfo = _refService.getCourseType(course.courseTypeId);
    final summary = _gradeService.getAttendeeSummary(course.id, widget.userId);

    double totalScore = 0;
    int gradeCount = 0;
    for (final s in summary.values) {
      if (s.hasGrades) {
        totalScore += s.weightedAverage;
        gradeCount++;
      }
    }
    final globalAvg = gradeCount > 0 ? totalScore / gradeCount : null;

    return RefreshIndicator(
      onRefresh: _reload,
      color: kWarning,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  if (_courses.length > 1)
                    DropdownButton<String>(
                      value: _selected?.id,
                      dropdownColor: kSurface,
                      style: const TextStyle(color: kText),
                      isExpanded: true,
                      underline: const SizedBox(),
                      items: _courses
                          .map((c) => DropdownMenuItem(value: c.id, child: Text(c.title)))
                          .toList(),
                      onChanged: (id) => setState(() {
                        _selected = _courses.firstWhere((c) => c.id == id);
                      }),
                    ),
                  const SizedBox(height: 12),
                  if (globalAvg != null)
                    Card(
                      color: kCard,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: (globalAvg >= 22.5 ? kAccent : kError).withOpacity(0.3)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              globalAvg.toStringAsFixed(1),
                              style: TextStyle(
                                color: globalAvg >= 22.5 ? kAccent : kError,
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text(' / 30', style: TextStyle(color: kTextDim, fontSize: 20)),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  globalAvg >= 22.5 ? 'SUFFICIENTE' : 'INSUFFICIENTE',
                                  style: TextStyle(
                                    color: globalAvg >= 22.5 ? kAccent : kError,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                Text('Media ponderata', style: const TextStyle(color: kTextDim, fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (typeInfo != null)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final module = typeInfo.modules[i];
                    final s = summary[module.number];

                    return Card(
                      color: kCard,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: kPrimary.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('M${module.number}',
                                      style: const TextStyle(color: kPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(module.name,
                                      style: const TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                                if (s != null && s.hasGrades)
                                  Text(
                                    s.weightedAverage.toStringAsFixed(1),
                                    style: TextStyle(
                                      color: s.isPassing ? kAccent : kError,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),
                            if (s != null && s.hasGrades) ...[
                              const SizedBox(height: 8),
                              ...s.grades.map((g) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: (g.assessmentType == AssessmentType.esame ? kWarning : kPrimary).withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        g.assessmentType.label,
                                        style: TextStyle(
                                          color: g.assessmentType == AssessmentType.esame ? kWarning : kPrimary,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(DateFormat('dd/MM/yyyy').format(g.date),
                                        style: const TextStyle(color: kTextDim, fontSize: 11)),
                                    const Spacer(),
                                    Text(
                                      g.score.toStringAsFixed(1),
                                      style: TextStyle(
                                        color: g.isPassing ? kAccent : kError,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                            ] else
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text('Nessuna valutazione', style: TextStyle(color: kTextDim, fontSize: 12)),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: typeInfo.modules.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
