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
  /// Returns map keyed by module number: {total, absent, recovered, unrecovered,
  /// absentT/absentP, recoveredT/recoveredP, unrecoveredT/unrecoveredP,
  /// threshold (= floor(ore_modulo/10)), toRecoverT/toRecoverP/toRecover}.
  /// toRecover = ore da recuperare: pratica 100% + teoria oltre soglia 10%.
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

    // Recuperi per modulo, separati per tipo. Usa recovered_type quando presente;
    // per i record legacy senza tipo si applica l'euristica (pratica prima).
    final Map<int, int> recoveredByModule = {};
    final Map<int, int> recoveredTByModule = {};
    final Map<int, int> recoveredPByModule = {};
    final Map<int, int> recoveredUntypedByModule = {};
    for (final r in records) {
      if (r.justification == 'recupero' && r.recoveredModule != null) {
        final m = r.recoveredModule!;
        recoveredByModule[m] = (recoveredByModule[m] ?? 0) + 1;
        if (r.recoveredType == 'pratica') {
          recoveredPByModule[m] = (recoveredPByModule[m] ?? 0) + 1;
        } else if (r.recoveredType == 'teoria') {
          recoveredTByModule[m] = (recoveredTByModule[m] ?? 0) + 1;
        } else {
          recoveredUntypedByModule[m] = (recoveredUntypedByModule[m] ?? 0) + 1;
        }
      }
    }

    // Build total hours map: use planned module hours when available
    final plannedHours = modules != null
        ? {for (final m in modules) m.number: m.totalHours}
        : <int, int>{};

    final result = <int, Map<String, int>>{};
    final moduleKeys = {
      ...confirmedByModule.keys,
      ...absentByModule.keys,
      ...recoveredByModule.keys,
    };
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
      // Recuperi tipizzati noti + distribuzione legacy (pratica prima) sulle assenze residue
      int recoveredT = recoveredTByModule[moduleNum] ?? 0;
      int recoveredP = recoveredPByModule[moduleNum] ?? 0;
      final untyped = recoveredUntypedByModule[moduleNum] ?? 0;
      final remAbsP = (absentP - recoveredP).clamp(0, absentP);
      final addP = min(untyped, remAbsP);
      recoveredP += addP;
      recoveredT += untyped - addP;
      final unrecoveredT = (absentT - recoveredT).clamp(0, absentT);
      final unrecoveredP = (absentP - recoveredP).clamp(0, absentP);
      // Ore che il frequentatore deve ancora recuperare (regola corso):
      //  - Pratica: 100% delle assenze residue.
      //  - Teoria: solo le ore eccedenti la soglia 10% del modulo
      //    (floor(ore_modulo/10), come Excel), al netto della teoria già recuperata.
      final threshold = total ~/ 10;
      final toRecoverP = unrecoveredP;
      final toRecoverT = max(0, absentT - threshold - recoveredT);
      final toRecover = toRecoverT + toRecoverP;
      result[moduleNum] = {
        'total': total,
        'confirmed': confirmedH,
        'confirmedT': confirmedT,
        'confirmedP': confirmedP,
        'absent': absent,
        'absentT': absentT,
        'absentP': absentP,
        'recovered': recovered,
        'recoveredT': recoveredT,
        'recoveredP': recoveredP,
        'unrecovered': unrecovered,
        'unrecoveredT': unrecoveredT,
        'unrecoveredP': unrecoveredP,
        'threshold': threshold,
        'toRecoverT': toRecoverT,
        'toRecoverP': toRecoverP,
        'toRecover': toRecover,
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
    String? recoveredType,
    String? recoveredSubmodule,
  }) async {
    final records = _db.records.toList();
    final dateKey = recoveryDate.toIso8601String().split('T').first;
    // Il tipo entra nell'id sintetico così teoria e pratica dello stesso modulo/data
    // possono coesistere senza collidere col controllo "già esistente".
    final typeSuffix = recoveredType != null ? ':$recoveredType' : '';
    final syntheticScheduleId =
        'recovery:${courseId.substring(0, 8)}:${attendeeId.substring(0, 8)}:$dateKey:m$recoveredModule$typeSuffix';
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
      if (recoveredSubmodule != null) 'recovered_submodule': recoveredSubmodule,
      if (recoveredType != null) 'recovered_type': recoveredType,
      'confirmed_by': confirmedBy,
      'confirmed_at': DateTime.now().toIso8601String(),
    });
    await _db.saveRecords(records);
  }

  Future<void> deleteRecovery(String recordId) async {
    final records = _db.records.where((r) => r['id'] != recordId).toList();
    await _db.saveRecords(records);
  }

  /// Frequentatori fuori limite: per ogni modulo, se
  /// max(0, assenze_modulo − recuperi_totali_globali) > 10% ore pianificate modulo.
  /// I recuperi fanno pool globale (come formula Excel "nette oltre soglia").
  Set<String> attendeesOverRecoveryLimit(
    String courseId,
    List<String> attendeeIds,
    List<ScheduledLesson> allLessons, {
    List<ModuleInfo>? modules,
  }) {
    final plannedHours = modules != null
        ? {for (final m in modules) m.number: m.totalHours}
        : <int, int>{};
    final result = <String>{};
    for (final attendeeId in attendeeIds) {
      final stats = computePerModuleStats(
          courseId, attendeeId, allLessons, modules: modules);
      // Pool globale recuperi (indipendente da quale modulo è stato recuperato)
      int totalRecovered = 0;
      for (final s in stats.values) {
        totalRecovered += s['recovered'] ?? 0;
      }
      bool over = false;
      for (final e in stats.entries) {
        final absM = e.value['absent'] ?? 0;
        final nette = (absM - totalRecovered).clamp(0, absM);
        final planH = plannedHours[e.key] ?? (e.value['confirmed'] ?? 0);
        if (planH > 0 && nette > planH * 0.10) { over = true; break; }
      }
      if (over) result.add(attendeeId);
    }
    return result;
  }

  /// True se almeno un frequentatore supera il limite assenze (10% ore totali corso).
  bool courseHasAttendeesInRecovery(
    String courseId,
    List<String> attendeeIds,
    List<ScheduledLesson> allLessons, {
    List<ModuleInfo>? modules,
  }) =>
      attendeesOverRecoveryLimit(courseId, attendeeIds, allLessons, modules: modules).isNotEmpty;
}
