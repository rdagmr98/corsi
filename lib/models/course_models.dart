enum CourseStatus { planning, active, completed, archived }

extension CourseStatusExt on CourseStatus {
  String get value => switch (this) {
    CourseStatus.planning => 'planning',
    CourseStatus.active => 'active',
    CourseStatus.completed => 'completed',
    CourseStatus.archived => 'archived',
  };

  String get label => switch (this) {
    CourseStatus.planning => 'Pianificazione',
    CourseStatus.active => 'Attivo',
    CourseStatus.completed => 'Completato',
    CourseStatus.archived => 'Archiviato',
  };

  static CourseStatus fromString(String s) => switch (s) {
    'active' => CourseStatus.active,
    'completed' => CourseStatus.completed,
    'archived' => CourseStatus.archived,
    _ => CourseStatus.planning,
  };
}

class Course {
  final String id;
  final String courseTypeId;
  final String? extensionTypeId; // optional mil extension (e.g. 'b1mil' for a b1 course)
  final String title;
  final DateTime? startDate;
  final DateTime? endDate;
  final String status;
  final List<String> directorIds;
  final List<String> attendeeIds;
  final List<String> instructorIds;
  final List<String> excludedDates; // YYYY-MM-DD days excluded from auto-schedule
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Course({
    required this.id,
    required this.courseTypeId,
    this.extensionTypeId,
    required this.title,
    this.startDate,
    this.endDate,
    required this.status,
    this.directorIds = const [],
    this.attendeeIds = const [],
    this.instructorIds = const [],
    this.excludedDates = const [],
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  CourseStatus get courseStatus => CourseStatusExt.fromString(status);
  bool get isActive => status == 'active';

  factory Course.fromJson(Map<String, dynamic> j) => Course(
    id: j['id'] as String,
    courseTypeId: j['course_type_id'] as String,
    extensionTypeId: j['extension_type_id'] as String?,
    title: j['title'] as String,
    startDate: j['start_date'] != null
        ? DateTime.tryParse(j['start_date'] as String)
        : null,
    endDate: j['end_date'] != null
        ? DateTime.tryParse(j['end_date'] as String)
        : null,
    status: j['status'] as String? ?? 'planning',
    directorIds: List<String>.from(j['director_ids'] as List? ?? []),
    attendeeIds: List<String>.from(j['attendee_ids'] as List? ?? []),
    instructorIds: List<String>.from(j['instructor_ids'] as List? ?? []),
    excludedDates: List<String>.from(j['excluded_dates'] as List? ?? []),
    createdBy: j['created_by'] as String? ?? '',
    createdAt: DateTime.parse(
      j['created_at'] as String? ?? DateTime.now().toIso8601String(),
    ),
    updatedAt: DateTime.parse(
      j['updated_at'] as String? ?? DateTime.now().toIso8601String(),
    ),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'course_type_id': courseTypeId,
    if (extensionTypeId != null) 'extension_type_id': extensionTypeId,
    'title': title,
    'start_date': startDate?.toIso8601String().split('T').first,
    'end_date': endDate?.toIso8601String().split('T').first,
    'status': status,
    'director_ids': directorIds,
    'attendee_ids': attendeeIds,
    'instructor_ids': instructorIds,
    'excluded_dates': excludedDates,
    'created_by': createdBy,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  Course copyWith({
    String? courseTypeId,
    Object? extensionTypeId = _s,
    String? title,
    Object? startDate = _s,
    Object? endDate = _s,
    String? status,
    List<String>? directorIds,
    List<String>? attendeeIds,
    List<String>? instructorIds,
    List<String>? excludedDates,
  }) => Course(
    id: id,
    courseTypeId: courseTypeId ?? this.courseTypeId,
    extensionTypeId: identical(extensionTypeId, _s) ? this.extensionTypeId : extensionTypeId as String?,
    title: title ?? this.title,
    startDate: identical(startDate, _s) ? this.startDate : startDate as DateTime?,
    endDate: identical(endDate, _s) ? this.endDate : endDate as DateTime?,
    status: status ?? this.status,
    directorIds: directorIds ?? this.directorIds,
    attendeeIds: attendeeIds ?? this.attendeeIds,
    instructorIds: instructorIds ?? this.instructorIds,
    excludedDates: excludedDates ?? this.excludedDates,
    createdBy: createdBy,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  static const Object _s = Object();
}
