import '../models/reference_models.dart';
import '../models/schedule_models.dart';
import 'gh_db_service.dart';

class ScheduleService {
  final _db = GhDbService();

  List<ScheduledLesson> getAllLessons() =>
      _db.schedules.map(ScheduledLesson.fromJson).toList();

  List<ScheduledLesson> getLessonsForCourse(String courseId) =>
      getAllLessons().where((l) => l.courseId == courseId).toList()
        ..sort((a, b) {
          final dc = a.date.compareTo(b.date);
          return dc != 0 ? dc : a.timeSlot.compareTo(b.timeSlot);
        });

  List<ScheduledLesson> getLessonsForDate(String courseId, DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return getLessonsForCourse(courseId)
        .where((l) {
          final ld = DateTime(l.date.year, l.date.month, l.date.day);
          return ld == d;
        })
        .toList()
      ..sort((a, b) => a.timeSlot.compareTo(b.timeSlot));
  }

  List<ScheduledLesson> getLessonsForInstructor(String instructorId) =>
      getAllLessons().where((l) => l.instructorId == instructorId).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  /// All lessons relevant for an instructor: assigned lessons + unconfirmed
  /// lessons where they are AMC-authorized and no instructor is assigned yet.
  List<ScheduledLesson> getAllRelevantLessonsForInstructor(String instructorId) {
    final amc = _db.amcData;
    final theoryGrid = (amc['theoryGrid'] as Map? ?? {})
        .map((k, v) => MapEntry(k as String, List<String>.from(v as List)));
    final practiceGrid = (amc['practiceGrid'] as Map? ?? {})
        .map((k, v) => MapEntry(k as String, List<String>.from(v as List)));

    bool isAmcAuthorized(ScheduledLesson l) {
      final grid = l.isTheory ? theoryGrid : practiceGrid;
      return grid[l.submoduleCode]?.contains(instructorId) ?? false;
    }

    return getAllLessons().where((l) {
      if (l.instructorId == instructorId) return true;
      if (l.instructorId == null && !l.confirmed && isAmcAuthorized(l)) return true;
      return false;
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<ScheduledLesson> getLessonsForInstructorToday(String instructorId) {
    final today = DateTime.now();
    final d = DateTime(today.year, today.month, today.day);
    return getLessonsForInstructor(instructorId).where((l) {
      final ld = DateTime(l.date.year, l.date.month, l.date.day);
      return ld == d;
    }).toList()
      ..sort((a, b) => a.timeSlot.compareTo(b.timeSlot));
  }

  /// Lessons today that are either assigned to [instructorId] OR are unconfirmed
  /// and the instructor is AMC-authorized for that submodule.
  List<ScheduledLesson> getLessonsRelevantForInstructorToday(String instructorId) {
    final today = DateTime.now();
    final d = DateTime(today.year, today.month, today.day);
    final amc = _db.amcData;
    final theoryGrid = (amc['theoryGrid'] as Map? ?? {})
        .map((k, v) => MapEntry(k as String, List<String>.from(v as List)));
    final practiceGrid = (amc['practiceGrid'] as Map? ?? {})
        .map((k, v) => MapEntry(k as String, List<String>.from(v as List)));

    bool isAmcAuthorized(ScheduledLesson l) {
      final grid = l.isTheory ? theoryGrid : practiceGrid;
      return grid[l.submoduleCode]?.contains(instructorId) ?? false;
    }

    return getAllLessons().where((l) {
      final ld = DateTime(l.date.year, l.date.month, l.date.day);
      if (ld != d) return false;
      if (l.instructorId == instructorId) return true;
      if (l.instructorId == null && !l.confirmed && isAmcAuthorized(l)) return true;
      return false;
    }).toList()
      ..sort((a, b) => a.timeSlot.compareTo(b.timeSlot));
  }

  List<ScheduledLesson> getLessonsForWeek(String courseId, DateTime weekStart) {
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = start.add(const Duration(days: 7));
    return getLessonsForCourse(courseId)
        .where((l) => !l.date.isBefore(start) && l.date.isBefore(end))
        .toList();
  }

  Future<ScheduledLesson> addLesson({
    required String courseId,
    required int moduleNumber,
    required String submoduleCode,
    required String topic,
    required String type,
    required DateTime date,
    required int timeSlot,
    String? instructorId,
  }) async {
    final schedules = _db.schedules.toList();
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toRadixString(16);
    final newLesson = {
      'id': id,
      'course_id': courseId,
      'module_number': moduleNumber,
      'submodule_code': submoduleCode,
      'topic': topic,
      'type': type,
      'date': date.toIso8601String().split('T').first,
      'time_slot': timeSlot,
      'instructor_id': instructorId,
      'confirmed': false,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    schedules.add(newLesson);
    await _db.saveSchedules(schedules);
    return ScheduledLesson.fromJson(newLesson);
  }

  Future<void> updateLesson(ScheduledLesson updated) async {
    final schedules = _db.schedules.toList();
    final idx = schedules.indexWhere((s) => s['id'] == updated.id);
    if (idx < 0) return;
    schedules[idx] = {
      ...schedules[idx],
      ...updated.toJson(),
      'updated_at': DateTime.now().toIso8601String(),
    };
    await _db.saveSchedules(schedules);
  }

  Future<void> confirmLesson(String lessonId, String confirmedBy) async {
    final schedules = _db.schedules.toList();
    final idx = schedules.indexWhere((s) => s['id'] == lessonId);
    if (idx < 0) return;
    schedules[idx] = {
      ...schedules[idx],
      'confirmed': true,
      'confirmed_by': confirmedBy,
      'updated_at': DateTime.now().toIso8601String(),
    };
    await _db.saveSchedules(schedules);
  }

  Future<void> deleteLesson(String lessonId) async {
    final schedules = _db.schedules.where((s) => s['id'] != lessonId).toList();
    await _db.saveSchedules(schedules);
  }

  Future<void> deleteLessonsForCourse(String courseId) async {
    final schedules = _db.schedules.where((s) => s['course_id'] != courseId).toList();
    await _db.saveSchedules(schedules);
  }

  /// Auto-generate a weekly schedule for a course based on the module plan.
  /// Distributes theory then practical hours across working days starting from [startDate].
  Future<void> generateSchedule({
    required String courseId,
    required String courseTypeId,
    required DateTime startDate,
    required CourseTypeInfo typeInfo,
  }) async {
    final existing = getLessonsForCourse(courseId);
    if (existing.isNotEmpty) return;

    final lessons = <Map<String, dynamic>>[];
    final now = DateTime.now().toIso8601String();
    var currentDate = _nextWorkday(startDate);

    final slots = typeInfo.schedule;

    for (final module in typeInfo.modules) {
      for (final sub in module.submodules) {
        for (var i = 0; i < sub.theoryHours; i++) {
          final slotList = slots.slotsForWeekday(currentDate.weekday);
          final slotIdx = i % slotList.length;
          final slot = slotList[slotIdx];
          if (slotIdx == 0 && i > 0) {
            currentDate = _nextWorkday(currentDate.add(const Duration(days: 1)));
          }
          lessons.add(_lessonMap(courseId, module.number, sub.code, sub.name, 'teoria', currentDate, slot.slot, now));
          if (slotIdx == slotList.length - 1) {
            currentDate = _nextWorkday(currentDate.add(const Duration(days: 1)));
          }
        }
        currentDate = _nextWorkday(currentDate);
        for (var i = 0; i < sub.practicalHours; i++) {
          final slotList = slots.slotsForWeekday(currentDate.weekday);
          final slotIdx = i % slotList.length;
          final slot = slotList[slotIdx];
          if (slotIdx == 0 && i > 0) {
            currentDate = _nextWorkday(currentDate.add(const Duration(days: 1)));
          }
          lessons.add(_lessonMap(courseId, module.number, sub.code, sub.name, 'pratica', currentDate, slot.slot, now));
          if (slotIdx == slotList.length - 1) {
            currentDate = _nextWorkday(currentDate.add(const Duration(days: 1)));
          }
        }
        currentDate = _nextWorkday(currentDate);
      }
    }

    final existing2 = _db.schedules.toList();
    final newLessons = lessons.map((l) {
      final id = DateTime.now().microsecondsSinceEpoch.toRadixString(16) +
          lessons.indexOf(l).toString();
      return {'id': id, ...l};
    }).toList();
    existing2.addAll(newLessons);
    await _db.saveSchedules(existing2);
  }

  Map<String, dynamic> _lessonMap(
    String courseId, int moduleNum, String subCode, String topic, String type,
    DateTime date, int slot, String now,
  ) => {
    'course_id': courseId,
    'module_number': moduleNum,
    'submodule_code': subCode,
    'topic': topic,
    'type': type,
    'date': date.toIso8601String().split('T').first,
    'time_slot': slot,
    'instructor_id': null,
    'confirmed': false,
    'created_at': now,
    'updated_at': now,
  };

  DateTime _nextWorkday(DateTime d) {
    var next = d;
    while (next.weekday == DateTime.saturday || next.weekday == DateTime.sunday) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  Map<int, double> computeModuleHoursTaught(String courseId) {
    final lessons = getLessonsForCourse(courseId).where((l) => l.confirmed);
    final map = <int, double>{};
    for (final l in lessons) {
      map[l.moduleNumber] = (map[l.moduleNumber] ?? 0) + 1;
    }
    return map;
  }

  /// Generate unconfirmed lessons for remaining hours not yet taught.
  /// Skips submodules already fully covered by confirmed lessons.
  /// Adds a 'recupero' lesson at slot 0 on each day if [hasAttendeesInRecovery] is true.
  Future<void> generateRemainingSchedule({
    required String courseId,
    required CourseTypeInfo typeInfo,
    required bool hasAttendeesInRecovery,
  }) async {
    final allLessons = getLessonsForCourse(courseId);
    // Count confirmed hours per (submoduleCode, type)
    final doneT = <String, int>{};
    final doneP = <String, int>{};
    for (final l in allLessons.where((l) => l.confirmed)) {
      if (l.isTheory) {
        doneT[l.submoduleCode] = (doneT[l.submoduleCode] ?? 0) + 1;
      } else {
        doneP[l.submoduleCode] = (doneP[l.submoduleCode] ?? 0) + 1;
      }
    }

    // Build queue of (code, module, type, hours_remaining)
    final queue = <(String, int, String)>[];
    for (final m in typeInfo.modules) {
      for (final sub in m.submodules) {
        final remT = sub.theoryHours - (doneT[sub.code] ?? 0);
        final remP = sub.practicalHours - (doneP[sub.code] ?? 0);
        for (var i = 0; i < remT; i++) { queue.add((sub.code, m.number, 'teoria')); }
        for (var i = 0; i < remP; i++) { queue.add((sub.code, m.number, 'pratica')); }
      }
    }

    if (queue.isEmpty) return;

    // Start date: day after last confirmed lesson (or tomorrow, whichever is later)
    DateTime startDate;
    final confirmedDates = allLessons
        .where((l) => l.confirmed)
        .map((l) => l.date)
        .toList()
      ..sort();
    final lastDone = confirmedDates.isNotEmpty ? confirmedDates.last : DateTime.now();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    startDate = lastDone.isAfter(tomorrow) ? lastDone : tomorrow;
    startDate = _nextWorkday(DateTime(startDate.year, startDate.month, startDate.day));

    // Remove any existing unconfirmed lessons (regenerate)
    final existing = _db.schedules.toList();
    final cleaned = existing.where((s) {
      if (s['course_id'] != courseId) return true;
      return s['confirmed'] == true;
    }).toList();

    final newLessons = <Map<String, dynamic>>[];
    final now = DateTime.now().toIso8601String();
    var qi = 0;
    var date = startDate;

    while (qi < queue.length) {
      final slots = typeInfo.schedule.slotsForWeekday(date.weekday);
      final dateStr = date.toIso8601String().split('T').first;

      // Recovery slot (slot 0) if needed
      if (hasAttendeesInRecovery) {
        final id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}r$qi';
        newLessons.add({
          'id': id,
          'course_id': courseId,
          'module_number': 0,
          'submodule_code': 'RECUPERO',
          'topic': 'Ora di recupero',
          'type': 'recupero',
          'date': dateStr,
          'time_slot': 0,
          'instructor_id': null,
          'confirmed': false,
          'created_at': now,
          'updated_at': now,
        });
      }

      for (final slot in slots) {
        if (qi >= queue.length) break;
        final (code, modNum, type) = queue[qi++];
        final id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}f$qi';
        newLessons.add({
          'id': id,
          'course_id': courseId,
          'module_number': modNum,
          'submodule_code': code,
          'topic': code,
          'type': type,
          'date': dateStr,
          'time_slot': slot.slot,
          'instructor_id': null,
          'confirmed': false,
          'created_at': now,
          'updated_at': now,
        });
      }

      date = _nextWorkday(date.add(const Duration(days: 1)));
    }

    cleaned.addAll(newLessons);
    await _db.saveSchedules(cleaned);
  }
}
