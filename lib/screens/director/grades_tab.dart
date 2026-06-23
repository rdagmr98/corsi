import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
import '../../models/grade_models.dart';
import '../../models/reference_models.dart';
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

  // Dialog di inserimento/modifica voto con input da tastiera (0–30, virgola o punto).
  Future<void> _gradeDialog(Course course, String attendeeId, ModuleInfo module,
      {Grade? existing}) async {
    final moduleNumber = module.number;

    // Voti già esistenti per questo modulo/frequentatore: servono per
    // proporre il numero di accertamento giusto (nuovo o da recuperare) e
    // per bloccare un tentativo oltre il massimo consentito o oltre il
    // numero di accertamenti previsti dal modulo (assessmentCount).
    final existingGrades = _gradeService
        .getGradesForAttendee(course.id, attendeeId)
        .where((g) => g.moduleNumber == moduleNumber)
        .toList();
    final summary = AttendeeGradeSummary(
        attendeeId: attendeeId,
        moduleNumber: moduleNumber,
        grades: existingGrades,
        assessmentCount: module.assessmentCount);

    AssessmentType type = existing?.assessmentType ??
        (summary.addableAccertamentoNumbers.isEmpty
            ? AssessmentType.esame
            : AssessmentType.accertamento);
    DateTime gradeDate = existing?.date ?? DateTime.now();
    final scoreCtrl = TextEditingController(
        text: existing == null
            ? ''
            : (existing.score % 1 == 0
                ? existing.score.toStringAsFixed(0)
                : existing.score.toStringAsFixed(1)));
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    int accertamentoNumber = existing?.accertamentoNumber ??
        (summary.addableAccertamentoNumbers.isNotEmpty
            ? summary.addableAccertamentoNumbers.first
            : summary.assessmentCount);

    double? parseScore() {
      final v = double.tryParse(scoreCtrl.text.trim().replaceAll(',', '.'));
      if (v == null || v < 0 || v > 30) return null;
      return v;
    }

    bool esameExhausted() {
      if (type != AssessmentType.esame || existing != null) return false;
      final list = existingGrades.where((g) => g.assessmentType == AssessmentType.esame).length;
      return list >= AssessmentType.esame.maxAttempts;
    }

    // true se si vuole inserire un NUOVO accertamento ma il modulo non ne
    // prevede altri (assessmentCount già raggiunto, o tentativi esauriti su
    // tutti gli accertamenti esistenti): non c'è più nulla da proporre.
    bool accertamentoBlocked() {
      if (type != AssessmentType.accertamento || existing != null) return false;
      return summary.addableAccertamentoNumbers.isEmpty;
    }

    Future<void> save(BuildContext ctx) async {
      final score = parseScore();
      if (score == null || esameExhausted() || accertamentoBlocked()) return;
      Navigator.pop(ctx);
      final number = type == AssessmentType.esame ? 1 : accertamentoNumber;
      if (existing == null) {
        await _gradeService.addGrade(
          courseId: course.id,
          attendeeId: attendeeId,
          moduleNumber: moduleNumber,
          type: type,
          accertamentoNumber: number,
          score: score,
          enteredBy: widget.userId,
          date: gradeDate,
          notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        );
      } else {
        await _gradeService.updateGrade(existing.copyWith(
          type: type.value,
          accertamentoNumber: number,
          score: score,
          date: gradeDate,
          notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        ));
      }
      if (mounted) setState(() {});
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final score = parseScore();
          return AlertDialog(
            backgroundColor: kCard,
            title: Text(existing == null ? 'Inserisci voto' : 'Modifica voto',
                style: const TextStyle(color: kText)),
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
                  if (type == AssessmentType.accertamento) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: (existing == null
                              ? summary.addableAccertamentoNumbers
                              : {
                                  ...summary.accertamentoNumbers,
                                  summary.nextAccertamentoNumber,
                                  existing.accertamentoNumber,
                                })
                          .contains(accertamentoNumber)
                          ? accertamentoNumber
                          : null,
                      dropdownColor: kSurface,
                      style: const TextStyle(color: kText),
                      decoration: const InputDecoration(labelText: 'Accertamento', isDense: true),
                      items: (existing == null
                              ? summary.addableAccertamentoNumbers
                              : ({
                                  ...summary.accertamentoNumbers,
                                  summary.nextAccertamentoNumber,
                                  existing.accertamentoNumber,
                                }.toList()
                                ..sort()))
                          .map((n) => DropdownMenuItem(
                                value: n,
                                child: Text(summary.accertamentoNumbers.contains(n)
                                    ? 'Accertamento $n'
                                    : 'Nuovo accertamento ($n)'),
                              ))
                          .toList(),
                      onChanged: (v) => setDlg(() => accertamentoNumber = v ?? accertamentoNumber),
                    ),
                  ],
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: gradeDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        locale: const Locale('it'),
                      );
                      if (picked != null) setDlg(() => gradeDate = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Data', isDense: true),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              DateFormat('dd/MM/yyyy').format(gradeDate),
                              style: const TextStyle(color: kText),
                            ),
                          ),
                          const Icon(Icons.calendar_today, size: 16, color: kTextDim),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: scoreCtrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: kText, fontSize: 20, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      labelText: 'Voto (0–30)',
                      hintText: 'es. 24,5',
                      isDense: true,
                    ),
                    onChanged: (_) => setDlg(() {}),
                    onSubmitted: (_) => save(ctx),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    score == null
                        ? (scoreCtrl.text.trim().isEmpty ? ' ' : 'Valore non valido (0–30)')
                        : (score >= 22.5 ? 'SUFFICIENTE' : 'INSUFFICIENTE'),
                    style: TextStyle(
                      color: score != null && score >= 22.5 ? kAccent : kError,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  if (esameExhausted())
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Numero massimo di tentativi raggiunto per l\'esame '
                        '(${AssessmentType.esame.maxAttempts})',
                        style: const TextStyle(color: kError, fontSize: 11),
                      ),
                    ),
                  if (accertamentoBlocked())
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Il modulo prevede ${summary.assessmentCount} '
                        '${summary.assessmentCount == 1 ? "accertamento" : "accertamenti"}: '
                        'già tutti inseriti o con tentativi esauriti',
                        style: const TextStyle(color: kError, fontSize: 11),
                      ),
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
                onPressed: score == null || esameExhausted() || accertamentoBlocked()
                    ? null
                    : () => save(ctx),
                child: Text(existing == null ? 'Salva' : 'Aggiorna'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _confirmDeleteGrade(Grade g, AttendeeGradeSummary summary) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Elimina voto', style: TextStyle(color: kText)),
        content: Text(
          'Eliminare il voto ${g.score.toStringAsFixed(1)} (${summary.chipLabel(g)}) '
          'del ${DateFormat('dd/MM/yyyy').format(g.date)}?',
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
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _gradeService.deleteGrade(g.id);
      if (mounted) setState(() {});
      return true;
    }
    return false;
  }

  // Dettaglio voti del modulo: tipo (accertamento/esame), voto, data, note,
  // con modifica/eliminazione e aggiunta.
  Future<void> _moduleGradesDialog(
      Course course, String attendeeId, String attendeeName, ModuleInfo module) async {
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final grades = _gradeService
              .getGradesForAttendee(course.id, attendeeId)
              .where((g) => g.moduleNumber == module.number)
              .toList();
          final summary = AttendeeGradeSummary(
              attendeeId: attendeeId,
              moduleNumber: module.number,
              grades: grades,
              assessmentCount: module.assessmentCount);
          return AlertDialog(
            backgroundColor: kCard,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('M${module.displayCode} — $attendeeName',
                    style: const TextStyle(color: kText, fontSize: 15)),
                Text(module.name,
                    style: const TextStyle(color: kTextDim, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: grades.isEmpty
                  ? const Text('Nessun voto registrato.', style: TextStyle(color: kTextDim, fontSize: 13))
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: grades.map((g) {
                        final isEsame = g.assessmentType == AssessmentType.esame;
                        final typeColor = isEsame ? kWarning : kPrimary;
                        final attemptLabel = summary.attemptLabel(g);
                        final recoveryNote = summary.recoveryNote(g);
                        final capNote = summary.recoveryCapNote(g);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Container(
                                width: 92,
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: typeColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                alignment: Alignment.center,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(summary.chipLabel(g),
                                      maxLines: 1,
                                      style: TextStyle(color: typeColor, fontSize: 10)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 44,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      g.score.toStringAsFixed(1),
                                      style: TextStyle(
                                        color: g.isPassing ? kAccent : kError,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (recoveryNote != null)
                                      Text(recoveryNote,
                                          style: TextStyle(
                                              color: recoveryNote == 'tentativo superato' ? kTextDim : kError,
                                              fontSize: 8)),
                                    if (capNote != null)
                                      Text(capNote,
                                          style: const TextStyle(color: kWarning, fontSize: 8)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(DateFormat('dd/MM/yyyy').format(g.date),
                                        style: const TextStyle(color: kTextDim, fontSize: 11)),
                                    if (attemptLabel != null)
                                      Text(attemptLabel,
                                          style: const TextStyle(color: kTextDim, fontSize: 9)),
                                    if (g.notes != null && g.notes!.isNotEmpty)
                                      Text(g.notes!,
                                          style: const TextStyle(color: kTextDim, fontSize: 10),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, color: kTextDim, size: 18),
                                tooltip: 'Modifica voto',
                                onPressed: () async {
                                  await _gradeDialog(course, attendeeId, module, existing: g);
                                  setDlg(() {});
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: kError, size: 18),
                                tooltip: 'Elimina voto',
                                onPressed: () async {
                                  final deleted = await _confirmDeleteGrade(g, summary);
                                  if (deleted) setDlg(() {});
                                },
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Aggiungi voto'),
                onPressed: () async {
                  await _gradeDialog(course, attendeeId, module);
                  setDlg(() {});
                },
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Chiudi', style: TextStyle(color: kTextDim)),
              ),
            ],
          );
        },
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

    final typeInfo = _refService.getEffectiveCourseType(course.courseTypeId, course.extensionTypeId);
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
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final ranking = _gradeService.getCourseRanking(
                        course.id, course.attendeeIds);
                    final rankMap = {for (final r in ranking) r.attendeeId: r.rank};

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Table(
                          border: TableBorder.all(color: kBorder, width: 0.5),
                          defaultColumnWidth: const FixedColumnWidth(64),
                          columnWidths: const {
                            0: FixedColumnWidth(32),   // Pos.
                            1: FixedColumnWidth(130),  // Nome
                          },
                          children: [
                            TableRow(
                              decoration: const BoxDecoration(color: kSurface),
                              children: [
                                _cell('#', header: true),
                                _cell('Frequentatore', header: true),
                                ...typeInfo.modules.map((m) => Tooltip(
                                  message: 'M${m.displayCode} - ${m.name}',
                                  child: _cell('M${m.displayCode}', header: true),
                                )),
                                _cell('Media', header: true),
                              ],
                            ),
                            ...attendees.map((a) {
                              final summary =
                                  _gradeService.getAttendeeSummary(course.id, a.id);
                              final gradScore = _gradeService.getGraduationScore(course.id, a.id);
                              final hasAny = summary.values.any((s) => s.hasGrades);
                              final pos = rankMap[a.id];

                              return TableRow(
                                children: [
                                  // Pos
                                  Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Text(
                                      pos != null ? '$pos°' : '—',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: kTextDim, fontSize: 10),
                                    ),
                                  ),
                                  // Nome
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 4),
                                    child: Text(a.fullName,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: kText, fontSize: 11)),
                                  ),
                                  // Per-module cells
                                  ...typeInfo.modules.map((m) {
                                    final s = summary[m.number];
                                    return TableCell(
                                      child: InkWell(
                                        onTap: () => s == null || !s.hasGrades
                                            ? _gradeDialog(course, a.id, m)
                                            : _moduleGradesDialog(course, a.id, a.fullName, m),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          alignment: Alignment.center,
                                          child: s == null || !s.hasGrades
                                              ? const Icon(Icons.add,
                                                  color: kBorder, size: 12)
                                              : Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      s.weightedAverage
                                                          .toStringAsFixed(1),
                                                      style: TextStyle(
                                                        color: s.isPassing
                                                            ? kAccent
                                                            : kError,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                    if (s.hasFailing)
                                                      const Icon(Icons.warning,
                                                          color: kWarning,
                                                          size: 8),
                                                  ],
                                                ),
                                        ),
                                      ),
                                    );
                                  }),
                                  // Media globale (graduation score)
                                  Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: !hasAny
                                        ? const Text('—',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                color: kTextDim, fontSize: 11))
                                        : Text(
                                            gradScore.toStringAsFixed(2),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: gradScore >= 22.5
                                                  ? kAccent
                                                  : kError,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                  ),
                                ],
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  },
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
