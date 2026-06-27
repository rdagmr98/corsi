enum AssessmentType { accertamento, esame }

extension AssessmentTypeExt on AssessmentType {
  String get value =>
      this == AssessmentType.accertamento ? 'accertamento' : 'esame';
  String get label =>
      this == AssessmentType.accertamento ? 'Accertamento' : 'Esame';
  int get weight => this == AssessmentType.accertamento ? 1 : 2;

  /// Numero massimo di tentativi consentiti (tentativo iniziale incluso): un
  /// accertamento (distinto) può essere recuperato 3 volte (4 tentativi
  /// totali), l'esame di modulo (uno solo) 2 volte (3 tentativi totali).
  /// Da struttura colonne file 'voti graduatoria' (Test/Esame + N Recupero).
  int get maxAttempts => this == AssessmentType.accertamento ? 4 : 3;

  static AssessmentType fromString(String s) =>
      s == 'esame' ? AssessmentType.esame : AssessmentType.accertamento;
}

class Grade {
  final String id;
  final String courseId;
  final String attendeeId;
  final int moduleNumber;
  final String type;
  /// Numero dell'accertamento distinto all'interno del modulo (1, 2, 3...).
  /// Ogni modulo può avere più accertamenti diversi, ciascuno recuperabile
  /// fino a 3 volte; l'esame è sempre numero 1 (uno solo per modulo).
  final int accertamentoNumber;
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
    this.accertamentoNumber = 1,
    required this.score,
    required this.date,
    required this.enteredBy,
    this.notes,
    required this.createdAt,
  });

  AssessmentType get assessmentType => AssessmentTypeExt.fromString(type);
  bool get isPassing => score >= 22.5;

  Grade copyWith({
    String? type,
    int? accertamentoNumber,
    double? score,
    DateTime? date,
    String? notes,
  }) => Grade(
    id: id,
    courseId: courseId,
    attendeeId: attendeeId,
    moduleNumber: moduleNumber,
    type: type ?? this.type,
    accertamentoNumber: accertamentoNumber ?? this.accertamentoNumber,
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
    accertamentoNumber: j['accertamento_number'] as int? ?? 1,
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
    'accertamento_number': accertamentoNumber,
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
  final String status;

  const InstructorUpdate({
    required this.id,
    required this.instructorId,
    required this.type,
    this.courseId,
    required this.hours,
    required this.date,
    required this.description,
    required this.createdAt,
    this.status = 'approved',
  });

  bool get isTeaching => type == 'teaching';
  bool get isProfessional => type == 'professional';
  bool get isApproved => status == 'approved';
  bool get isPending => status == 'pending';

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
    status: j['status'] as String? ?? 'approved',
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
    'status': status,
  };
}

class AttendeeGradeSummary {
  final String attendeeId;
  final int moduleNumber;
  final List<Grade> grades;
  /// Numero di accertamenti distinti richiesti dal modulo (da ModuleInfo,
  /// file 'voti graduatoria'). Limita le proposte di NUOVI accertamenti:
  /// non si propone mai un accertamento oltre questo numero.
  final int assessmentCount;

  const AttendeeGradeSummary({
    required this.attendeeId,
    required this.moduleNumber,
    required this.grades,
    this.assessmentCount = 1,
  });

  /// Voti raggruppati per accertamento/esame DISTINTO (tipo + numero),
  /// ordinati dal più vecchio al più recente: indice+1 = numero del
  /// tentativo per QUEL singolo accertamento (non per tutti quelli del
  /// modulo, che possono essere più di uno).
  Map<(AssessmentType, int), List<Grade>> get byAssessment {
    final map = <(AssessmentType, int), List<Grade>>{};
    for (final g in grades) {
      map.putIfAbsent((g.assessmentType, g.accertamentoNumber), () => []).add(g);
    }
    // NON sort per data: alcune date recupero sono errate (< data esame).
    // L'ordine dell'array JSON è già cronologico (confermato dall'utente).
    return map;
  }

  /// Numeri di accertamento distinti già usati nel modulo, ordinati.
  List<int> get accertamentoNumbers => byAssessment.keys
      .where((k) => k.$1 == AssessmentType.accertamento)
      .map((k) => k.$2)
      .toSet()
      .toList()
    ..sort();

  /// Prossimo numero libero da proporre per un NUOVO accertamento distinto.
  int get nextAccertamentoNumber =>
      accertamentoNumbers.isEmpty ? 1 : accertamentoNumbers.last + 1;

  /// Numeri selezionabili quando si aggiunge un voto: gli accertamenti
  /// esistenti ancora da recuperare (insufficienti, tentativi non esauriti)
  /// più il prossimo numero libero per iniziarne uno nuovo. Un accertamento
  /// già superato o con tentativi esauriti non va più proposto. Il prossimo
  /// numero libero non viene proposto se supera assessmentCount: il modulo
  /// non prevede un altro accertamento distinto (resta solo l'esame).
  List<int> get addableAccertamentoNumbers {
    final result = <int>[];
    for (final n in accertamentoNumbers) {
      final list = byAssessment[(AssessmentType.accertamento, n)]!;
      final last = list.last;
      if (!last.isPassing && list.length < AssessmentType.accertamento.maxAttempts) {
        result.add(n);
      }
    }
    if (nextAccertamentoNumber <= assessmentCount) {
      result.add(nextAccertamentoNumber);
    }
    return result;
  }

  /// Solo l'ultimo tentativo per ciascun accertamento/esame distinto: sono
  /// questi — non lo storico completo — a determinare se il modulo è
  /// ancora "da recuperare", e quanti accertamenti/esame conta il modulo.
  List<Grade> get latestAttempts =>
      byAssessment.values.map((l) => l.last).toList();

  double get weightedAverage {
    final valid = latestAttempts.where((g) => g.isPassing).toList();
    if (valid.isEmpty) return 0;
    double totalWeightedScore = 0;
    int totalWeight = 0;
    for (final g in valid) {
      final w = g.assessmentType.weight;
      totalWeightedScore += effectiveScore(g) * w;
      totalWeight += w;
    }
    return totalWeight == 0 ? 0 : totalWeightedScore / totalWeight;
  }

  bool get hasFailing => latestAttempts.any((g) => !g.isPassing);

  bool get isPassing => weightedAverage >= 22.5;
  bool get hasGrades => grades.isNotEmpty;

  /// Numero di tentativo (1-based) di [g] tra i voti dello stesso
  /// accertamento/esame distinto (stesso tipo E stesso numero).
  int attemptNumber(Grade g) {
    final list = byAssessment[(g.assessmentType, g.accertamentoNumber)] ?? const [];
    final idx = list.indexWhere((x) => x.id == g.id);
    return idx < 0 ? 1 : idx + 1;
  }

  /// true se [g] è un tentativo di recupero (non il primo per quel singolo
  /// accertamento/esame) con punteggio superiore a 25: per regola del corso
  /// un punteggio pieno ottenuto solo al recupero non vale per intero in
  /// media/graduatoria, resta tappato alla soglia di sufficienza (22,5).
  bool isCappedRecovery(Grade g) => attemptNumber(g) > 1 && g.score > 25;

  /// Punteggio da usare in media di modulo e graduatoria del corso: il voto
  /// resta salvato come inserito (vedi [Grade.score]), ma se è un recupero
  /// tappato (vedi [isCappedRecovery]) conta come 22,5, non per intero.
  double effectiveScore(Grade g) => isCappedRecovery(g) ? 22.5 : g.score;

  /// Nota da mostrare accanto al voto quando [isCappedRecovery] è vero, per
  /// chiarire che il punteggio registrato non è quello usato in media/
  /// graduatoria.
  String? recoveryCapNote(Grade g) =>
      isCappedRecovery(g) ? 'conta 22,5 (recupero)' : null;

  int attemptsCount(Grade g) =>
      byAssessment[(g.assessmentType, g.accertamentoNumber)]?.length ?? 1;

  /// true se [g] non è l'ultimo tentativo del suo accertamento/esame
  /// distinto (superato da un tentativo successivo sullo stesso numero).
  bool isSuperseded(Grade g) {
    final list = byAssessment[(g.assessmentType, g.accertamentoNumber)];
    return list != null && list.isNotEmpty && list.last.id != g.id;
  }

  /// true se [g] è l'ultimo tentativo del suo accertamento/esame distinto,
  /// è insufficiente e ha già raggiunto il numero massimo di tentativi
  /// consentiti: non è più possibile un ulteriore tentativo.
  bool isExhausted(Grade g) =>
      !isSuperseded(g) && !g.isPassing && attemptsCount(g) >= g.assessmentType.maxAttempts;

  /// Etichetta da mostrare al posto del generico "Accertamento"/"Esame":
  /// se il modulo ha più di un accertamento distinto, specifica quale
  /// ("Accertamento 2"), per non confondere tentativi su accertamenti
  /// diversi. Per l'esame (uno solo per modulo) resta l'etichetta semplice.
  String chipLabel(Grade g) {
    if (g.assessmentType == AssessmentType.esame) return AssessmentType.esame.label;
    return accertamentoNumbers.length > 1
        ? 'Accertamento ${g.accertamentoNumber}'
        : AssessmentType.accertamento.label;
  }

  /// Etichetta "Tentativo N di M" da mostrare accanto al voto. Null se è
  /// l'unico tentativo per quell'accertamento/esame distinto (nessuna
  /// ambiguità da chiarire).
  String? attemptLabel(Grade g) {
    final count = attemptsCount(g);
    if (count <= 1) return null;
    return 'Tentativo ${attemptNumber(g)} di $count';
  }

  /// Nota di stato da mostrare sotto un voto negativo. Null se il voto è
  /// positivo. "da recuperare" solo se è l'ultimo tentativo e ne restano
  /// ancora; "tentativi esauriti" se ha raggiunto il massimo consentito;
  /// un voto negativo superato da un tentativo successivo è "superato".
  String? recoveryNote(Grade g) {
    if (g.isPassing) return null;
    if (isSuperseded(g)) return 'tentativo superato';
    if (isExhausted(g)) return 'tentativi esauriti';
    return 'da recuperare';
  }
}
