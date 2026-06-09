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

  Future<int> deleteUnconfirmedLessons(String courseId) async {
    final all = _db.schedules.toList();
    final toKeep = all.where((s) =>
        s['course_id'] != courseId || s['confirmed'] == true).toList();
    final deleted = all.length - toKeep.length;
    if (deleted > 0) await _db.saveSchedules(toKeep);
    return deleted;
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
            currentDate = _nextWorkday(_safeNext(currentDate));
          }
          lessons.add(_lessonMap(courseId, module.number, sub.code, sub.name, 'teoria', currentDate, slot.slot, now));
          if (slotIdx == slotList.length - 1) {
            currentDate = _nextWorkday(_safeNext(currentDate));
          }
        }
        currentDate = _nextWorkday(currentDate);
        for (var i = 0; i < sub.practicalHours; i++) {
          final slotList = slots.slotsForWeekday(currentDate.weekday);
          final slotIdx = i % slotList.length;
          final slot = slotList[slotIdx];
          if (slotIdx == 0 && i > 0) {
            currentDate = _nextWorkday(_safeNext(currentDate));
          }
          lessons.add(_lessonMap(courseId, module.number, sub.code, sub.name, 'pratica', currentDate, slot.slot, now));
          if (slotIdx == slotList.length - 1) {
            currentDate = _nextWorkday(_safeNext(currentDate));
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

  // ── Date helpers (DST-safe: no Duration arithmetic) ─────────────────────────

  DateTime _safeNext(DateTime d) => DateTime(d.year, d.month, d.day + 1);

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime _nextWorkday(DateTime d, [List<String> excluded = const []]) {
    var next = DateTime(d.year, d.month, d.day);
    while (next.weekday == DateTime.saturday ||
        next.weekday == DateTime.sunday ||
        excluded.contains(_fmt(next))) {
      next = DateTime(next.year, next.month, next.day + 1);
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

  /// Auto-generate remaining unconfirmed lessons mixing 2–3-hour blocks from
  /// different modules each day. Removes old auto-generated lessons; keeps
  /// confirmed lessons and any manually-placed unconfirmed lessons.
  Future<void> generateRemainingSchedule({
    required String courseId,
    required CourseTypeInfo typeInfo,
    required bool hasAttendeesInRecovery,
    List<String> excludedDates = const [],
  }) async {
    final allLessons = getLessonsForCourse(courseId);

    // Count confirmed hours per (submoduleCode, type) AND per module total.
    // Normalize codes to match reference: '7.3P' → '7.3' (P-suffix practical),
    // '12.7.1' → '12.7' (triple-component codes collapsed to two components).
    final doneT = <String, int>{};
    final doneP = <String, int>{};
    final doneTotalByModule = <int, int>{};
    for (final l in allLessons.where((l) => l.confirmed && l.timeSlot > 0)) {
      String c = l.submoduleCode;
      if (c.endsWith('P')) c = c.substring(0, c.length - 1);
      final parts = c.split('.');
      if (parts.length >= 3) c = '${parts[0]}.${parts[1]}';
      if (l.isTheory) doneT[c] = (doneT[c] ?? 0) + 1;
      else            doneP[c] = (doneP[c] ?? 0) + 1;
      doneTotalByModule[l.moduleNumber] = (doneTotalByModule[l.moduleNumber] ?? 0) + 1;
    }

    // Build 2–3-hour blocks per module, then interleave round-robin for mixing
    final moduleBlocks = <int, List<List<(String, int, String)>>>{};
    for (final m in typeInfo.modules) {
      // Skip entire module if confirmed hours already meet planned total
      final moduleDone = doneTotalByModule[m.number] ?? 0;
      if (moduleDone >= m.totalHours) continue;
      // Remaining module capacity to distribute across submodules
      var moduleCapacity = m.totalHours - moduleDone;

      for (final sub in m.submodules) {
        if (moduleCapacity <= 0) break;
        final subDone = (doneT[sub.code] ?? 0) + (doneP[sub.code] ?? 0);
        final subPlanned = sub.theoryHours + sub.practicalHours;
        final subRemaining = (subPlanned - subDone).clamp(0, moduleCapacity);
        final remT = (sub.theoryHours    - (doneT[sub.code] ?? 0)).clamp(0, subRemaining);
        final remP = (sub.practicalHours - (doneP[sub.code] ?? 0)).clamp(0, (subRemaining - remT).clamp(0, 9999));
        moduleCapacity -= remT + remP;

        void addBlocks(int rem, String t) {
          var r = rem;
          while (r > 0) {
            // prefer 3-hr blocks; avoid leaving a lone 1-hr tail (use 2+2 for 4)
            final size = (r == 1) ? 1 : (r == 4 ? 2 : (r >= 3 ? 3 : 2));
            moduleBlocks.putIfAbsent(m.number, () => [])
                .add(List.generate(size, (_) => (sub.code, m.number, t)));
            r -= size;
          }
        }

        if (remT > 0) addBlocks(remT, 'teoria');
        if (remP > 0) addBlocks(remP, 'pratica');
      }
    }

    // Interleave: one block per module per pass
    final queue = <(String, int, String)>[];
    final modNums = moduleBlocks.keys.toList()..sort();
    final modIdx  = {for (final k in modNums) k: 0};
    bool anyLeft = true;
    while (anyLeft) {
      anyLeft = false;
      for (final mod in modNums) {
        final blocks = moduleBlocks[mod]!;
        final bi = modIdx[mod]!;
        if (bi < blocks.length) {
          queue.addAll(blocks[bi]);
          modIdx[mod] = bi + 1;
          anyLeft = true;
        }
      }
    }

    // Remove old auto-generated unconfirmed lessons; keep confirmed + manual
    final rawSchedules = _db.schedules.toList();
    final cleaned = rawSchedules.where((s) {
      if (s['course_id'] != courseId) return true;
      if (s['confirmed'] == true) return true;
      return !(s['auto_generated'] as bool? ?? false);
    }).toList();

    if (queue.isEmpty) {
      await _db.saveSchedules(cleaned);
      return;
    }

    // Start: day after last confirmed lesson or today, whichever is later
    final confirmedDates = allLessons
        .where((l) => l.confirmed)
        .map((l) => l.date)
        .toList()
      ..sort();
    final lastDone = confirmedDates.isNotEmpty ? confirmedDates.last : DateTime.now();
    final today   = DateTime.now();
    final seed    = lastDone.isAfter(today) ? lastDone : today;
    var date      = _nextWorkday(_safeNext(seed), excludedDates);

    final subNames = <String, String>{
      for (final m in typeInfo.modules)
        for (final s in m.submodules) s.code: s.name,
    };

    final newLessons = <Map<String, dynamic>>[];
    final now = DateTime.now().toIso8601String();
    var counter = 0;
    var qi = 0;

    while (qi < queue.length) {
      final weekday = date.weekday;
      final slots   = typeInfo.schedule.slotsForWeekday(weekday);
      final dateStr = _fmt(date);

      // Recovery slot 0 — Mon–Thu only (weekday 1..4)
      if (hasAttendeesInRecovery && weekday <= DateTime.thursday) {
        newLessons.add({
          'id': 'gen_rec_${counter++}',
          'course_id': courseId,
          'module_number': 0,
          'submodule_code': 'RECUPERO',
          'topic': 'Ora di recupero',
          'type': 'recupero',
          'date': dateStr,
          'time_slot': 0,
          'instructor_id': null,
          'confirmed': false,
          'auto_generated': true,
          'created_at': now,
          'updated_at': now,
        });
      }

      for (final slot in slots) {
        if (qi >= queue.length) break;
        final (code, modNum, lessonType) = queue[qi++];
        newLessons.add({
          'id': 'gen_${counter++}',
          'course_id': courseId,
          'module_number': modNum,
          'submodule_code': code,
          'topic': subNames[code] ?? code,
          'type': lessonType,
          'date': dateStr,
          'time_slot': slot.slot,
          'instructor_id': null,
          'confirmed': false,
          'auto_generated': true,
          'created_at': now,
          'updated_at': now,
        });
      }

      date = _nextWorkday(_safeNext(date), excludedDates);
    }

    cleaned.addAll(newLessons);
    await _db.saveSchedules(cleaned);
  }
}
