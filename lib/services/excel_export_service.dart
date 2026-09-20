import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';

import '../models/course_models.dart';
import '../models/reference_models.dart';
import '../models/schedule_models.dart';
import '../models/user_models.dart';
import '../utils/file_download.dart';
import 'ps_ooxml_filler.dart';

/// Export programma settimanale .xlsx clonando il template ufficiale PS
/// (`66_PS` foglio EI). Patch OOXML in-place (merges/bordi/font/pausa
/// preservati). Colori lezione = `moduleColor` via cellXf pre-registrati.
///
/// Colonne (1-based B..N): DATA | ORARIO | ADDESTRAMENTO | Ore Mod. |
/// Ore Tot. Mod. | ISTRUTTORE | Sott. Mod. | ID TASK | Ore | LOCALITA'/AULA
/// (LOCALITA'/AULA = una sola colonna merge N:O, come 66_PS).
///
/// Frequentatori (66_PS PERSONALE INTERESSATO):
/// - R48 title, R49 headers fixed in blank
/// - R50+: sinistra B/C = ESERCITO, destra I/J = CARABINIERI (forza=CC / titolo CAR.)
/// - numbering restarts at 1 in each column
/// - Footer destra I62–I63: IL COMANDANTE / (Accountable Manager); I64 vuoto
///
/// Unknown fields (firma AM, ecc.) restano vuoti.
class ExcelExportService {
  static const _templateAsset = 'assets/templates/ps_weekly_blank.xlsx';

  /// Max chars for ADDESTRAMENTO (D:F merge, print 1 page). Submodule is in K.
  static const addestramentoMaxChars = 42;

  /// First data row under PERSONALE INTERESSATO (headers are row 49).
  static const attendeeDataStartRow = 50;

  /// Template data slots: rows 50–58 (9), chrome ends at 58.
  static const attendeeMaxRows = 9;

  /// Official 66_PS LOCALITA' labels.
  static const hangarPratica = 'HANGAR 6';

  /// Teoria → `AULA n`; pratica/task → `HANGAR 6`. Null aula → null (blank cell).
  static String? localitaLabel({
    required bool isTheory,
    int? aula,
  }) {
    if (!isTheory) return hangarPratica;
    if (aula == null || aula < 1 || aula > 7) return null;
    return 'AULA $aula';
  }

  static int? resolveAula(ScheduledLesson lesson, Course course) =>
      lesson.aula ?? course.resolvedDefaultAula;

  /// Template label: "GRADO, NOME e COGNOME".
  static String attendeePsLabel(AppUser u) {
    final grado = (u.titolo ?? '').trim();
    final nome = u.nome.trim().toUpperCase();
    final cognome = u.cognome.trim().toUpperCase();
    return [grado, nome, cognome].where((s) => s.isNotEmpty).join(' ');
  }

  /// Destra (CARABINIERI) se `forza=CC` o grado titolo tipo CAR./CC.
  static bool isCarabinieriAttendee(AppUser u) => u.isCarabinieri;

  /// Blocchi giorno nel template (righe Excel 1-based).
  static const _dayBlocks = <(int, int)>[
    (10, 17), // Lun
    (18, 25), // Mar
    (26, 33), // Mer
    (34, 41), // Gio
    (42, 44), // Ven
  ];

  /// Mon–Thu: first hour = Disposizione (fixed template label).
  static const _disposizioneOffset = 0;

  /// Mon–Thu: sixth hour = yellow pausa pranzo (fixed template chrome).
  static const _lunchOffset = 5;

  /// Truncate for print; ASCII `...`, prefer break at last space.
  /// Submodule is already in col K — full module title is less critical.
  static String fitAddestramento(String text,
      {int max = addestramentoMaxChars}) {
    final t = text
        .trim()
        .replaceAll('…', '...')
        .replaceAll('⋯', '...')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (t.length <= max) return t;
    if (max <= 3) return '...';
    var cut = t.substring(0, max - 3);
    final sp = cut.lastIndexOf(' ');
    if (sp >= max ~/ 2) cut = cut.substring(0, sp);
    return '$cut...';
  }

  static Future<void> downloadWeeklySchedule({
    required Course course,
    required CourseTypeInfo? typeInfo,
    required DateTime weekStart,
    required List<ScheduledLesson> weekLessons,
    required List<SlotNote> weekNotes,
    required Map<String, AppUser> instructors,
    required List<AppUser> directors,
    required Map<String, String> subNames,
    required List<AppUser> attendees,
    List<ScheduledLesson> allCourseLessons = const [],
  }) async {
    final bytes = await buildWeeklyScheduleBytes(
      course: course,
      typeInfo: typeInfo,
      weekStart: weekStart,
      weekLessons: weekLessons,
      weekNotes: weekNotes,
      instructors: instructors,
      directors: directors,
      subNames: subNames,
      attendees: attendees,
      allCourseLessons: allCourseLessons,
    );
    final weekLabel = DateFormat('yyyy-MM-dd').format(weekStart);
    final safeTitle = course.title.replaceAll(RegExp(r'[^\w\- ]'), '_');
    await downloadBytes(
      bytes,
      '${safeTitle}_PS_$weekLabel.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  static Future<Uint8List> buildWeeklyScheduleBytes({
    required Course course,
    required CourseTypeInfo? typeInfo,
    required DateTime weekStart,
    required List<ScheduledLesson> weekLessons,
    required List<SlotNote> weekNotes,
    required Map<String, AppUser> instructors,
    required List<AppUser> directors,
    required Map<String, String> subNames,
    required List<AppUser> attendees,
    List<ScheduledLesson> allCourseLessons = const [],
  }) async {
    final asset = await rootBundle.load(_templateAsset);
    final filler = PsOoxmlFiller(
      asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
    );
    filler.load();

    final weekEnd = weekStart.add(const Duration(days: 4));
    final sheetName =
        '${DateFormat('dd.MM').format(weekStart)}_${DateFormat('dd.MM').format(weekEnd)}';
    filler.renameSheet(sheetName);

    final modByNumber = {
      for (final m in typeInfo?.modules ?? const <ModuleInfo>[]) m.number: m,
    };

    String moduleTitle(ScheduledLesson l) {
      final m = modByNumber[l.moduleNumber];
      if (m == null) {
        return l.topic.isNotEmpty ? l.topic : 'Modulo ${l.moduleNumber}';
      }
      return 'Modulo ${m.displayCode} ${m.name}';
    }

    String personLabel(String? id) {
      if (id == null) return '';
      final u = instructors[id];
      if (u == null) return '';
      return u.cognome.toUpperCase();
    }

    String instructorLabel(ScheduledLesson l) {
      final a = personLabel(l.instructorId);
      final b = personLabel(l.instructorId2);
      if (a.isEmpty) return b;
      if (b.isEmpty) return a;
      return '$a / $b';
    }

    String oreTotMod(ScheduledLesson l) {
      final m = modByNumber[l.moduleNumber];
      if (m == null) return '';
      return '${m.theoryHours}+${m.practicalHours}';
    }

    String sottMod(ScheduledLesson l) {
      final code = l.submoduleCode.trim();
      if (code.isEmpty) return '';
      final u = code.toUpperCase();
      if (u.startsWith('T') || u.startsWith('P')) return code;
      return '${l.isTheory ? 'T' : 'P'}$code';
    }

    final corpus = allCourseLessons.isNotEmpty ? allCourseLessons : weekLessons;
    final sortedAll = [...corpus.where((l) => l.timeSlot > 0)]
      ..sort((a, b) {
        final c = a.date.compareTo(b.date);
        return c != 0 ? c : a.timeSlot.compareTo(b.timeSlot);
      });
    final oreModById = <String, int>{};
    final subOrdById = <String, int>{};
    final cntMod = <int, int>{};
    final cntSub = <String, int>{};
    for (final l in sortedAll) {
      cntMod[l.moduleNumber] = (cntMod[l.moduleNumber] ?? 0) + 1;
      oreModById[l.id] = cntMod[l.moduleNumber]!;
      final sk = '${l.submoduleCode}|${l.type}';
      cntSub[sk] = (cntSub[sk] ?? 0) + 1;
      subOrdById[l.id] = cntSub[sk]!;
    }

    // Header corso = celle ufficiali 66_PS (B6/D6, F6/J6, B7/D7, F7/J7).
    filler.setText('B5', course.title);
    if (course.startDate != null) {
      filler.setDate('D6', course.startDate!); // DATA INIZIO CORSO
    }
    if (course.endDate != null) {
      filler.setDate('J6', course.endDate!); // DATA FINE CORSO (PIANIFICATA)
    }
    if (course.durationWeeks != null) {
      filler.setText('D7', Course.formatDurationWeeks(course.durationWeeks!));
    }
    if (course.delayWeeks != null) {
      filler.setInt('J7', course.delayWeeks!); // EVENTUALE RITARDO (N. SETT.)
    }

    final regular = weekLessons.where((l) => l.timeSlot > 0).toList();
    final recovery = weekLessons.where((l) => l.timeSlot == 0).toList();
    final defaultSlots =
        typeInfo?.schedule.mondayThursday ?? const <TimeSlot>[];

    // Track which rows got a lesson (for recovery fill)
    final filledRows = <int>{};

    for (var dayIdx = 0; dayIdx < 5; dayIdx++) {
      final day = weekStart.add(Duration(days: dayIdx));
      final (startRow, endRow) = _dayBlocks[dayIdx];
      final fullDay = endRow - startRow == 7; // Lun–Gio: 8 rows
      final lunchRow = fullDay ? startRow + _lunchOffset : null;
      final disposizioneRow =
          fullDay ? startRow + _disposizioneOffset : null;
      // App slots map onto teaching rows only — never Disposizione or lunch.
      final lessonRows = [
        for (var r = startRow; r <= endRow; r++)
          if (r != lunchRow && r != disposizioneRow) r,
      ];

      final daySlots =
          typeInfo?.schedule.slotsForWeekday(day.weekday) ?? defaultSlots;

      filler.setDate('B$startRow', day);

      for (var i = 0; i < lessonRows.length; i++) {
        final excelRow1 = lessonRows[i];
        final slot = i < daySlots.length ? daySlots[i] : null;

        ScheduledLesson? lesson;
        if (slot != null) {
          lesson = regular
              .where((l) =>
                  l.date.year == day.year &&
                  l.date.month == day.month &&
                  l.date.day == day.day &&
                  l.timeSlot == slot.slot)
              .firstOrNull;
        }
        final note = slot == null
            ? null
            : weekNotes
                .where((n) =>
                    n.date.year == day.year &&
                    n.date.month == day.month &&
                    n.date.day == day.day &&
                    n.timeSlot == slot.slot)
                .firstOrNull;

        if (lesson != null) {
          final aula = resolveAula(lesson, course);
          filler.paintLessonRow(
            row1Based: excelRow1,
            moduleNumber: lesson.moduleNumber,
            addestramento: fitAddestramento(moduleTitle(lesson)),
            oreMod: oreModById[lesson.id] ?? 0,
            oreTot: oreTotMod(lesson),
            instructor: instructorLabel(lesson),
            sott: sottMod(lesson),
            taskId: lesson.taskId?.toString(),
            oreSub: subOrdById[lesson.id] ?? 0,
            localita: localitaLabel(isTheory: lesson.isTheory, aula: aula),
          );
          filledRows.add(excelRow1);
        } else if (note != null && note.text.isNotEmpty) {
          filler.setText('D$excelRow1', fitAddestramento(note.text));
          filledRows.add(excelRow1);
        }
      }

      final dayRec = recovery
          .where((l) =>
              l.date.year == day.year &&
              l.date.month == day.month &&
              l.date.day == day.day)
          .toList();
      var recIdx = 0;
      for (final excelRow1 in lessonRows) {
        if (recIdx >= dayRec.length) break;
        if (filledRows.contains(excelRow1)) continue;
        final rec = dayRec[recIdx++];
        final aula = resolveAula(rec, course);
        filler.paintLessonRow(
          row1Based: excelRow1,
          moduleNumber: rec.moduleNumber,
          addestramento:
              fitAddestramento('REC: ${moduleTitle(rec)}'),
          oreMod: oreModById[rec.id] ?? 0,
          oreTot: oreTotMod(rec),
          instructor: instructorLabel(rec),
          sott: sottMod(rec),
          taskId: rec.taskId?.toString(),
          oreSub: subOrdById[rec.id] ?? 0,
          localita: localitaLabel(isTheory: rec.isTheory, aula: aula),
        );
        filledRows.add(excelRow1);
      }
    }

    final directorNames = directors.map((d) {
      final t = d.titolo?.trim();
      return (t != null && t.isNotEmpty)
          ? '$t ${d.cognome} ${d.nome}'.trim()
          : d.fullName;
    }).join(' / ');
    // Leave blank after label if unknown (same as aula — no invented placeholder).
    filler.setText(
      'B46',
      directorNames.isEmpty
          ? 'Direttore del corso: '
          : 'Direttore del corso: $directorNames',
    );

    final sortedAtt = [...attendees]
      ..sort((a, b) => a.cognome.compareTo(b.cognome));
    final esercito = sortedAtt.where((u) => !isCarabinieriAttendee(u)).toList();
    final carabinieri =
        sortedAtt.where(isCarabinieriAttendee).toList();
    // 66_PS: col sinistra ESERCITO (B=N., C=label), destra CARABINIERI (I/J).
    // Numerazione indipendente da 1 in ciascuna colonna; non inventare Capo Corso.
    final nEs = esercito.length < attendeeMaxRows
        ? esercito.length
        : attendeeMaxRows;
    final nCc = carabinieri.length < attendeeMaxRows
        ? carabinieri.length
        : attendeeMaxRows;
    for (var i = 0; i < nEs; i++) {
      final row = attendeeDataStartRow + i;
      filler.setInt('B$row', i + 1);
      filler.setText('C$row', attendeePsLabel(esercito[i]));
    }
    for (var i = 0; i < nCc; i++) {
      final row = attendeeDataStartRow + i;
      filler.setInt('I$row', i + 1);
      filler.setText('J$row', attendeePsLabel(carabinieri[i]));
    }

    return filler.encode();
  }
}
