enum LessonType { teoria, pratica }

extension LessonTypeExt on LessonType {
  String get value => this == LessonType.teoria ? 'teoria' : 'pratica';
  String get label => this == LessonType.teoria ? 'Teoria' : 'Pratica';

  static LessonType fromString(String s) =>
      s == 'pratica' ? LessonType.pratica : LessonType.teoria;
}

class ScheduledLesson {
  final String id;
  final String courseId;
  final int moduleNumber;
  final String submoduleCode;
  final String topic;
  final String type;
  final DateTime date;
  final int timeSlot;
  final String? instructorId;
  final bool confirmed;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ScheduledLesson({
    required this.id,
    required this.courseId,
    required this.moduleNumber,
    required this.submoduleCode,
    required this.topic,
    required this.type,
    required this.date,
    required this.timeSlot,
    this.instructorId,
    this.confirmed = false,
    required this.createdAt,
    required this.updatedAt,
  });

  LessonType get lessonType => LessonTypeExt.fromString(type);
  bool get isTheory => type != 'pratica';

  factory ScheduledLesson.fromJson(Map<String, dynamic> j) => ScheduledLesson(
    id: j['id'] as String,
    courseId: j['course_id'] as String,
    moduleNumber: j['module_number'] as int,
    submoduleCode: j['submodule_code'] as String? ?? '',
    topic: j['topic'] as String? ?? '',
    type: j['type'] as String? ?? 'teoria',
    date: DateTime.parse(j['date'] as String),
    timeSlot: j['time_slot'] as int? ?? 1,
    instructorId: j['instructor_id'] as String?,
    confirmed: j['confirmed'] as bool? ?? false,
    createdAt: DateTime.parse(
      j['created_at'] as String? ?? DateTime.now().toIso8601String(),
    ),
    updatedAt: DateTime.parse(
      j['updated_at'] as String? ?? DateTime.now().toIso8601String(),
    ),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'course_id': courseId,
    'module_number': moduleNumber,
    'submodule_code': submoduleCode,
    'topic': topic,
    'type': type,
    'date': date.toIso8601String().split('T').first,
    'time_slot': timeSlot,
    'instructor_id': instructorId,
    'confirmed': confirmed,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  ScheduledLesson copyWith({
    int? moduleNumber,
    String? submoduleCode,
    String? topic,
    String? type,
    DateTime? date,
    int? timeSlot,
    Object? instructorId = _s,
    bool? confirmed,
  }) => ScheduledLesson(
    id: id,
    courseId: courseId,
    moduleNumber: moduleNumber ?? this.moduleNumber,
    submoduleCode: submoduleCode ?? this.submoduleCode,
    topic: topic ?? this.topic,
    type: type ?? this.type,
    date: date ?? this.date,
    timeSlot: timeSlot ?? this.timeSlot,
    instructorId: identical(instructorId, _s) ? this.instructorId : instructorId as String?,
    confirmed: confirmed ?? this.confirmed,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  static const Object _s = Object();
}

class AttendanceRecord {
  final String id;
  final String scheduleId;
  final String courseId;
  final String attendeeId;
  final bool present;
  final String? justification;
  final int? recoveredModule;
  final String? confirmedBy;
  final DateTime? confirmedAt;

  const AttendanceRecord({
    required this.id,
    required this.scheduleId,
    required this.courseId,
    required this.attendeeId,
    required this.present,
    this.justification,
    this.recoveredModule,
    this.confirmedBy,
    this.confirmedAt,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
    id: j['id'] as String,
    scheduleId: j['schedule_id'] as String,
    courseId: j['course_id'] as String,
    attendeeId: j['attendee_id'] as String,
    present: j['present'] as bool? ?? false,
    justification: j['justification'] as String?,
    recoveredModule: j['recovered_module'] as int?,
    confirmedBy: j['confirmed_by'] as String?,
    confirmedAt: j['confirmed_at'] != null
        ? DateTime.tryParse(j['confirmed_at'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'schedule_id': scheduleId,
    'course_id': courseId,
    'attendee_id': attendeeId,
    'present': present,
    'justification': justification,
    'recovered_module': recoveredModule,
    'confirmed_by': confirmedBy,
    'confirmed_at': confirmedAt?.toIso8601String(),
  };
}
