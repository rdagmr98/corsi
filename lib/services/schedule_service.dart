import 'dart:math';
import '../models/reference_models.dart';
import '../models/schedule_models.dart';
import 'gh_db_service.dart';

class ScheduleService {
  final _db = GhDbService();

  /// Normalizza un codice sottomodulo per confrontarlo col programma ufficiale:
  /// suffisso pratica rimosso ('7.3P', '12.2p' → '7.3', '12.2'),
  /// codici a 3 componenti collassati ('12.7.1' → '12.7').
  static String normalizeSubCode(String code) {
    var c = code.trim();
    if (c.endsWith('P') || c.endsWith('p')) c = c.substring(0, c.length - 1);
    final parts = c.split('.');
    if (parts.length >= 3) c = '${parts[0]}.${parts[1]}';
    return c;
  }

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
      return grid[normalizeSubCode(l.submoduleCode)]?.contains(instructorId) ?? false;
    }

    return getAllLessons().where((l) {
      if (l.instructorId == instructorId) return true;
      if (l.instructorId == null && !l.confirmed && isAmcAuthorized(l)) return true;
      return false;
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// IDs degli istruttori abilitati AMC per [submoduleCode] e [type]
  /// ('teoria' → theoryGrid, altrimenti practiceGrid). Confronto su codici
  /// normalizzati così le varianti 'P'/'p'/3-componenti trovano la riga giusta.
  Set<String> qualifiedInstructorIds(String submoduleCode, String type) {
    final grid = (_db.amcData[type == 'teoria' ? 'theoryGrid' : 'practiceGrid']
        as Map? ?? {});
    final target = normalizeSubCode(submoduleCode);
    final ids = <String>{};
    grid.forEach((k, v) {
      if (normalizeSubCode(k as String) == target) {
        ids.addAll(List<String>.from(v as List));
      }
    });
    return ids;
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
      return grid[normalizeSubCode(l.submoduleCode)]?.contains(instructorId) ?? false;
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
    dynamic taskId,
  }) async {
    final schedules = _db.schedules.toList();
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toRadixString(16);
    final newLesson = <String, dynamic>{
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
      if (taskId != null) 'task_id': taskId,
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

  Future<void> confirmLesson(String lessonId, String confirmedBy) =>
      confirmLessons([lessonId], confirmedBy);

  /// Conferma più lezioni in un solo salvataggio (validazione giornata intera).
  Future<void> confirmLessons(List<String> lessonIds, String confirmedBy) async {
    if (lessonIds.isEmpty) return;
    final ids = lessonIds.toSet();
    final nowIso = DateTime.now().toIso8601String();
    var changed = false;
    final schedules = _db.schedules.map((s) {
      if (!ids.contains(s['id'])) return s;
      changed = true;
      return {
        ...s,
        'confirmed': true,
        'confirmed_by': confirmedBy,
        'updated_at': nowIso,
      };
    }).toList();
    if (changed) await _db.saveSchedules(schedules);
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

  Future<int> deleteUnconfirmedLessonsFrom(String courseId, DateTime fromDate) async {
    final all = _db.schedules.toList();
    final fromStr = fromDate.toIso8601String().split('T').first;
    final toKeep = all.where((s) {
      if (s['course_id'] != courseId) return true;
      if (s['confirmed'] == true) return true;
      final dateStr = (s['date'] as String?)?.split('T').first ?? '';
      return dateStr.compareTo(fromStr) < 0;
    }).toList();
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

  // ── Note su slot ─────────────────────────────────────────────────────────────

  List<SlotNote> getNotesForCourse(String courseId) =>
      _db.slotNotes
          .where((n) => n['course_id'] == courseId)
          .map(SlotNote.fromJson)
          .toList();

  List<SlotNote> getNotesForWeek(String courseId, DateTime weekStart) {
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = start.add(const Duration(days: 7));
    return getNotesForCourse(courseId)
        .where((n) => !n.date.isBefore(start) && n.date.isBefore(end))
        .toList();
  }

  Future<SlotNote> addNote({
    required String courseId,
    required DateTime date,
    required int timeSlot,
    required String text,
  }) async {
    final notes = _db.slotNotes.toList();
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final newNote = {
      'id': id,
      'course_id': courseId,
      'date': date.toIso8601String().split('T').first,
      'time_slot': timeSlot,
      'text': text,
    };
    notes.removeWhere((n) =>
        n['course_id'] == courseId &&
        n['date'] == newNote['date'] &&
        n['time_slot'] == timeSlot);
    notes.add(newNote);
    await _db.saveSlotNotes(notes);
    return SlotNote.fromJson(newNote);
  }

  Future<void> deleteNote(String noteId) async {
    final notes = _db.slotNotes.where((n) => n['id'] != noteId).toList();
    await _db.saveSlotNotes(notes);
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

    // Le auto-generate non confermate verranno rimosse e rigenerate: contano
    // come ore già coperte solo le lezioni che restano (confermate + manuali).
    final rawSchedules = _db.schedules.toList();
    final keptIds = <String>{
      for (final s in rawSchedules)
        if (s['course_id'] == courseId &&
            (s['confirmed'] == true || !(s['auto_generated'] as bool? ?? false)))
          s['id'] as String,
    };

    // Count kept hours per (submoduleCode, type).
    // Normalize codes to match reference: '7.3P' → '7.3' (P-suffix practical),
    // '12.7.1' → '12.7' (triple-component codes collapsed to two components).
    final doneT = <String, int>{};
    final doneP = <String, int>{};
    // Also count existing practice hours per task_id for assignment continuity
    final taskDoneByNc = <String, Map<dynamic, int>>{};
    for (final l in allLessons.where((l) => l.timeSlot > 0 && keptIds.contains(l.id))) {
      final c = normalizeSubCode(l.submoduleCode);
      if (l.isTheory) doneT[c] = (doneT[c] ?? 0) + 1;
      else {
        doneP[c] = (doneP[c] ?? 0) + 1;
        if (l.taskId != null) {
          (taskDoneByNc[c] ??= {})[l.taskId] = ((taskDoneByNc[c] ?? {})[l.taskId] ?? 0) + 1;
        }
      }
    }

    // Map: normalized submodule code → practicalTasks (for auto task assignment)
    final practicalTasksMap = <String, List<PracticalTask>>{};
    for (final m in typeInfo.modules) {
      for (final sub in m.submodules) {
        if (sub.practicalTasks.isNotEmpty) {
          practicalTasksMap[normalizeSubCode(sub.code)] = sub.practicalTasks;
        }
      }
    }
    // Track current task pointer per submodule during generation
    final taskPtr = <String, int>{};

    // Build blocks grouped by phase:
    //   0 – nessuna dipendenza
    //   1 – perDifferenzaOf == 12 (sottomoduli M11A "per differenza", dopo M12)
    //   2 – perDifferenzaOf == 11 (sottomoduli M11B, dopo M11A)
    final blocksByPhase = <int, Map<int, List<List<(String, int, String)>>>>{};
    for (final m in typeInfo.modules) {
      for (final sub in m.submodules) {
        final nc = normalizeSubCode(sub.code);
        final remT = (sub.theoryHours    - (doneT[nc] ?? 0)).clamp(0, sub.theoryHours);
        final remP = (sub.practicalHours - (doneP[nc] ?? 0)).clamp(0, sub.practicalHours);
        if (remT == 0 && remP == 0) continue;

        final phase = sub.perDifferenzaOf == null
            ? 0
            : sub.perDifferenzaOf == 12
                ? 1
                : 2;
        final phaseMap = blocksByPhase.putIfAbsent(phase, () => {});

        void addBlocks(int rem, String t) {
          var r = rem;
          while (r > 0) {
            final int size;
            if (t == 'pratica') {
              size = r >= 4 ? 4 : (r >= 2 ? 2 : 1);
            } else {
              size = r == 1 ? 1 : (r == 4 ? 2 : (r >= 3 ? 3 : 2));
            }
            phaseMap.putIfAbsent(m.number, () => [])
                .add(List.generate(size, (_) => (sub.code, m.number, t)));
            r -= size;
          }
        }

        if (remT > 0) addBlocks(remT, 'teoria');
        if (remP > 0) addBlocks(remP, 'pratica');
      }
    }

    // Interleave per fase (0 → 1 → 2); concatena nella queue finale.
    final queue = <(String, int, String)>[];
    for (final phase in [0, 1, 2]) {
      final phaseMods = blocksByPhase[phase] ?? {};
      if (phaseMods.isEmpty) continue;
      final phaseModNums = phaseMods.keys.toList()..sort();
      final phaseIdx = {for (final k in phaseModNums) k: 0};
      bool anyLeft = true;
      while (anyLeft) {
        anyLeft = false;
        for (final mod in phaseModNums) {
          final blocks = phaseMods[mod]!;
          final bi = phaseIdx[mod]!;
          if (bi < blocks.length) {
            queue.addAll(blocks[bi]);
            phaseIdx[mod] = bi + 1;
            anyLeft = true;
          }
        }
      }
    }

    // Remove old auto-generated unconfirmed lessons; keep confirmed + manual
    final cleaned = rawSchedules.where((s) {
      if (s['course_id'] != courseId) return true;
      return keptIds.contains(s['id']);
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
    // Prefisso timestamp: gli ID restano unici anche tra rigenerazioni
    // successive (le lezioni confermate di run precedenti non vengono rimosse).
    final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    var counter = 0;
    var qi = 0;

    while (qi < queue.length) {
      final weekday = date.weekday;
      final allDaySlots = typeInfo.schedule.slotsForWeekday(weekday);
      // Venerdì: max 3 slot (le ultime 3 ore sono libere)
      final slots = weekday == DateTime.friday
          ? allDaySlots.where((s) => s.slot <= 3).toList()
          : allDaySlots;
      final dateStr = _fmt(date);

      // Venerdì: prova a portare in testa un blocco di 3 ore stesso sottomodulo
      if (weekday == DateTime.friday && slots.length >= 3) {
        _rotateSameSubmoduleBlock(queue, qi, 3);
      }

      // Recovery slot 0 — Mon–Thu only (weekday 1..4)
      if (hasAttendeesInRecovery && weekday <= DateTime.thursday) {
        newLessons.add({
          'id': 'gen_rec_${runId}_${counter++}',
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

        // Auto-assign task_id for practice lessons
        dynamic assignedTaskId;
        if (lessonType == 'pratica') {
          final nc = normalizeSubCode(code);
          final tasks = practicalTasksMap[nc] ?? [];
          if (tasks.isNotEmpty) {
            final done = taskDoneByNc[nc] ??= {};
            var ptr = taskPtr[nc] ?? 0;
            while (ptr < tasks.length) {
              final task = tasks[ptr];
              final used = done[task.id] ?? 0;
              if (used < task.plannedHours) {
                assignedTaskId = task.id;
                done[task.id] = used + 1;
                if (used + 1 >= task.plannedHours) ptr++;
                taskPtr[nc] = ptr;
                break;
              }
              ptr++;
            }
            if (ptr <= (taskPtr[nc] ?? 0)) taskPtr[nc] = ptr;
          }
        }

        newLessons.add({
          'id': 'gen_${runId}_${counter++}',
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
          if (assignedTaskId != null) 'task_id': assignedTaskId,
          'created_at': now,
          'updated_at': now,
        });
      }

      date = _nextWorkday(_safeNext(date), excludedDates);
    }

    cleaned.addAll(newLessons);
    await _db.saveSchedules(cleaned);
  }

  /// Se possibile, sposta un blocco di [needed] ore dello stesso sottomodulo
  /// nella posizione [qi] della coda (best-effort, lookahead 30).
  void _rotateSameSubmoduleBlock(
    List<(String, int, String)> queue, int qi, int needed) {
    if (queue.length - qi < needed) return;
    final (code0, _, _) = queue[qi];
    bool alreadyOk = true;
    for (var k = 1; k < needed; k++) {
      if (queue[qi + k].$1 != code0) { alreadyOk = false; break; }
    }
    if (alreadyOk) return;
    const lookahead = 40;
    final limit = (qi + lookahead).clamp(0, queue.length - needed + 1);
    for (var i = qi + 1; i < limit; i++) {
      final (c, _, _) = queue[i];
      bool match = true;
      for (var k = 1; k < needed; k++) {
        if (queue[i + k].$1 != c) { match = false; break; }
      }
      if (match) {
        final block = queue.sublist(i, i + needed);
        queue.removeRange(i, i + needed);
        queue.insertAll(qi, block);
        return;
      }
    }
  }
}
