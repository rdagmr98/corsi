import '../models/course_models.dart';
import '../models/grade_models.dart';
import '../models/reference_models.dart';
import 'course_service.dart';
import 'grade_service.dart';
import 'reference_service.dart';

/// Snapshot KPI corso: media voti + % insufficienze esami modulo.
class KpiCourseSnapshot {
  final Course course;
  final CourseTypeInfo? typeInfo;
  final DateTime? periodFrom;
  final DateTime? periodTo;

  /// Media aritmetica voti 0–30 (accertamenti + esami nel periodo).
  final double? averageScore;
  final int gradedAttempts;

  /// % insufficienze per esame di modulo (ultimi tentativi nel periodo).
  final List<KpiModuleFailRate> failRates;

  const KpiCourseSnapshot({
    required this.course,
    required this.typeInfo,
    required this.periodFrom,
    required this.periodTo,
    required this.averageScore,
    required this.gradedAttempts,
    required this.failRates,
  });

  String get averageBand {
    final a = averageScore;
    if (a == null) return 'n/d';
    if (a < 22) return 'Non accettabile (18–21)';
    if (a <= 26) return 'Buono (22–26)';
    return 'Ottimo (27–30)';
  }
}

class KpiModuleFailRate {
  final int moduleNumber;
  final String label;
  final int examAttempts;
  final int failures;
  final double failPercent;

  const KpiModuleFailRate({
    required this.moduleNumber,
    required this.label,
    required this.examAttempts,
    required this.failures,
    required this.failPercent,
  });

  String get band {
    if (examAttempts == 0) return 'n/d';
    if (failPercent > 50) return 'Non accettabile (>50%)';
    if (failPercent >= 30) return 'Buono (30–50%)';
    return 'Ottimo (<30%)';
  }
}

class KpiService {
  final _courses = CourseService();
  final _grades = GradeService();
  final _ref = ReferenceService();

  List<Course> coursesForUser({String? directorId, bool allIfAdmin = false}) {
    if (allIfAdmin || directorId == null || directorId.isEmpty) {
      return _courses.getAllCourses();
    }
    return _courses.getCoursesForDirector(directorId);
  }

  KpiCourseSnapshot snapshot(
    Course course, {
    DateTime? from,
    DateTime? to,
  }) {
    final typeInfo = _ref.getEffectiveCourseType(
        course.courseTypeId, course.extensionTypeId, course.mamlCombinationId);

    final dayFrom = from == null
        ? null
        : DateTime(from.year, from.month, from.day);
    final dayTo = to == null ? null : DateTime(to.year, to.month, to.day);

    bool inPeriod(Grade g) {
      final d = DateTime(g.date.year, g.date.month, g.date.day);
      if (dayFrom != null && d.isBefore(dayFrom)) return false;
      if (dayTo != null && d.isAfter(dayTo)) return false;
      return true;
    }

    final allGrades =
        _grades.getGradesForCourse(course.id).where(inPeriod).toList();

    double? avg;
    if (allGrades.isNotEmpty) {
      avg = allGrades.map((g) => g.score).reduce((a, b) => a + b) /
          allGrades.length;
    }

    final failRates = <KpiModuleFailRate>[];
    final mods = typeInfo?.modules ?? const <ModuleInfo>[];
    for (final m in mods) {
      final exams = allGrades
          .where((g) =>
              g.moduleNumber == m.number &&
              g.assessmentType == AssessmentType.esame)
          .toList();
      if (exams.isEmpty) continue;
      // Per frequentatore: ultimo tentativo esame nel periodo
      final byAtt = <String, Grade>{};
      for (final g in exams) {
        byAtt[g.attendeeId] = g; // ordine JSON = cronologico
      }
      final latest = byAtt.values.toList();
      final fails = latest.where((g) => !g.isPassing).length;
      failRates.add(KpiModuleFailRate(
        moduleNumber: m.number,
        label: 'M${m.displayCode}',
        examAttempts: latest.length,
        failures: fails,
        failPercent: latest.isEmpty ? 0 : fails * 100.0 / latest.length,
      ));
    }

    return KpiCourseSnapshot(
      course: course,
      typeInfo: typeInfo,
      periodFrom: from,
      periodTo: to,
      averageScore: avg,
      gradedAttempts: allGrades.length,
      failRates: failRates,
    );
  }
}
