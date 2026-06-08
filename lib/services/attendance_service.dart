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
      final record = {
        'id': existing >= 0
            ? records[existing]['id']
            : now.microsecondsSinceEpoch.toRadixString(16) + attendeeId.substring(0, 4),
        'schedule_id': scheduleId,
        'course_id': courseId,
        'attendee_id': attendeeId,
        'present': presence[attendeeId] ?? false,
        'justification': null,
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
  /// Returns map keyed by module number: {total, absent, recovered, unrecovered}
  Map<int, Map<String, int>> computePerModuleStats(
    String courseId,
    String attendeeId,
    List<ScheduledLesson> allLessons,
  ) {
    final confirmedLessons = allLessons
        .where((l) => l.courseId == courseId && l.confirmed && l.timeSlot > 0)
        .toList();
    final records = getRecordsForAttendee(courseId, attendeeId);
    final recordMap = {for (final r in records) r.scheduleId: r};

    final Map<int, int> totalByModule = {};
    final Map<int, int> absentByModule = {};
    for (final l in confirmedLessons) {
      totalByModule[l.moduleNumber] = (totalByModule[l.moduleNumber] ?? 0) + 1;
      final r = recordMap[l.id];
      if (r != null && !r.present) {
        absentByModule[l.moduleNumber] = (absentByModule[l.moduleNumber] ?? 0) + 1;
      }
    }

    final Map<int, int> recoveredByModule = {};
    for (final r in records) {
      if (r.justification == 'recupero' && r.recoveredModule != null) {
        final m = r.recoveredModule!;
        recoveredByModule[m] = (recoveredByModule[m] ?? 0) + 1;
      }
    }

    final result = <int, Map<String, int>>{};
    for (final module in totalByModule.keys) {
      final total = totalByModule[module] ?? 0;
      final absent = absentByModule[module] ?? 0;
      final recovered = recoveredByModule[module] ?? 0;
      final unrecovered = (absent - recovered).clamp(0, absent);
      result[module] = {
        'total': total,
        'absent': absent,
        'recovered': recovered,
        'unrecovered': unrecovered,
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

  /// Returns true if at least one attendee in the course has >10% absence rate
  /// (excluding recoveries) relative to total confirmed lessons.
  bool courseHasAttendeesInRecovery(String courseId, List<String> attendeeIds, int totalLessons) {
    if (totalLessons == 0) return false;
    for (final id in attendeeIds) {
      final stats = computeAbsences(courseId, id);
      final absences = stats['absent'] ?? 0;
      final recoveries = getAllRecords()
          .where((r) => r.courseId == courseId && r.attendeeId == id && r.justification == 'recupero')
          .length;
      final unrecoveredAbsences = absences - recoveries;
      if (unrecoveredAbsences / totalLessons > 0.10) return true;
    }
    return false;
  }
}
