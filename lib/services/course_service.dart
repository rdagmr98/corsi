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
    List<String> directorIds = const [],
    List<String> attendeeIds = const [],
    List<String> instructorIds = const [],
  }) async {
    final courses = _db.courses.toList();
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toRadixString(16);
    final newCourse = {
      'id': id,
      'course_type_id': courseTypeId,
      'title': title,
      'start_date': startDate?.toIso8601String().split('T').first,
      'end_date': null,
      'status': 'planning',
      'director_ids': directorIds,
      'attendee_ids': attendeeIds,
      'instructor_ids': instructorIds,
      'created_by': createdBy,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
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
    await updateCourse(course.copyWith(
      status: 'completed',
      endDate: DateTime.now(),
    ));
  }
}
