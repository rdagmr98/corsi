import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';

import '../models/course_models.dart';
import '../models/reference_models.dart';
import '../models/schedule_models.dart';
import '../models/user_models.dart';
import '../theme.dart';
import '../utils/file_download.dart';

/// Export programma settimanale .xlsx clonando il template ufficiale PS
/// (`66_PS` foglio EI — merges/bordi/orari/pausa pranzo preservati).
///
/// Colonne (1-based B..N): DATA | ORARIO | ADDESTRAMENTO | Ore Mod. |
/// Ore Tot. Mod. | ISTRUTTORE | Sott. Mod. | ID TASK | Ore | LOCALITA'
class ExcelExportService {
  static const _templateAsset = 'assets/templates/ps_weekly_blank.xlsx';

  /// Blocchi giorno nel template (righe Excel 1-based).
  static const _dayBlocks = <(int, int)>[
    (10, 17), // Lun
    (18, 25), // Mar
    (26, 33), // Mer
    (34, 41), // Gio
    (42, 44), // Ven
  ];

  /// Offset pausa pranzo (giallo) nei blocchi da 8 righe Lun–Gio.
  static const _lunchOffset = 5;

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
    final excel = Excel.decodeBytes(
      asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
    );

    final weekEnd = weekStart.add(const Duration(days: 4));
    final sheetName =
        '${DateFormat('dd.MM').format(weekStart)}_${DateFormat('dd.MM').format(weekEnd)}';
    const templateSheet = 'Settimana';
    if (excel.sheets.containsKey(templateSheet)) {
      excel.rename(templateSheet, sheetName);
    }
    final sheet = excel[sheetName];

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

    // Progressivi corso-wide (Ore Mod. / Ore sottomodulo)
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

    // Header
    _setText(sheet, 1, 4, course.title); // B5
    if (course.startDate != null) {
      final d = course.startDate!;
      _set(
        sheet,
        3,
        5,
        DateCellValue(year: d.year, month: d.month, day: d.day),
      );
    }
    if (course.endDate != null) {
      final d = course.endDate!;
      _set(
        sheet,
        9,
        5,
        DateCellValue(year: d.year, month: d.month, day: d.day),
      );
    }
    if (course.startDate != null && course.endDate != null) {
      final weeks =
          (course.endDate!.difference(course.startDate!).inDays / 7).ceil();
      _setText(sheet, 3, 6, '$weeks  SETTIMANE');
    }

    final regular = weekLessons.where((l) => l.timeSlot > 0).toList();
    final recovery = weekLessons.where((l) => l.timeSlot == 0).toList();
    final defaultSlots =
        typeInfo?.schedule.mondayThursday ?? const <TimeSlot>[];

    for (var dayIdx = 0; dayIdx < 5; dayIdx++) {
      final day = weekStart.add(Duration(days: dayIdx));
      final (startRow, endRow) = _dayBlocks[dayIdx]; // 1-based
      final lunchRow = (endRow - startRow == 7) ? startRow + _lunchOffset : null;
      final lessonRows = [
        for (var r = startRow; r <= endRow; r++)
          if (r != lunchRow) r,
      ];

      final daySlots =
          typeInfo?.schedule.slotsForWeekday(day.weekday) ?? defaultSlots;

      // DATA (merged B start:end)
      _set(
        sheet,
        1,
        startRow - 1,
        DateCellValue(year: day.year, month: day.month, day: day.day),
      );

      for (var i = 0; i < lessonRows.length; i++) {
        final excelRow1 = lessonRows[i];
        final rowIdx = excelRow1 - 1;
        final slot = i < daySlots.length ? daySlots[i] : null;

        // Prefer match by timeSlot number; fallback by order
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
          _fillLessonRow(
            sheet,
            rowIdx,
            lesson: lesson,
            moduleTitle: moduleTitle(lesson),
            instructor: instructorLabel(lesson),
            oreMod: oreModById[lesson.id] ?? 0,
            oreTot: oreTotMod(lesson),
            sott: sottMod(lesson),
            subOrd: subOrdById[lesson.id] ?? 0,
          );
        } else if (note != null && note.text.isNotEmpty) {
          _setText(sheet, 3, rowIdx, note.text);
        }
      }

      // Recuperi: riempi slot vuoti dello stesso giorno
      final dayRec = recovery
          .where((l) =>
              l.date.year == day.year &&
              l.date.month == day.month &&
              l.date.day == day.day)
          .toList();
      var recIdx = 0;
      for (final excelRow1 in lessonRows) {
        if (recIdx >= dayRec.length) break;
        final rowIdx = excelRow1 - 1;
        final existing = sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx))
            .value;
        if (existing != null) continue;
        final rec = dayRec[recIdx++];
        _fillLessonRow(
          sheet,
          rowIdx,
          lesson: rec,
          moduleTitle: 'REC: ${moduleTitle(rec)}',
          instructor: instructorLabel(rec),
          oreMod: oreModById[rec.id] ?? 0,
          oreTot: oreTotMod(rec),
          sott: sottMod(rec),
          subOrd: subOrdById[rec.id] ?? 0,
        );
      }
    }

    // Direttore
    final directorNames = directors.map((d) {
      final t = d.titolo?.trim();
      return (t != null && t.isNotEmpty)
          ? '$t ${d.cognome} ${d.nome}'.trim()
          : d.fullName;
    }).join(' / ');
    _setText(
      sheet,
      1,
      45,
      'Direttore del corso: ${directorNames.isEmpty ? "—" : directorNames}',
    );

    // PERSONALE INTERESSATO — riga 50+
    final sortedAtt = [...attendees]
      ..sort((a, b) => a.cognome.compareTo(b.cognome));
    final mid = (sortedAtt.length + 1) ~/ 2;
    final left = sortedAtt.take(mid).toList();
    final right = sortedAtt.skip(mid).toList();
    final maxRows = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < maxRows; i++) {
      final rowIdx = 49 + i; // Excel row 50
      if (i < left.length) {
        _set(sheet, 1, rowIdx, IntCellValue(i + 1));
        _setText(
          sheet,
          2,
          rowIdx,
          '${left[i].titolo ?? ""} ${left[i].fullName}'.trim(),
        );
      }
      if (i < right.length) {
        _set(sheet, 8, rowIdx, IntCellValue(mid + i + 1));
        _setText(
          sheet,
          9,
          rowIdx,
          '${right[i].titolo ?? ""} ${right[i].fullName}'.trim(),
        );
      }
    }

    final encoded = excel.encode();
    if (encoded == null) {
      throw StateError('Generazione Excel fallita');
    }
    return Uint8List.fromList(encoded);
  }

  static void _fillLessonRow(
    Sheet sheet,
    int rowIdx, {
    required ScheduledLesson lesson,
    required String moduleTitle,
    required String instructor,
    required int oreMod,
    required String oreTot,
    required String sott,
    required int subOrd,
  }) {
    final bg = _excelColor(moduleColor(lesson.moduleNumber));
    final style = CellStyle(
      backgroundColorHex: bg,
      fontColorHex: ExcelColor.white,
      fontSize: 9,
      fontFamily: getFontFamily(FontFamily.Arial),
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
      leftBorder: Border(borderStyle: BorderStyle.Thin),
      rightBorder: Border(borderStyle: BorderStyle.Thin),
      topBorder: Border(borderStyle: BorderStyle.Thin),
      bottomBorder: Border(borderStyle: BorderStyle.Thin),
    );

    void paint(int col, CellValue value) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIdx),
      );
      cell.value = value;
      cell.cellStyle = style;
    }

    paint(3, TextCellValue(moduleTitle)); // D ADDESTRAMENTO
    paint(6, IntCellValue(oreMod)); // G Ore Mod.
    paint(7, TextCellValue(oreTot)); // H Ore Tot. Mod.
    paint(8, TextCellValue(instructor)); // I ISTRUTTORE
    paint(10, TextCellValue(sott)); // K Sott. Mod.
    if (lesson.taskId != null) {
      paint(11, TextCellValue('${lesson.taskId}')); // L ID TASK
    } else {
      // clear + keep module color on empty task cell
      paint(11, TextCellValue(''));
    }
    paint(12, IntCellValue(subOrd)); // M Ore
  }

  static ExcelColor _excelColor(Color c) {
    final argb = (c.a * 255).round() << 24 |
        (c.r * 255).round() << 16 |
        (c.g * 255).round() << 8 |
        (c.b * 255).round();
    final hex = argb.toRadixString(16).padLeft(8, '0').toUpperCase();
    return ExcelColor.fromHexString(hex);
  }

  static void _set(Sheet sheet, int col, int rowIdx, CellValue? value) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIdx))
        .value = value;
  }

  static void _setText(Sheet sheet, int col, int rowIdx, String text) {
    _set(sheet, col, rowIdx, TextCellValue(text));
  }
}
