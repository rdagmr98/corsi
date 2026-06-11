import '../models/grade_models.dart';
import 'gh_db_service.dart';

class GradeService {
  final _db = GhDbService();

  List<Grade> getAllGrades() => _db.grades.map(Grade.fromJson).toList();

  List<Grade> getGradesForCourse(String courseId) =>
      getAllGrades().where((g) => g.courseId == courseId).toList();

  List<Grade> getGradesForAttendee(String courseId, String attendeeId) =>
      getGradesForCourse(courseId)
          .where((g) => g.attendeeId == attendeeId)
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));

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
    return map.map((k, v) => MapEntry(
      k,
      AttendeeGradeSummary(attendeeId: attendeeId, moduleNumber: k, grades: v),
    ));
  }

  Future<Grade> addGrade({
    required String courseId,
    required String attendeeId,
    required int moduleNumber,
    required AssessmentType type,
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

  // Instructor updates
  List<InstructorUpdate> getUpdatesForInstructor(String instructorId) =>
      _db.updates
          .map(InstructorUpdate.fromJson)
          .where((u) => u.instructorId == instructorId)
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  double getTeachingHoursRollingYear(String instructorId) {
    final cutoff = DateTime.now().subtract(const Duration(days: 365));
    return getUpdatesForInstructor(instructorId)
        .where((u) => u.isTeaching && u.date.isAfter(cutoff))
        .fold(0.0, (s, u) => s + u.hours);
  }

  double getProfessionalUpdateHoursLast2Years(String instructorId) {
    final cutoff = DateTime.now().subtract(const Duration(days: 730));
    return getUpdatesForInstructor(instructorId)
        .where((u) => u.isProfessional && u.date.isAfter(cutoff))
        .fold(0.0, (s, u) => s + u.hours);
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
    };
    updates.add(entry);
    await _db.saveUpdates(updates);
    return InstructorUpdate.fromJson(entry);
  }

  /// Overall graduation score: sum(score × weight) / sum(weights) for passing grades only.
  double getGraduationScore(String courseId, String attendeeId) {
    final grades = getGradesForAttendee(courseId, attendeeId)
        .where((g) => g.isPassing)
        .toList();
    if (grades.isEmpty) return 0;
    double total = 0;
    int totalWeight = 0;
    for (final g in grades) {
      final w = g.assessmentType.weight;
      total += g.score * w;
      totalWeight += w;
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
