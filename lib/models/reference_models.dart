class PracticalTask {
  final int id;
  final int plannedHours;

  const PracticalTask({required this.id, required this.plannedHours});

  factory PracticalTask.fromJson(Map<String, dynamic> j) => PracticalTask(
    id: (j['id'] as num).toInt(),
    plannedHours: j['plannedHours'] as int? ?? 0,
  );
}

class SubmoduleInfo {
  final String code;
  final String name;
  final int theoryHours;
  final int practicalHours;
  final int? levelB1;
  final int? levelB2;
  final List<String> topics;
  final List<PracticalTask> practicalTasks;

  const SubmoduleInfo({
    required this.code,
    required this.name,
    required this.theoryHours,
    required this.practicalHours,
    this.levelB1,
    this.levelB2,
    this.topics = const [],
    this.practicalTasks = const [],
  });

  factory SubmoduleInfo.fromJson(Map<String, dynamic> j) => SubmoduleInfo(
    code: j['code'] as String,
    name: j['name'] as String,
    theoryHours: j['theoryHours'] as int? ?? 0,
    practicalHours: j['practicalHours'] as int? ?? 0,
    levelB1: j['levelB1'] as int?,
    levelB2: j['levelB2'] as int?,
    topics: List<String>.from(j['topics'] as List? ?? []),
    practicalTasks: (j['practicalTasks'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(PracticalTask.fromJson)
        .toList(),
  );
}

class ModuleInfo {
  final int number;
  // Etichetta da mostrare al posto del numero (es. '11A' per il modulo 11,
  // '11B' per il modulo 18). Se assente si mostra il numero.
  final String? label;
  final String name;
  final int theoryHours;
  final int practicalHours;
  final int examQuestions;
  final int examMinutes;
  final List<SubmoduleInfo> submodules;

  const ModuleInfo({
    required this.number,
    this.label,
    required this.name,
    required this.theoryHours,
    required this.practicalHours,
    this.examQuestions = 0,
    this.examMinutes = 0,
    this.submodules = const [],
  });

  int get totalHours => theoryHours + practicalHours;

  String get displayCode => label ?? '$number';

  factory ModuleInfo.fromJson(Map<String, dynamic> j) => ModuleInfo(
    number: j['number'] as int,
    label: j['label'] as String?,
    name: j['name'] as String,
    theoryHours: j['theoryHours'] as int? ?? 0,
    practicalHours: j['practicalHours'] as int? ?? 0,
    examQuestions: j['examQuestions'] as int? ?? 0,
    examMinutes: j['examMinutes'] as int? ?? 0,
    submodules: (j['submodules'] as List? ?? [])
        .map((s) => SubmoduleInfo.fromJson(s as Map<String, dynamic>))
        .toList(),
  );
}

class TimeSlot {
  final int slot;
  final String start;
  final String end;

  const TimeSlot({required this.slot, required this.start, required this.end});

  factory TimeSlot.fromJson(Map<String, dynamic> j) => TimeSlot(
    slot: j['slot'] as int,
    start: j['start'] as String,
    end: j['end'] as String,
  );
}

class ScheduleTemplate {
  final List<TimeSlot> mondayThursday;
  final List<TimeSlot> friday;
  final int hoursPerWeek;

  const ScheduleTemplate({
    required this.mondayThursday,
    required this.friday,
    required this.hoursPerWeek,
  });

  factory ScheduleTemplate.fromJson(Map<String, dynamic> j) => ScheduleTemplate(
    mondayThursday: (j['mondayThursday'] as List? ?? [])
        .map((s) => TimeSlot.fromJson(s as Map<String, dynamic>))
        .toList(),
    friday: (j['friday'] as List? ?? [])
        .map((s) => TimeSlot.fromJson(s as Map<String, dynamic>))
        .toList(),
    hoursPerWeek: j['hoursPerWeek'] as int? ?? 27,
  );

  List<TimeSlot> slotsForWeekday(int weekday) =>
      weekday == DateTime.friday ? friday : mondayThursday;
}

class CourseTypeInfo {
  final String id;
  final String code;
  final String name;
  final String category;
  final int maxAttendees;
  final ScheduleTemplate schedule;
  final List<ModuleInfo> modules;

  const CourseTypeInfo({
    required this.id,
    required this.code,
    required this.name,
    required this.category,
    required this.maxAttendees,
    required this.schedule,
    required this.modules,
  });

  int get totalTheoryHours =>
      modules.fold(0, (s, m) => s + m.theoryHours);
  int get totalPracticalHours =>
      modules.fold(0, (s, m) => s + m.practicalHours);
  int get totalHours => totalTheoryHours + totalPracticalHours;
  int get estimatedWeeks => (totalHours / schedule.hoursPerWeek).ceil();

  factory CourseTypeInfo.fromJson(Map<String, dynamic> j) => CourseTypeInfo(
    id: j['id'] as String,
    code: j['code'] as String,
    name: j['name'] as String,
    category: j['category'] as String,
    maxAttendees: j['maxAttendees'] as int? ?? 28,
    schedule: ScheduleTemplate.fromJson(j['schedule'] as Map<String, dynamic>),
    modules: (j['modules'] as List? ?? [])
        .map((m) => ModuleInfo.fromJson(m as Map<String, dynamic>))
        .toList(),
  );
}

class GradingRules {
  final int scale;
  final double passThreshold;
  final double passScore;
  final int assessmentWeight;
  final int examWeight;

  const GradingRules({
    required this.scale,
    required this.passThreshold,
    required this.passScore,
    required this.assessmentWeight,
    required this.examWeight,
  });

  factory GradingRules.fromJson(Map<String, dynamic> j) => GradingRules(
    scale: j['scale'] as int? ?? 30,
    passThreshold: (j['passThreshold'] as num?)?.toDouble() ?? 0.75,
    passScore: (j['passScore'] as num?)?.toDouble() ?? 22.5,
    assessmentWeight: j['assessmentWeight'] as int? ?? 1,
    examWeight: j['examWeight'] as int? ?? 2,
  );
}

// Qualifica istruttore secondo l'ANNESSO MTOE-P-3-1 (regole AMC).
class AmcQualification {
  final String id;
  final String label;
  final String group;

  const AmcQualification({
    required this.id,
    required this.label,
    required this.group,
  });

  factory AmcQualification.fromJson(Map<String, dynamic> j) => AmcQualification(
    id: j['id'] as String,
    label: j['label'] as String,
    group: j['group'] as String? ?? '',
  );
}

class InstructorCurrencyRules {
  final int teachingHoursPerYear;
  final int professionalUpdateHoursPer2Years;

  const InstructorCurrencyRules({
    required this.teachingHoursPerYear,
    required this.professionalUpdateHoursPer2Years,
  });

  factory InstructorCurrencyRules.fromJson(Map<String, dynamic> j) =>
      InstructorCurrencyRules(
        teachingHoursPerYear: j['teachingHoursPerYear'] as int? ?? 6,
        professionalUpdateHoursPer2Years:
            j['professionalUpdateHoursPer2Years'] as int? ?? 35,
      );
}
