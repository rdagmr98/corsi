import 'dart:math';

import '../models/reference_models.dart';
import '../models/schedule_models.dart';
import 'gh_db_service.dart';

class AttendanceService {
  final _db = GhDbService();

  List<AttendanceRecord> getAllRecords() =>
      _db.records.map(AttendanceRecord.fromJson).toList();

  List<AttendanceRecord> getRecordsForLesson(String scheduleId) =>
      getAllRecords().where((r) => r.scheduleId == scheduleId).toList();

  List<AttendanceRecord> getRecordsForAttendee(String courseId, String attendeeId) =>
      getAllRecords()
          .where((r) => r.courseId == courseId && r.attendeeId == attendeeId)
          .toList();

  AttendanceRecord? getRecord(String scheduleId, String attendeeId) {
    try {
      return getAllRecords()
          .firstWhere((r) => r.scheduleId == scheduleId && r.attendeeId == attendeeId);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveAttendance({
    required String scheduleId,
    required String courseId,
    required List<String> attendeeIds,
    required Map<String, bool> presence,
    required String confirmedBy,
  }) async {
    final records = _db.records.toList();
    final now = DateTime.now();

    for (final attendeeId in attendeeIds) {
      final existing = records.indexWhere(
        (r) => r['schedule_id'] == scheduleId && r['attendee_id'] == attendeeId,
      );
      final prev = existing >= 0 ? records[existing] : null;
      final newPresent = presence[attendeeId] ?? false;
      final record = {
        'id': prev != null
            ? prev['id']
            : now.microsecondsSinceEpoch.toRadixString(16) + attendeeId.substring(0, 4),
        'schedule_id': scheduleId,
        'course_id': courseId,
        'attendee_id': attendeeId,
        'present': newPresent,
        // Una giustificazione registrata resta valida finché lo stato
        // presente/assente non cambia.
        'justification':
            prev != null && prev['present'] == newPresent ? prev['justification'] : null,
        'confirmed_by': confirmedBy,
        'confirmed_at': now.toIso8601String(),
      };
      if (existing >= 0) {
        records[existing] = record;
      } else {
        records.add(record);
      }
    }

    await _db.saveRecords(records);
  }

  Future<void> setJustification(String scheduleId, String attendeeId, String? justification) async {
    final records = _db.records.toList();
    final idx = records.indexWhere(
      (r) => r['schedule_id'] == scheduleId && r['attendee_id'] == attendeeId,
    );
    if (idx < 0) return;
    records[idx] = {...records[idx], 'justification': justification};
    await _db.saveRecords(records);
  }

  Map<String, int> computeAbsences(String courseId, String attendeeId) {
    final records = getRecordsForAttendee(courseId, attendeeId);
    int absent = 0;
    int unjustified = 0;
    for (final r in records) {
      if (!r.present) {
        absent++;
        if (r.justification == null) unjustified++;
      }
    }
    return {'absent': absent, 'unjustified': unjustified, 'total': records.length};
  }

  List<AttendanceRecord> getAllRecordsForCourse(String courseId) =>
      getAllRecords().where((r) => r.courseId == courseId).toList();

  /// Per-module absence/recovery stats for one attendee.
  /// 'total' = planned module hours from [modules] reference (if provided),
  /// otherwise falls back to confirmed lesson count.
  /// Returns map keyed by module number: {total, absent, recovered, unrecovered}
  Map<int, Map<String, int>> computePerModuleStats(
    String courseId,
    String attendeeId,
    List<ScheduledLesson> allLessons, {
    List<ModuleInfo>? modules,
  }) {
    final confirmedLessons = allLessons
        .where((l) => l.courseId == courseId && l.confirmed && l.timeSlot > 0)
        .toList();
    final records = getRecordsForAttendee(courseId, attendeeId);
    final recordMap = {for (final r in records) r.scheduleId: r};

    final Map<int, int> confirmedByModule = {};
    final Map<int, int> confirmedTByModule = {};
    final Map<int, int> confirmedPByModule = {};
    final Map<int, int> absentByModule = {};
    final Map<int, int> absentTByModule = {};
    final Map<int, int> absentPByModule = {};
    for (final l in confirmedLessons) {
      confirmedByModule[l.moduleNumber] = (confirmedByModule[l.moduleNumber] ?? 0) + 1;
      if (l.isTheory) {
        confirmedTByModule[l.moduleNumber] = (confirmedTByModule[l.moduleNumber] ?? 0) + 1;
      } else {
        confirmedPByModule[l.moduleNumber] = (confirmedPByModule[l.moduleNumber] ?? 0) + 1;
      }
      final r = recordMap[l.id];
      if (r != null && !r.present) {
        absentByModule[l.moduleNumber] = (absentByModule[l.moduleNumber] ?? 0) + 1;
        if (l.isTheory) {
          absentTByModule[l.moduleNumber] = (absentTByModule[l.moduleNumber] ?? 0) + 1;
        } else {
          absentPByModule[l.moduleNumber] = (absentPByModule[l.moduleNumber] ?? 0) + 1;
        }
      }
    }

    final Map<int, int> recoveredByModule = {};
    for (final r in records) {
      if (r.justification == 'recupero' && r.recoveredModule != null) {
        final m = r.recoveredModule!;
        recoveredByModule[m] = (recoveredByModule[m] ?? 0) + 1;
      }
    }

    // Build total hours map: use planned module hours when available
    final plannedHours = modules != null
        ? {for (final m in modules) m.number: m.totalHours}
        : <int, int>{};

    final result = <int, Map<String, int>>{};
    final moduleKeys = {...confirmedByModule.keys, ...absentByModule.keys};
    for (final moduleNum in moduleKeys) {
      final confirmedH = confirmedByModule[moduleNum] ?? 0;
      final confirmedT = confirmedTByModule[moduleNum] ?? 0;
      final confirmedP = confirmedPByModule[moduleNum] ?? 0;
      final total = max(plannedHours[moduleNum] ?? 0, confirmedH);
      final absent = absentByModule[moduleNum] ?? 0;
      final absentT = absentTByModule[moduleNum] ?? 0;
      final absentP = absentPByModule[moduleNum] ?? 0;
      final recovered = recoveredByModule[moduleNum] ?? 0;
      final unrecovered = (absent - recovered).clamp(0, absent);
      // Recoveries applied to practice first (stricter rule), then theory
      final recForP = min(recovered, absentP);
      final recForT = recovered - recForP;
      final unrecoveredP = absentP - recForP;
      final unrecoveredT = (absentT - recForT).clamp(0, absentT);
      result[moduleNum] = {
        'total': total,
        'confirmed': confirmedH,
        'confirmedT': confirmedT,
        'confirmedP': confirmedP,
        'absent': absent,
        'absentT': absentT,
        'absentP': absentP,
        'recovered': recovered,
        'unrecovered': unrecovered,
        'unrecoveredT': unrecoveredT,
        'unrecoveredP': unrecoveredP,
      };
    }
    return result;
  }

  Future<void> saveRecovery({
    required String courseId,
    required String attendeeId,
    required String confirmedBy,
    required int recoveredModule,
    required DateTime recoveryDate,
  }) async {
    final records = _db.records.toList();
    final dateKey = recoveryDate.toIso8601String().split('T').first;
    final syntheticScheduleId =
        'recovery:${courseId.substring(0, 8)}:${attendeeId.substring(0, 8)}:$dateKey:m$recoveredModule';
    final alreadyExists = records.any((r) =>
        r['schedule_id'] == syntheticScheduleId &&
        r['attendee_id'] == attendeeId);
    if (alreadyExists) return;

    final id = 'rec_${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    records.add({
      'id': id,
      'schedule_id': syntheticScheduleId,
      'course_id': courseId,
      'attendee_id': attendeeId,
      'present': true,
      'justification': 'recupero',
      'recovered_module': recoveredModule,
      'confirmed_by': confirmedBy,
      'confirmed_at': DateTime.now().toIso8601String(),
    });
    await _db.saveRecords(records);
  }

  Future<void> deleteRecovery(String recordId) async {
    final records = _db.records.where((r) => r['id'] != recordId).toList();
    await _db.saveRecords(records);
  }

  /// Frequentatori fuori limite: pratica con assenze non recuperate al 100%,
  /// o teoria con >10% assenze non recuperate sulle ore di teoria PIANIFICATE del modulo.
  Set<String> attendeesOverRecoveryLimit(
    String courseId,
    List<String> attendeeIds,
    List<ScheduledLesson> allLessons, {
    List<ModuleInfo>? modules,
  }) {
    final plannedT = modules != null
        ? {for (final m in modules) m.number: m.theoryHours}
        : <int, int>{};
    final result = <String>{};
    for (final attendeeId in attendeeIds) {
      final stats = computePerModuleStats(
          courseId, attendeeId, allLessons, modules: modules);
      bool over = false;
      for (final e in stats.entries) {
        if ((e.value['unrecoveredP'] ?? 0) > 0) { over = true; break; }
        final unrecT = e.value['unrecoveredT'] ?? 0;
        final planT  = plannedT[e.key] ?? (e.value['confirmedT'] ?? 0);
        if (planT > 0 && unrecT / planT > 0.10) { over = true; break; }
      }
      if (over) result.add(attendeeId);
    }
    return result;
  }

  /// True se almeno un frequentatore supera il limite assenze (pratica 100%, teoria 10%).
  bool courseHasAttendeesInRecovery(
    String courseId,
    List<String> attendeeIds,
    List<ScheduledLesson> allLessons, {
    List<ModuleInfo>? modules,
  }) =>
      attendeesOverRecoveryLimit(courseId, attendeeIds, allLessons, modules: modules).isNotEmpty;
}
