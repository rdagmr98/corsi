import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../models/course_models.dart';
import '../models/reference_models.dart';
import '../models/schedule_models.dart';
import '../models/user_models.dart';
import '../utils/file_download.dart';

/// Export programma settimanale .xlsx allineato ai template PS (`65_` / `66_`).
/// Colonne: DATA | ORARIO | ADDESTRAMENTO | Ore Mod. | Ore Tot. Mod. |
/// ISTRUTTORE | Sott. Mod. | ID TASK | Ore | LOCALITA'
class ExcelExportService {
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
    final bytes = buildWeeklyScheduleBytes(
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

  static Uint8List buildWeeklyScheduleBytes({
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
  }) {
    final excel = Excel.createExcel();
    final defaultName = excel.getDefaultSheet() ?? excel.sheets.keys.first;
    final weekEnd = weekStart.add(const Duration(days: 4));
    final sheetName =
        '${DateFormat('dd.MM').format(weekStart)}_${DateFormat('dd.MM').format(weekEnd)}';
    excel.rename(defaultName, sheetName);
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
      final t = u.titolo?.trim();
      if (t != null && t.isNotEmpty) return '$t ${u.cognome}'.trim();
      return u.cognome.isNotEmpty ? u.cognome : u.fullName;
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

    // Progressivi corso-wide (stile Ore Mod. / Ore sottomodulo nei template)
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

    // Header istituzionale (pattern 66_PS)
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1))
        .value = TextCellValue('CENTRO ADDESTRATIVO AVIAZIONE ESERCITO');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2))
        .value = TextCellValue('REPARTO CORSI SPECIALISTICI/TERRESTRI');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 3))
        .value = TextCellValue('SEZIONE MANUTENTORI AEROMOBILI MILITARI');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 4))
        .value = TextCellValue(course.title);

    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 5))
        .value = TextCellValue('DATA INIZIO CORSO');
    if (course.startDate != null) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 5))
          .value = DateCellValue(
        year: course.startDate!.year,
        month: course.startDate!.month,
        day: course.startDate!.day,
      );
    }
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 5))
        .value = TextCellValue('DATA FINE CORSO (PIANIFICATA)');
    if (course.endDate != null) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: 5))
          .value = DateCellValue(
        year: course.endDate!.year,
        month: course.endDate!.month,
        day: course.endDate!.day,
      );
    }

    if (course.startDate != null && course.endDate != null) {
      final weeks =
          (course.endDate!.difference(course.startDate!).inDays / 7).ceil();
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 6))
          .value = TextCellValue('DURATA');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 6))
          .value = TextCellValue('$weeks  SETTIMANE');
    }

    // Intestazioni colonne — allineate a 66_PS
    const headers = <int, String>{
      1: 'DATA',
      2: 'ORARIO',
      3: 'ADDESTRAMENTO',
      6: 'Ore Mod.',
      7: 'Ore Tot. Mod.',
      8: 'ISTRUTTORE / RESPONSABILE',
      10: 'Sott. Mod.',
      11: 'ID TASK',
      12: 'Ore',
      13: "LOCALITA'",
    };
    for (final e in headers.entries) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: e.key, rowIndex: 7))
          .value = TextCellValue(e.value);
    }

    final regular = weekLessons.where((l) => l.timeSlot > 0).toList();
    final recovery = weekLessons.where((l) => l.timeSlot == 0).toList();
    final slots = typeInfo?.schedule.mondayThursday ?? const <TimeSlot>[];

    var row = 9; // Excel row 10
    for (var i = 0; i < 5; i++) {
      final day = weekStart.add(Duration(days: i));
      final daySlots =
          typeInfo?.schedule.slotsForWeekday(day.weekday) ?? slots;
      final dayStartRow = row;
      var wroteDate = false;

      for (final slot in daySlots) {
        if (day.weekday == DateTime.friday && slot.slot > 3) continue;
        final lesson = regular
            .where((l) =>
                l.date.year == day.year &&
                l.date.month == day.month &&
                l.date.day == day.day &&
                l.timeSlot == slot.slot)
            .firstOrNull;
        final note = weekNotes
            .where((n) =>
                n.date.year == day.year &&
                n.date.month == day.month &&
                n.date.day == day.day &&
                n.timeSlot == slot.slot)
            .firstOrNull;

        if (!wroteDate) {
          sheet
              .cell(CellIndex.indexByColumnRow(
                  columnIndex: 1, rowIndex: row))
              .value = DateCellValue(
            year: day.year,
            month: day.month,
            day: day.day,
          );
          wroteDate = true;
        }

        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
            .value = TextCellValue('${slot.start}-${slot.end}');

        if (lesson != null) {
          sheet
              .cell(CellIndex.indexByColumnRow(
                  columnIndex: 3, rowIndex: row))
              .value = TextCellValue(moduleTitle(lesson));
          sheet
              .cell(CellIndex.indexByColumnRow(
                  columnIndex: 6, rowIndex: row))
              .value = IntCellValue(oreModById[lesson.id] ?? 0);
          sheet
              .cell(CellIndex.indexByColumnRow(
                  columnIndex: 7, rowIndex: row))
              .value = TextCellValue(oreTotMod(lesson));
          sheet
              .cell(CellIndex.indexByColumnRow(
                  columnIndex: 8, rowIndex: row))
              .value = TextCellValue(instructorLabel(lesson));
          sheet
              .cell(CellIndex.indexByColumnRow(
                  columnIndex: 10, rowIndex: row))
              .value = TextCellValue(lesson.submoduleCode);
          if (lesson.taskId != null) {
            sheet
                .cell(CellIndex.indexByColumnRow(
                    columnIndex: 11, rowIndex: row))
                .value = TextCellValue('${lesson.taskId}');
          }
          sheet
              .cell(CellIndex.indexByColumnRow(
                  columnIndex: 12, rowIndex: row))
              .value = IntCellValue(subOrdById[lesson.id] ?? 0);
        } else if (note != null && note.text.isNotEmpty) {
          sheet
              .cell(CellIndex.indexByColumnRow(
                  columnIndex: 3, rowIndex: row))
              .value = TextCellValue(note.text);
        }
        row++;
      }

      for (final rec in recovery.where((l) =>
          l.date.year == day.year &&
          l.date.month == day.month &&
          l.date.day == day.day)) {
        if (!wroteDate) {
          sheet
              .cell(CellIndex.indexByColumnRow(
                  columnIndex: 1, rowIndex: row))
              .value = DateCellValue(
            year: day.year,
            month: day.month,
            day: day.day,
          );
          wroteDate = true;
        }
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
            .value = TextCellValue('Recupero');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
            .value = TextCellValue(moduleTitle(rec));
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row))
            .value = TextCellValue(instructorLabel(rec));
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: row))
            .value = TextCellValue(rec.submoduleCode);
        row++;
      }

      if (wroteDate && row - dayStartRow > 1) {
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: dayStartRow),
          CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row - 1),
        );
      }
    }

    row += 1;
    final directorNames = directors.map((d) {
      final t = d.titolo?.trim();
      return (t != null && t.isNotEmpty)
          ? '$t ${d.cognome} ${d.nome}'.trim()
          : d.fullName;
    }).join(' / ');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
        .value = TextCellValue(
            'Direttore del corso: ${directorNames.isEmpty ? "—" : directorNames}');

    row += 2;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
        .value = TextCellValue('PERSONALE INTERESSATO');
    row += 1;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
        .value = TextCellValue('N.');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
        .value = TextCellValue('GRADO, COGNOME e NOME');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row))
        .value = TextCellValue('N.');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: row))
        .value = TextCellValue('GRADO, COGNOME e NOME');
    row += 1;

    final sortedAtt = [...attendees]
      ..sort((a, b) => a.cognome.compareTo(b.cognome));
    final mid = (sortedAtt.length + 1) ~/ 2;
    final left = sortedAtt.take(mid).toList();
    final right = sortedAtt.skip(mid).toList();
    final maxRows =
        left.length > right.length ? left.length : right.length;
    for (var i = 0; i < maxRows; i++) {
      if (i < left.length) {
        sheet
            .cell(CellIndex.indexByColumnRow(
                columnIndex: 1, rowIndex: row + i))
            .value = IntCellValue(i + 1);
        sheet
            .cell(CellIndex.indexByColumnRow(
                columnIndex: 2, rowIndex: row + i))
            .value = TextCellValue(
                '${left[i].titolo ?? ""} ${left[i].fullName}'.trim());
      }
      if (i < right.length) {
        sheet
            .cell(CellIndex.indexByColumnRow(
                columnIndex: 8, rowIndex: row + i))
            .value = IntCellValue(mid + i + 1);
        sheet
            .cell(CellIndex.indexByColumnRow(
                columnIndex: 9, rowIndex: row + i))
            .value = TextCellValue(
                '${right[i].titolo ?? ""} ${right[i].fullName}'.trim());
      }
    }

    final encoded = excel.encode();
    if (encoded == null) {
      throw StateError('Generazione Excel fallita');
    }
    return Uint8List.fromList(encoded);
  }
}
