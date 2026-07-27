import 'dart:math';

import '../models/reference_models.dart';
import '../models/schedule_models.dart';
import 'gh_db_service.dart';

/// Dettaglio di una singola assenza (una lezione) per la vista per-studente
/// del direttore: se è stata recuperata (con data e, se nota, sottomodulo/tipo
/// dell'ora di recupero) oppure no, e in tal caso se è tollerata (teoria entro
/// la soglia 10%) o da recuperare.
class AbsenceDetail {
  final ScheduledLesson lesson;
  final String type; // 'teoria' | 'pratica'
  final bool isRecovered;
  final bool isTolerated;
  final DateTime? recoveryDate;
  final String? recoveredSubmodule;

  const AbsenceDetail({
    required this.lesson,
    required this.type,
    required this.isRecovered,
    required this.isTolerated,
    this.recoveryDate,
    this.recoveredSubmodule,
  });

  bool get needsRecovery => !isRecovered && !isTolerated;
}

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

  List<AttendanceRecord> getRecoveriesForCourse(String courseId) => getAllRecords()
      .where((r) => r.courseId == courseId && r.justification == 'recupero')
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
  /// threshold (= floor(ore_teoria_modulo/10)), toRecoverT/toRecoverP/toRecover}.
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
    final plannedTheoryHours = modules != null
        ? {for (final m in modules) m.number: m.theoryHours}
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
      final theoryTotal = max(plannedTheoryHours[moduleNum] ?? 0, confirmedT);
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
      //  - Teoria: solo le ore eccedenti la soglia 10% delle ore di TEORIA
      //    del modulo (floor(ore_teoria_modulo/10), come Excel), al netto
      //    della teoria già recuperata.
      final threshold = theoryTotal ~/ 10;
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

  /// Per ogni assenza (lezione confermata con record present=false), se la
  /// sua ora è stata recuperata, la data del recupero che la "copre".
  /// Il sistema registra i recuperi come pool per modulo+tipo (non un legame
  /// 1:1 con l'assenza specifica), quindi l'abbinamento è FIFO: l'assenza
  /// più vecchia è la prima a considerarsi recuperata, coerente con
  /// l'ordine in cui maturano i conteggi aggregati di [computePerModuleStats].
  /// Ritorna: scheduleId della lezione assente -> data del recupero.
  Map<String, DateTime> pairAbsenceRecoveries(
    String courseId,
    String attendeeId,
    List<ScheduledLesson> allLessons,
  ) {
    final lessonsById = {
      for (final l in allLessons)
        if (l.courseId == courseId) l.id: l,
    };
    final records = getRecordsForAttendee(courseId, attendeeId);

    final absences = <Map<String, dynamic>>[];
    for (final r in records) {
      if (r.present) continue;
      final l = lessonsById[r.scheduleId];
      if (l == null || !l.confirmed || l.timeSlot == 0) continue;
      absences.add({
        'scheduleId': r.scheduleId,
        'date': l.date,
        'module': l.moduleNumber,
        'type': l.isTheory ? 'teoria' : 'pratica',
      });
    }
    absences.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    final recoveries = <Map<String, dynamic>>[];
    for (final r in records) {
      final date = r.recoveryDate;
      if (date == null || r.recoveredModule == null) continue;
      recoveries.add({
        'date': date,
        'module': r.recoveredModule,
        'type': r.recoveredType ?? 'pratica',
      });
    }
    recoveries.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    final result = <String, DateTime>{};
    final usedRecoveryIdx = <int>{};
    for (final absence in absences) {
      for (var i = 0; i < recoveries.length; i++) {
        if (usedRecoveryIdx.contains(i)) continue;
        if (recoveries[i]['module'] != absence['module']) continue;
        if (recoveries[i]['type'] != absence['type']) continue;
        result[absence['scheduleId'] as String] = recoveries[i]['date'] as DateTime;
        usedRecoveryIdx.add(i);
        break;
      }
    }
    return result;
  }

  /// Dettaglio per-assenza (una riga per lezione persa) di un modulo, per la
  /// vista per-studente del direttore. A differenza di [pairAbsenceRecoveries]
  /// (solo data, solo per chi NON ha sottomodulo/tipo) qui si espone anche
  /// sottomodulo/tipo recuperato quando noto, e lo stato "tollerata" vs
  /// "da recuperare". Stessa convenzione FIFO (assenza più vecchia ↔ recupero
  /// più vecchio nello stesso pool tipo) e stessa eristica di distribuzione dei
  /// recuperi legacy non tipizzati di [computePerModuleStats], in modo che i
  /// conteggi per-riga (recuperate/tollerate/da recuperare) coincidano sempre
  /// con i totali aggregati di quel metodo.
  List<AbsenceDetail> absenceDetailsForModule(
    String courseId,
    String attendeeId,
    List<ScheduledLesson> allLessons,
    int moduleNumber, {
    List<ModuleInfo>? modules,
  }) {
    final records = getRecordsForAttendee(courseId, attendeeId);
    final recordMap = {for (final r in records) r.scheduleId: r};

    final absT = <ScheduledLesson>[];
    final absP = <ScheduledLesson>[];
    for (final l in allLessons) {
      if (l.courseId != courseId || l.moduleNumber != moduleNumber) continue;
      if (!l.confirmed || l.timeSlot == 0) continue;
      final r = recordMap[l.id];
      if (r == null || r.present) continue;
      (l.isTheory ? absT : absP).add(l);
    }
    absT.sort((a, b) => a.date.compareTo(b.date));
    absP.sort((a, b) => a.date.compareTo(b.date));

    final recT = <Map<String, dynamic>>[];
    final recP = <Map<String, dynamic>>[];
    final recUntyped = <Map<String, dynamic>>[];
    for (final r in records) {
      if (r.recoveredModule != moduleNumber) continue;
      final d = r.recoveryDate;
      if (d == null) continue;
      final entry = {'date': d, 'submodule': r.recoveredSubmodule};
      if (r.recoveredType == 'pratica') {
        recP.add(entry);
      } else if (r.recoveredType == 'teoria') {
        recT.add(entry);
      } else {
        recUntyped.add(entry);
      }
    }
    recT.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    recP.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    recUntyped.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    // Stessa eristica di computePerModuleStats: i recuperi non tipizzati
    // (legacy) riempiono prima il fabbisogno pratica residuo.
    final remAbsP = (absP.length - recP.length).clamp(0, absP.length);
    final addP = min(recUntyped.length, remAbsP);
    recP.addAll(recUntyped.take(addP));
    recT.addAll(recUntyped.skip(addP));
    recP.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    recT.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    var theoryTotal = 0;
    if (modules != null) {
      for (final m in modules) {
        if (m.number == moduleNumber) { theoryTotal = m.theoryHours; break; }
      }
    }
    final threshold = theoryTotal ~/ 10;

    List<AbsenceDetail> buildDetails(
      List<ScheduledLesson> abs,
      List<Map<String, dynamic>> rec,
      String type,
      bool toleranceApplies,
    ) {
      final recoveredCount = min(abs.length, rec.length);
      final toleratedCount =
          toleranceApplies ? min(threshold, abs.length - recoveredCount) : 0;
      final details = <AbsenceDetail>[];
      for (var i = 0; i < abs.length; i++) {
        if (i < recoveredCount) {
          details.add(AbsenceDetail(
            lesson: abs[i],
            type: type,
            isRecovered: true,
            isTolerated: false,
            recoveryDate: rec[i]['date'] as DateTime,
            recoveredSubmodule: rec[i]['submodule'] as String?,
          ));
        } else {
          details.add(AbsenceDetail(
            lesson: abs[i],
            type: type,
            isRecovered: false,
            isTolerated: (i - recoveredCount) < toleratedCount,
          ));
        }
      }
      return details;
    }

    final result = [
      ...buildDetails(absT, recT, 'teoria', true),
      ...buildDetails(absP, recP, 'pratica', false),
    ];
    result.sort((a, b) => a.lesson.date.compareTo(b.lesson.date));
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
