import '../models/course_models.dart';
import 'gh_db_service.dart';

class CourseService {
  final _db = GhDbService();

  List<Course> getAllCourses() {
    final courses = _db.courses.map(Course.fromJson).toList();
    courses.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return courses;
  }

  List<Course> getActiveCourses() =>
      getAllCourses().where((c) => c.isActive).toList();

  List<Course> getCoursesForDirector(String userId) =>
      getAllCourses().where((c) => c.directorIds.contains(userId)).toList();

  List<Course> getCoursesForInstructor(String userId) =>
      getAllCourses().where((c) => c.instructorIds.contains(userId)).toList();

  List<Course> getCoursesForAttendee(String userId) =>
      getAllCourses().where((c) => c.attendeeIds.contains(userId)).toList();

  Course? findById(String id) {
    try {
      return getAllCourses().firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<Course> createCourse({
    required String courseTypeId,
    required String title,
    required String createdBy,
    DateTime? startDate,
    String? mamlCombinationId,
    List<String> directorIds = const [],
    List<String> attendeeIds = const [],
    List<String> instructorIds = const [],
  }) async {
    final courses = _db.courses.toList();
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toRadixString(16);
    final draft = Course(
      id: id,
      courseTypeId: courseTypeId,
      mamlCombinationId: mamlCombinationId,
      title: title,
      startDate: startDate,
      status: 'planning',
      directorIds: directorIds,
      attendeeIds: attendeeIds,
      instructorIds: instructorIds,
      defaultAula: null,
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );
    final newCourse = {
      ...draft.toJson(),
      // Persist inferred 3° BTC default so JSON carries it.
      if (draft.resolvedDefaultAula != null)
        'default_aula': draft.resolvedDefaultAula,
    };
    courses.add(newCourse);
    await _db.saveCourses(courses);
    return Course.fromJson(newCourse);
  }

  Future<void> updateCourse(Course updated) async {
    final courses = _db.courses.toList();
    final idx = courses.indexWhere((c) => c['id'] == updated.id);
    if (idx < 0) return;
    courses[idx] = {
      ...courses[idx],
      ...updated.toJson(),
      'updated_at': DateTime.now().toIso8601String(),
    };
    await _db.saveCourses(courses);
  }

  Future<void> deleteCourse(String courseId) async {
    final courses = _db.courses.where((c) => c['id'] != courseId).toList();
    await _db.saveCourses(courses);
  }

  Future<void> activateCourse(String courseId) async {
    final course = findById(courseId);
    if (course == null) return;
    await updateCourse(course.copyWith(
      status: 'active',
      startDate: course.startDate ?? DateTime.now(),
    ));
  }

  Future<void> completeCourse(String courseId) async {
    final course = findById(courseId);
    if (course == null) return;
    // endDate = DATA FINE CORSO (PIANIFICATA) sul PS — non sovrascrivere.
    await updateCourse(course.copyWith(status: 'completed'));
  }

  /// Riempie header PS 3° BTC da `66_PS` ufficiale se fine/durata mancano.
  /// Se manca il seed (fine o durata), allinea anche inizio ai valori foglio EI.
  Future<Course> ensurePsHeaderDefaults(Course course) async {
    if (!course.is3Btc) return course;
    var next = course;
    var changed = false;
    final needsSeed = next.endDate == null || next.durationWeeks == null;
    if (needsSeed) {
      next = next.copyWith(
        startDate: Course.btc3Start,
        endDate: Course.btc3PlannedEnd,
        durationWeeks: Course.btc3DurationWeeks,
      );
      changed = true;
    }
    if (next.defaultAula == null && next.resolvedDefaultAula != null) {
      next = next.copyWith(defaultAula: next.resolvedDefaultAula);
      changed = true;
    }
    if (!changed) return course;
    await updateCourse(next);
    return findById(course.id) ?? next;
  }
}
