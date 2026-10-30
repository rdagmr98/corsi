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
import '../../widgets/mobile_ui.dart';

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
      return const EmptyState(Icons.school_outlined, 'Nessun corso attivo');
    }

    final course = _selected;
    if (course == null) return const SizedBox();

    final typeInfo = _refService.getEffectiveCourseType(course.courseTypeId, course.extensionTypeId, course.mamlCombinationId);
    final summary = _gradeService.getAttendeeSummary(course.id, widget.userId);

    final gradScore = _gradeService.getGraduationScore(course.id, widget.userId);
    final hasAnyGrade = summary.values.any((s) => s.hasGrades);
    final globalAvg = hasAnyGrade ? gradScore : null;

    // Provisional ranking
    final ranking = _gradeService.getCourseRanking(course.id, course.attendeeIds);
    final myRank = ranking.firstWhere(
        (r) => r.attendeeId == widget.userId,
        orElse: () => (attendeeId: widget.userId, score: 0, rank: 0));
    final rankPos = hasAnyGrade ? myRank.rank : null;

    return RefreshIndicator(
      onRefresh: _reload,
      color: kAttendeeAccent,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_courses.length > 1) ...[
                    CourseSelector(
                      courses: _courses,
                      selectedId: _selected?.id,
                      onSelected: (c) => setState(() => _selected = c),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (globalAvg != null) ...[
                    _summaryCard(globalAvg, rankPos, course.attendeeIds.length),
                    const SizedBox(height: 4),
                  ],
                  const SectionTitle('Voti per modulo'),
                ],
              ),
            ),
          ),
          if (typeInfo != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final module = typeInfo.modules[i];
                    final s = summary[module.number];
                    final graded = s != null && s.hasGrades;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: mobileCard(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Pill('M${module.displayCode}', moduleColor(module.number)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(module.name,
                                    style: const TextStyle(
                                        color: kText, fontSize: 14, fontWeight: FontWeight.w600),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              if (graded) ...[
                                const SizedBox(width: 8),
                                Text(
                                  s.weightedAverage.toStringAsFixed(1),
                                  style: TextStyle(
                                    color: s.isPassing ? kAccent : kError,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (graded) ...[
                            const SizedBox(height: 10),
                            ...s.grades.map((g) {
                              final attemptLabel = s.attemptLabel(g);
                              final recoveryNote = s.recoveryNote(g);
                              final capNote = s.recoveryCapNote(g);
                              final chipColor =
                                  g.assessmentType == AssessmentType.esame ? kWarning : kPrimary;
                              return Container(
                                margin: const EdgeInsets.only(top: 6),
                                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                                decoration: BoxDecoration(
                                  color: kSurface,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Pill(s.chipLabel(g), chipColor),
                                          const SizedBox(height: 4),
                                          Text(DateFormat('dd/MM/yyyy').format(g.date),
                                              style: const TextStyle(color: kTextSoft, fontSize: 12)),
                                          if (attemptLabel != null)
                                            Text(attemptLabel,
                                                style: const TextStyle(color: kTextSoft, fontSize: 11)),
                                          if (g.notes != null && g.notes!.isNotEmpty)
                                            Text(g.notes!,
                                                style: const TextStyle(color: kTextSoft, fontSize: 12),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          g.score.toStringAsFixed(1),
                                          style: TextStyle(
                                            color: g.isPassing ? kAccent : kError,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (recoveryNote != null)
                                          Text(recoveryNote,
                                              style: TextStyle(
                                                  color: recoveryNote == 'tentativo superato'
                                                      ? kTextSoft
                                                      : kError,
                                                  fontSize: 11)),
                                        if (capNote != null)
                                          Text(capNote,
                                              style: const TextStyle(color: kWarning, fontSize: 11)),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ] else
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text('Nessuna valutazione',
                                  style: TextStyle(color: kTextSoft, fontSize: 13)),
                            ),
                        ],
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

  Widget _summaryCard(double avg, int? rankPos, int total) {
    final color = avg >= 22.5 ? kAccent : kError;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: mobileCard(tint: color),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                avg.toStringAsFixed(3),
                style: TextStyle(color: color, fontSize: 38, fontWeight: FontWeight.w800),
              ),
              const Text(' /30', style: TextStyle(color: kTextSoft, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 2),
          const Text('Media ponderata graduatoria',
              textAlign: TextAlign.center,
              style: TextStyle(color: kTextSoft, fontSize: 13)),
          if (rankPos != null && rankPos > 0) ...[
            const SizedBox(height: 12),
            Pill('Posizione provvisoria: $rankPos° / $total', kAttendeeAccent,
                icon: Icons.leaderboard),
          ],
        ],
      ),
    );
  }
}
