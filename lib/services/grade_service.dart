import '../models/course_models.dart';
import '../models/grade_models.dart';
import '../models/user_models.dart';
import 'gh_db_service.dart';
import 'reference_service.dart';

class GradeService {
  final _db = GhDbService();
  final _refService = ReferenceService();

  List<Grade> getAllGrades() => _db.grades.map(Grade.fromJson).toList();

  List<Grade> getGradesForCourse(String courseId) =>
      getAllGrades().where((g) => g.courseId == courseId).toList();

  // Ordine preservato dal JSON array: l'utente conferma che i voti sono
  // registrati cronologicamente da sinistra a destra nell'array. Il sort per
  // data inverte i recuperi che hanno date errate (recupero < esame originale).
  List<Grade> getGradesForAttendee(String courseId, String attendeeId) =>
      getGradesForCourse(courseId)
          .where((g) => g.attendeeId == attendeeId)
          .toList();

  List<Grade> getGradesForModule(String courseId, int moduleNumber) =>
      getGradesForCourse(courseId)
          .where((g) => g.moduleNumber == moduleNumber)
          .toList();

  Map<int, AttendeeGradeSummary> getAttendeeSummary(String courseId, String attendeeId) {
    final grades = getGradesForAttendee(courseId, attendeeId);
    final map = <int, List<Grade>>{};
    for (final g in grades) {
      map.putIfAbsent(g.moduleNumber, () => []).add(g);
    }
    final assessmentCounts = _assessmentCountsByModule(courseId);
    return map.map((k, v) => MapEntry(
      k,
      AttendeeGradeSummary(
        attendeeId: attendeeId,
        moduleNumber: k,
        grades: v,
        assessmentCount: assessmentCounts[k] ?? 1,
      ),
    ));
  }

  // Numero di accertamenti previsti per modulo (assessmentCount), dal tipo
  // corso effettivo: serve ad AttendeeGradeSummary per non proporre in
  // aggiunta accertamenti oltre quelli previsti dal programma.
  Map<int, int> _assessmentCountsByModule(String courseId) {
    final raw = _db.courses.where((c) => c['id'] == courseId);
    if (raw.isEmpty) return {};
    final course = Course.fromJson(raw.first);
    final typeInfo =
        _refService.getEffectiveCourseType(course.courseTypeId, course.extensionTypeId, course.mamlCombinationId);
    if (typeInfo == null) return {};
    return {for (final m in typeInfo.modules) m.number: m.assessmentCount};
  }

  Future<Grade> addGrade({
    required String courseId,
    required String attendeeId,
    required int moduleNumber,
    required AssessmentType type,
    int accertamentoNumber = 1,
    required double score,
    required String enteredBy,
    DateTime? date,
    String? notes,
  }) async {
    final grades = _db.grades.toList();
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toRadixString(16);
    final newGrade = {
      'id': id,
      'course_id': courseId,
      'attendee_id': attendeeId,
      'module_number': moduleNumber,
      'type': type.value,
      // l'esame è unico per modulo: il numero ha senso solo per gli accertamenti.
      'accertamento_number': type == AssessmentType.esame ? 1 : accertamentoNumber,
      'score': score,
      'date': (date ?? now).toIso8601String().split('T').first,
      'entered_by': enteredBy,
      'notes': notes,
      'created_at': now.toIso8601String(),
    };
    grades.add(newGrade);
    await _db.saveGrades(grades);
    return Grade.fromJson(newGrade);
  }

  Future<void> updateGrade(Grade updated) async {
    final grades = _db.grades.toList();
    final idx = grades.indexWhere((g) => g['id'] == updated.id);
    if (idx < 0) return;
    grades[idx] = updated.toJson();
    await _db.saveGrades(grades);
  }

  Future<void> deleteGrade(String gradeId) async {
    final grades = _db.grades.where((g) => g['id'] != gradeId).toList();
    await _db.saveGrades(grades);
  }

  // Bulk import del 2026-06-06: ore di insegnamento 1/2/3BTC duplicano le ore
  // già contate dalle lezioni confermate a calendario (getConfirmedLessonHoursByCourse).
  // Escluse ovunque: non vanno né mostrate né sommate alla currency.
  static const _bulkImportDescriptions = {
    'Ore insegnamento 1BTC',
    'Ore insegnamento 2BTC',
    'Ore insegnamento 3BTC',
  };
  static bool isBulkImportArtifact(Map<String, dynamic> raw) =>
      raw['type'] == 'teaching' && _bulkImportDescriptions.contains(raw['description']);

  // Instructor updates
  List<InstructorUpdate> getUpdatesForInstructor(String instructorId) =>
      _db.updates
          .where((raw) => !isBulkImportArtifact(raw))
          .map(InstructorUpdate.fromJson)
          .where((u) => u.instructorId == instructorId)
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  List<InstructorUpdate> getPendingUpdates() =>
      _db.updates.map(InstructorUpdate.fromJson).where((u) => u.isPending).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Ore insegnamento da registrazioni manuali (updates.json), ultimi 365 gg.
  /// Conta solo update approvati (non pending).
  double getManualTeachingHoursRollingYear(String instructorId) {
    final cutoff = DateTime.now().subtract(const Duration(days: 365));
    return getUpdatesForInstructor(instructorId)
        .where((u) => u.isTeaching && u.isApproved && u.date.isAfter(cutoff))
        .fold(0.0, (s, u) => s + u.hours);
  }

  /// Ore di lezione validate dal direttore o confermate dall'istruttore
  /// (1h per lezione a calendario con confirmed=true), per corso,
  /// ultimi 365 giorni.
  Map<String, double> getConfirmedLessonHoursByCourse(String instructorId) {
    final cutoff = DateTime.now().subtract(const Duration(days: 365));
    final map = <String, double>{};
    for (final raw in _db.schedules) {
      if (raw['instructor_id'] != instructorId) continue;
      if (raw['confirmed'] != true) continue;
      if (((raw['time_slot'] as num?)?.toInt() ?? 0) <= 0) continue;
      final d = DateTime.tryParse(raw['date'] as String? ?? '');
      if (d == null || !d.isAfter(cutoff)) continue;
      final courseId = raw['course_id'] as String? ?? '';
      map[courseId] = (map[courseId] ?? 0) + 1;
    }
    return map;
  }

  double getConfirmedLessonHoursRollingYear(String instructorId) =>
      getConfirmedLessonHoursByCourse(instructorId)
          .values
          .fold(0.0, (a, b) => a + b);

  /// Totale ai fini del mantenimento currency: lezioni confermate a
  /// calendario + registrazioni manuali.
  double getTeachingHoursRollingYear(String instructorId) =>
      getConfirmedLessonHoursRollingYear(instructorId) +
      getManualTeachingHoursRollingYear(instructorId);

  double getProfessionalUpdateHoursLast2Years(String instructorId) {
    final cutoff = DateTime.now().subtract(const Duration(days: 730));
    return getUpdatesForInstructor(instructorId)
        .where((u) => u.isProfessional && u.isApproved && u.date.isAfter(cutoff))
        .fold(0.0, (s, u) => s + u.hours);
  }

  /// GO/NOGO complessivo. Il DAA (aggiornamento normativa aeronautica)
  /// incide solo sul modulo 10: la scadenza NAM non deve rendere NOGO
  /// un istruttore per gli altri moduli.
  bool isGo(AppUser u, {DateTime? now, int? moduleNumber}) {
    if (u.goOverride) return true;
    final teachOk = getTeachingHoursRollingYear(u.id) >= 6;
    final profOk = getProfessionalUpdateHoursLast2Years(u.id) >= 35;
    if (moduleNumber != 10) return teachOk && profOk;
    final n = now ?? DateTime.now();
    final daaOk = u.daaExpiry == null || u.daaExpiry!.isAfter(n);
    return teachOk && profOk && daaOk;
  }

  Future<InstructorUpdate> addUpdate({
    required String instructorId,
    required String type,
    required double hours,
    required String description,
    String? courseId,
    DateTime? date,
  }) async {
    final updates = _db.updates.toList();
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toRadixString(16);
    final entry = {
      'id': id,
      'instructor_id': instructorId,
      'type': type,
      'course_id': courseId,
      'hours': hours,
      'date': (date ?? now).toIso8601String().split('T').first,
      'description': description,
      'created_at': now.toIso8601String(),
      'status': 'approved',
    };
    updates.add(entry);
    await _db.saveUpdates(updates);
    return InstructorUpdate.fromJson(entry);
  }

  Future<InstructorUpdate> addPendingUpdate({
    required String instructorId,
    required String type,
    required double hours,
    required String description,
    String? courseId,
    DateTime? date,
  }) async {
    final updates = _db.updates.toList();
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toRadixString(16);
    final entry = {
      'id': id,
      'instructor_id': instructorId,
      'type': type,
      'course_id': courseId,
      'hours': hours,
      'date': (date ?? now).toIso8601String().split('T').first,
      'description': description,
      'created_at': now.toIso8601String(),
      'status': 'pending',
    };
    updates.add(entry);
    await _db.saveUpdates(updates);
    return InstructorUpdate.fromJson(entry);
  }

  Future<void> approveUpdate(String updateId) async {
    final updates = _db.updates.toList();
    final idx = updates.indexWhere((u) => u['id'] == updateId);
    if (idx < 0) return;
    updates[idx] = {...updates[idx], 'status': 'approved'};
    await _db.saveUpdates(updates);
  }

  /// Overall graduation score: sum(score × weight) / sum(weights) for passing grades only.
  /// Usa solo l'ultimo tentativo di ciascun accertamento/esame distinto
  /// (via AttendeeGradeSummary), non lo storico completo: altrimenti un
  /// accertamento recuperato dopo un primo tentativo insufficiente, o più
  /// accertamenti distinti dello stesso modulo, falserebbero la media.
  double getGraduationScore(String courseId, String attendeeId) {
    final summaries = getAttendeeSummary(courseId, attendeeId).values;
    double total = 0;
    int totalWeight = 0;
    for (final s in summaries) {
      for (final g in s.latestAttempts.where((g) => g.isPassing)) {
        final w = g.assessmentType.weight;
        total += s.effectiveScore(g) * w;
        totalWeight += w;
      }
    }
    return totalWeight == 0 ? 0 : total / totalWeight;
  }

  List<({String attendeeId, double score, int rank})> getCourseRanking(
      String courseId, List<String> attendeeIds) {
    final scored = attendeeIds
        .map((id) => (id: id, score: getGraduationScore(courseId, id)))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return [
      for (var i = 0; i < scored.length; i++)
        (attendeeId: scored[i].id, score: scored[i].score, rank: i + 1),
    ];
  }

  Future<void> deleteUpdate(String updateId) async {
    final updates = _db.updates.where((u) => u['id'] != updateId).toList();
    await _db.saveUpdates(updates);
  }
}
