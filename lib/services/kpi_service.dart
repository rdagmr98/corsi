import '../models/course_models.dart';
import '../models/grade_models.dart';
import '../models/reference_models.dart';
import '../models/user_models.dart';
import 'course_service.dart';
import 'grade_service.dart';
import 'reference_service.dart';
import 'user_service.dart';

/// Snapshot KPI corso: media voti + % insufficienze esami modulo.
class KpiCourseSnapshot {
  final Course course;
  final CourseTypeInfo? typeInfo;
  final DateTime? periodFrom;
  final DateTime? periodTo;

  /// Media aritmetica su **tutti** i tentativi (accertamenti + esami) nel
  /// periodo, inclusi i fallimenti poi recuperati. Non usa [AttendeeGradeSummary]
  /// / effectiveScore / solo ultimo tentativo — quelli restano per la graduatoria.
  final double? averageScore;
  final int gradedAttempts;

  /// % insufficienze su **tutti** i tentativi d'esame modulo nel periodo
  /// (un fail recuperato conta ancora come insufficienza).
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
  final _users = UserService();

  List<Course> coursesForUser({String? directorId, bool allIfAdmin = false}) {
    if (allIfAdmin || directorId == null || directorId.isEmpty) {
      return _courses.getAllCourses();
    }
    return _courses.getCoursesForDirector(directorId);
  }

  /// Frequentatori del corso (nome ordinato) per il filtro KPI.
  List<AppUser> attendeesForCourse(Course course) {
    final out = <AppUser>[];
    for (final id in course.attendeeIds) {
      final u = _users.findById(id);
      if (u != null) out.add(u);
    }
    out.sort((a, b) => a.fullName.compareTo(b.fullName));
    return out;
  }

  /// [attendeeIds] null o vuoto = tutti i frequentatori del corso.
  KpiCourseSnapshot snapshot(
    Course course, {
    DateTime? from,
    DateTime? to,
    Set<String>? attendeeIds,
  }) {
    final typeInfo = _ref.getEffectiveCourseType(
        course.courseTypeId, course.extensionTypeId, course.mamlCombinationId);

    final dayFrom = from == null
        ? null
        : DateTime(from.year, from.month, from.day);
    final dayTo = to == null ? null : DateTime(to.year, to.month, to.day);
    final filterAtt =
        attendeeIds == null || attendeeIds.isEmpty ? null : attendeeIds;

    bool inScope(Grade g) {
      if (filterAtt != null && !filterAtt.contains(g.attendeeId)) return false;
      final d = DateTime(g.date.year, g.date.month, g.date.day);
      if (dayFrom != null && d.isBefore(dayFrom)) return false;
      if (dayTo != null && d.isAfter(dayTo)) return false;
      return true;
    }

    // Tutti i tentativi nel periodo (fail recuperati inclusi) — non latestAttempts.
    final allGrades =
        _grades.getGradesForCourse(course.id).where(inScope).toList();

    double? avg;
    if (allGrades.isNotEmpty) {
      avg = allGrades.map((g) => g.score).reduce((a, b) => a + b) /
          allGrades.length;
    }

    final failRates = <KpiModuleFailRate>[];
    final mods = typeInfo?.modules ?? const <ModuleInfo>[];
    for (final m in mods) {
      // Tutti i tentativi d'esame del modulo: un fail poi recuperato resta
      // nel numeratore (non si tiene solo l'ultimo tentativo per frequentatore).
      final exams = allGrades
          .where((g) =>
              g.moduleNumber == m.number &&
              g.assessmentType == AssessmentType.esame)
          .toList();
      if (exams.isEmpty) continue;
      final fails = exams.where((g) => !g.isPassing).length;
      failRates.add(KpiModuleFailRate(
        moduleNumber: m.number,
        label: 'M${m.displayCode}',
        examAttempts: exams.length,
        failures: fails,
        failPercent: fails * 100.0 / exams.length,
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
