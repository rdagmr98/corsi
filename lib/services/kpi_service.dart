import '../models/course_models.dart';
import '../models/grade_models.dart';
import '../models/reference_models.dart';
import 'course_service.dart';
import 'grade_service.dart';
import 'reference_service.dart';
import 'schedule_service.dart';

/// Dati aggregati per compilare i KPI MTOE-A-2-1 (a–d).
class KpiCourseSnapshot {
  final Course course;
  final CourseTypeInfo? typeInfo;

  /// (a) scostamento temporale in giorni (stimato).
  final int? temporalDeviationDays;
  final String temporalMethod;
  final int plannedLessons;
  final int confirmedLessons;
  final DateTime? lastConfirmedDate;
  final DateTime? lastPlannedDate;

  /// (b) questionari — non in app.
  final bool hasQuestionnaires;

  /// (c) media valutazioni 0–30 (ultimi tentativi).
  final double? averageScore;
  final int gradedAttempts;

  /// (d) % insufficienze per esame di modulo.
  final List<KpiModuleFailRate> failRates;

  const KpiCourseSnapshot({
    required this.course,
    required this.typeInfo,
    required this.temporalDeviationDays,
    required this.temporalMethod,
    required this.plannedLessons,
    required this.confirmedLessons,
    required this.lastConfirmedDate,
    required this.lastPlannedDate,
    required this.hasQuestionnaires,
    required this.averageScore,
    required this.gradedAttempts,
    required this.failRates,
  });

  String get temporalBand {
    final d = temporalDeviationDays;
    if (d == null) return 'n/d';
    if (d <= 10) return 'Ottimo (0–10 gg)';
    if (d <= 20) return 'Buono (11–20 gg)';
    return 'Non accettabile (>20 gg)';
  }

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
  final _schedule = ScheduleService();
  final _ref = ReferenceService();

  List<Course> coursesForUser({String? directorId, bool allIfAdmin = false}) {
    if (allIfAdmin || directorId == null || directorId.isEmpty) {
      return _courses.getAllCourses();
    }
    return _courses.getCoursesForDirector(directorId);
  }

  KpiCourseSnapshot snapshot(Course course) {
    final typeInfo = _ref.getEffectiveCourseType(
        course.courseTypeId, course.extensionTypeId, course.mamlCombinationId);
    final lessons = _schedule.getLessonsForCourse(course.id);
    final regular = lessons.where((l) => l.timeSlot > 0).toList();
    final confirmed = regular.where((l) => l.confirmed).toList();
    confirmed.sort((a, b) => a.date.compareTo(b.date));
    regular.sort((a, b) => a.date.compareTo(b.date));

    final lastConfirmed =
        confirmed.isEmpty ? null : confirmed.last.date;
    final lastPlanned = regular.isEmpty ? null : regular.last.date;

    // Scostamento: differenza tra ultima lezione pianificata e ultima svolta
    // (proxy del ritardo calendario rispetto al programma).
    int? deviation;
    var method =
        'Differenza giorni tra ultima lezione pianificata e ultima svolta';
    if (lastPlanned != null && lastConfirmed != null) {
      deviation = lastPlanned.difference(lastConfirmed).inDays.abs();
      if (lastConfirmed.isAfter(lastPlanned) ||
          lastConfirmed.isAtSameMomentAs(lastPlanned)) {
        deviation = 0;
      } else {
        deviation = lastPlanned.difference(lastConfirmed).inDays;
      }
    } else if (course.endDate != null && lastConfirmed != null) {
      // Fallback: fine corso pianificata vs progresso attuale
      final today = DateTime.now();
      if (today.isAfter(course.endDate!) &&
          confirmed.length < regular.length) {
        deviation = today.difference(course.endDate!).inDays;
        method =
            'Fallback: oggi oltre fine corso pianificata con lezioni residue';
      }
    }

    final allGrades = _grades.getGradesForCourse(course.id);
    // Media KPI (c): media aritmetica di tutti i voti (accertamenti + esami)
    // come da testo KPI — non solo ultimi tentativi.
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
      // Per frequentatore: ultimo tentativo esame
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
      temporalDeviationDays: deviation,
      temporalMethod: method,
      plannedLessons: regular.length,
      confirmedLessons: confirmed.length,
      lastConfirmedDate: lastConfirmed,
      lastPlannedDate: lastPlanned,
      hasQuestionnaires: false,
      averageScore: avg,
      gradedAttempts: allGrades.length,
      failRates: failRates,
    );
  }
}
