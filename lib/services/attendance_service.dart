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
