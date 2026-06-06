import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/course_models.dart';
import '../../models/grade_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/course_service.dart';
import '../../services/grade_service.dart';
import '../../services/reference_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';

class DirectorGradesTab extends ConsumerStatefulWidget {
  final String userId;
  const DirectorGradesTab({super.key, required this.userId});

  @override
  ConsumerState<DirectorGradesTab> createState() => _DirectorGradesTabState();
}

class _DirectorGradesTabState extends ConsumerState<DirectorGradesTab> {
  final _courseService = CourseService();
  final _gradeService = GradeService();
  final _refService = ReferenceService();
  final _userService = UserService();

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

  Future<void> _addGrade(Course course, String attendeeId, int moduleNumber) async {
    double score = 0;
    AssessmentType type = AssessmentType.accertamento;
    final notesCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: kCard,
          title: const Text('Inserisci voto', style: TextStyle(color: kText)),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<AssessmentType>(
                  value: type,
                  dropdownColor: kSurface,
                  style: const TextStyle(color: kText),
                  decoration: const InputDecoration(labelText: 'Tipo', isDense: true),
                  items: [
                    DropdownMenuItem(value: AssessmentType.accertamento, child: Text(AssessmentType.accertamento.label)),
                    DropdownMenuItem(value: AssessmentType.esame, child: Text(AssessmentType.esame.label)),
                  ],
                  onChanged: (v) => setDlg(() => type = v ?? type),
                ),
                const SizedBox(height: 16),
                Text('Voto: ${score.toStringAsFixed(1)}/30',
                    style: const TextStyle(color: kText, fontWeight: FontWeight.bold)),
                Slider(
                  value: score,
                  min: 0,
                  max: 30,
                  divisions: 60,
                  label: score.toStringAsFixed(1),
                  activeColor: score >= 22.5 ? kAccent : kError,
                  onChanged: (v) => setDlg(() => score = v),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      score >= 22.5 ? 'SUFFICIENTE' : 'INSUFFICIENTE',
                      style: TextStyle(
                        color: score >= 22.5 ? kAccent : kError,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  style: const TextStyle(color: kText),
                  decoration: const InputDecoration(labelText: 'Note (opzionale)', isDense: true),
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
                await _gradeService.addGrade(
                  courseId: course.id,
                  attendeeId: attendeeId,
                  moduleNumber: moduleNumber,
                  type: type,
                  score: score,
                  enteredBy: widget.userId,
                  notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                );
                _reload();
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_courses.isEmpty) {
      return const Center(child: Text('Nessun corso assegnato', style: TextStyle(color: kTextDim)));
    }

    final course = _selected;
    if (course == null) return const SizedBox();

    final typeInfo = _refService.getCourseType(course.courseTypeId);
    final attendees = _userService.getAllUsers()
        .where((u) => course.attendeeIds.contains(u.id))
        .toList();

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
                  onChanged: (id) => setState(() {
                    _selected = _courses.firstWhere((c) => c.id == id);
                  }),
                )
              else
                Text('Voti: ${course.title}', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(icon: const Icon(Icons.refresh, color: kTextDim), onPressed: _reload),
            ],
          ),
        ),
        Expanded(
          child: typeInfo == null || attendees.isEmpty
              ? const Center(child: Text('Nessun dato disponibile', style: TextStyle(color: kTextDim)))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Table(
                      border: TableBorder.all(color: kBorder, width: 0.5),
                      defaultColumnWidth: const FixedColumnWidth(120),
                      columnWidths: const {0: FixedColumnWidth(160)},
                      children: [
                        TableRow(
                          decoration: const BoxDecoration(color: kSurface),
                          children: [
                            _cell('Frequentatore', header: true),
                            ...typeInfo.modules.map((m) => _cell('M${m.number}\n${m.name}', header: true)),
                            _cell('Media', header: true),
                          ],
                        ),
                        ...attendees.map((a) {
                          final summary = _gradeService.getAttendeeSummary(course.id, a.id);
                          double totalScore = 0;
                          int gradeCount = 0;
                          for (final s in summary.values) {
                            if (s.hasGrades) {
                              totalScore += s.weightedAverage;
                              gradeCount++;
                            }
                          }
                          final avg = gradeCount > 0 ? totalScore / gradeCount : null;

                          return TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(a.fullName, style: const TextStyle(color: kText, fontSize: 12)),
                              ),
                              ...typeInfo.modules.map((m) {
                                final s = summary[m.number];
                                return TableCell(
                                  child: InkWell(
                                    onTap: () => _addGrade(course, a.id, m.number),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      alignment: Alignment.center,
                                      child: s == null || !s.hasGrades
                                          ? const Icon(Icons.add, color: kBorder, size: 14)
                                          : Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  s.weightedAverage.toStringAsFixed(1),
                                                  style: TextStyle(
                                                    color: s.isPassing ? kAccent : kError,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                Text(
                                                  '${s.grades.length} val.',
                                                  style: const TextStyle(color: kTextDim, fontSize: 9),
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                );
                              }),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: avg == null
                                    ? const Text('—', style: TextStyle(color: kTextDim, fontSize: 12), textAlign: TextAlign.center)
                                    : Text(
                                        avg.toStringAsFixed(1),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: avg >= 22.5 ? kAccent : kError,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _cell(String text, {bool header = false}) => Padding(
    padding: const EdgeInsets.all(8),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: header ? kText : kTextDim,
        fontWeight: header ? FontWeight.bold : FontWeight.normal,
        fontSize: 11,
      ),
    ),
  );
}
