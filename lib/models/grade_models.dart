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

  Grade copyWith({String? type, double? score, DateTime? date, String? notes}) => Grade(
    id: id,
    courseId: courseId,
    attendeeId: attendeeId,
    moduleNumber: moduleNumber,
    type: type ?? this.type,
    score: score ?? this.score,
    date: date ?? this.date,
    enteredBy: enteredBy,
    notes: notes ?? this.notes,
    createdAt: createdAt,
  );

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

  /// Voti raggruppati per tipo (accertamento/esame), ordinati dal più
  /// vecchio al più recente: indice+1 = numero del tentativo.
  Map<AssessmentType, List<Grade>> get byType {
    final map = <AssessmentType, List<Grade>>{};
    for (final g in grades) {
      map.putIfAbsent(g.assessmentType, () => []).add(g);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.date.compareTo(b.date));
    }
    return map;
  }

  /// Solo l'ultimo tentativo per ciascun tipo: è questo — non lo storico
  /// completo — a determinare se il modulo è ancora "da recuperare".
  List<Grade> get latestAttempts =>
      byType.values.map((l) => l.last).toList();

  double get weightedAverage {
    final valid = latestAttempts.where((g) => g.isPassing).toList();
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

  bool get hasFailing => latestAttempts.any((g) => !g.isPassing);

  bool get isPassing => weightedAverage >= 22.5;
  bool get hasGrades => grades.isNotEmpty;

  /// Numero di tentativo (1-based) di [g] tra i voti dello stesso tipo.
  int attemptNumber(Grade g) {
    final list = byType[g.assessmentType] ?? const [];
    final idx = list.indexWhere((x) => x.id == g.id);
    return idx < 0 ? 1 : idx + 1;
  }

  int attemptsCount(Grade g) => byType[g.assessmentType]?.length ?? 1;

  /// true se [g] non è l'ultimo tentativo del suo tipo (superato da un
  /// tentativo successivo, indipendentemente dall'esito di quest'ultimo).
  bool isSuperseded(Grade g) {
    final list = byType[g.assessmentType];
    return list != null && list.isNotEmpty && list.last.id != g.id;
  }

  /// Etichetta "Tentativo N di M" da mostrare accanto al voto. Null se è
  /// l'unico tentativo per quel tipo (nessuna ambiguità da chiarire).
  String? attemptLabel(Grade g) {
    final count = attemptsCount(g);
    if (count <= 1) return null;
    return 'Tentativo ${attemptNumber(g)} di $count';
  }

  /// Nota di stato da mostrare sotto un voto negativo. Null se il voto è
  /// positivo. "da recuperare" solo se è l'ultimo tentativo del suo tipo;
  /// un voto negativo superato da un tentativo successivo è "superato".
  String? recoveryNote(Grade g) {
    if (g.isPassing) return null;
    return isSuperseded(g) ? 'tentativo superato' : 'da recuperare';
  }
}
