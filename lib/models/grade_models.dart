enum AssessmentType { accertamento, esame }

extension AssessmentTypeExt on AssessmentType {
  String get value =>
      this == AssessmentType.accertamento ? 'accertamento' : 'esame';
  String get label =>
      this == AssessmentType.accertamento ? 'Accertamento' : 'Esame';
  int get weight => this == AssessmentType.accertamento ? 1 : 2;

  static AssessmentType fromString(String s) =>
      s == 'esame' ? AssessmentType.esame : AssessmentType.accertamento;
}

class Grade {
  final String id;
  final String courseId;
  final String attendeeId;
  final int moduleNumber;
  final String type;
  final double score;
  final DateTime date;
  final String enteredBy;
  final String? notes;
  final DateTime createdAt;

  const Grade({
    required this.id,
    required this.courseId,
    required this.attendeeId,
    required this.moduleNumber,
    required this.type,
    required this.score,
    required this.date,
    required this.enteredBy,
    this.notes,
    required this.createdAt,
  });

  AssessmentType get assessmentType => AssessmentTypeExt.fromString(type);
  bool get isPassing => score >= 22.5;

  factory Grade.fromJson(Map<String, dynamic> j) => Grade(
    id: j['id'] as String,
    courseId: j['course_id'] as String,
    attendeeId: j['attendee_id'] as String,
    moduleNumber: j['module_number'] as int,
    type: j['type'] as String? ?? 'accertamento',
    score: (j['score'] as num?)?.toDouble() ?? 0.0,
    date: DateTime.parse(j['date'] as String),
    enteredBy: j['entered_by'] as String? ?? '',
    notes: j['notes'] as String?,
    createdAt: DateTime.parse(
      j['created_at'] as String? ?? DateTime.now().toIso8601String(),
    ),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'course_id': courseId,
    'attendee_id': attendeeId,
    'module_number': moduleNumber,
    'type': type,
    'score': score,
    'date': date.toIso8601String().split('T').first,
    'entered_by': enteredBy,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
  };
}

class InstructorUpdate {
  final String id;
  final String instructorId;
  final String type;
  final String? courseId;
  final double hours;
  final DateTime date;
  final String description;
  final DateTime createdAt;

  const InstructorUpdate({
    required this.id,
    required this.instructorId,
    required this.type,
    this.courseId,
    required this.hours,
    required this.date,
    required this.description,
    required this.createdAt,
  });

  bool get isTeaching => type == 'teaching';
  bool get isProfessional => type == 'professional';

  factory InstructorUpdate.fromJson(Map<String, dynamic> j) => InstructorUpdate(
    id: j['id'] as String,
    instructorId: j['instructor_id'] as String,
    type: j['type'] as String? ?? 'teaching',
    courseId: j['course_id'] as String?,
    hours: (j['hours'] as num?)?.toDouble() ?? 0.0,
    date: DateTime.parse(j['date'] as String),
    description: j['description'] as String? ?? '',
    createdAt: DateTime.parse(
      j['created_at'] as String? ?? DateTime.now().toIso8601String(),
    ),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'instructor_id': instructorId,
    'type': type,
    'course_id': courseId,
    'hours': hours,
    'date': date.toIso8601String().split('T').first,
    'description': description,
    'created_at': createdAt.toIso8601String(),
  };
}

class AttendeeGradeSummary {
  final String attendeeId;
  final int moduleNumber;
  final List<Grade> grades;

  const AttendeeGradeSummary({
    required this.attendeeId,
    required this.moduleNumber,
    required this.grades,
  });

  double get weightedAverage {
    final valid = grades.where((g) => g.isPassing).toList();
    if (valid.isEmpty) return 0;
    double totalWeightedScore = 0;
    int totalWeight = 0;
    for (final g in valid) {
      final w = g.assessmentType.weight;
      totalWeightedScore += g.score * w;
      totalWeight += w;
    }
    return totalWeight == 0 ? 0 : totalWeightedScore / totalWeight;
  }

  bool get hasFailing => grades.any((g) => !g.isPassing);

  bool get isPassing => weightedAverage >= 22.5;
  bool get hasGrades => grades.isNotEmpty;
}
