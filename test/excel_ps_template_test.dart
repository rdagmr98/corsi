import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corsi/models/course_models.dart';
import 'package:corsi/models/user_models.dart';
import 'package:corsi/services/excel_export_service.dart';
import 'package:corsi/services/ps_module_style_map.dart';
import 'package:corsi/services/ps_ooxml_filler.dart';

void main() {
  test('Course.formatDurationWeeks matches 66_PS spacing', () {
    expect(Course.formatDurationWeeks(86), '86  SETTIMANE');
  });

  test('Course PS header fields round-trip JSON', () {
    final c = Course(
      id: 'x',
      courseTypeId: 'b1',
      title: '3° Corso BTC Cat.B1 2025',
      startDate: Course.btc3Start,
      endDate: Course.btc3PlannedEnd,
      status: 'active',
      durationWeeks: Course.btc3DurationWeeks,
      defaultAula: 3,
      createdBy: 't',
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    );
    final again = Course.fromJson(c.toJson());
    expect(again.startDate, DateTime(2025, 3, 10));
    expect(again.endDate, DateTime(2027, 2, 28));
    expect(again.durationWeeks, 86);
    expect(again.delayWeeks, isNull);
    expect(again.toJson()['duration_weeks'], 86);
    // Null must be serialized so updateCourse merge can clear delay_weeks.
    expect(again.toJson()['delay_weeks'], isNull);
  });

  test('OOXML fill preserves merges and header cells', () {
    final blankBytes =
        File('assets/templates/ps_weekly_blank.xlsx').readAsBytesSync();
    final blank = _SheetZip(blankBytes);

    final filler = PsOoxmlFiller(Uint8List.fromList(blankBytes));
    filler.load();
    filler.renameSheet('07.09_11.09');
    filler.setText('B5', '3° Corso BTC Cat.B1 2025');
    // Celle ufficiali header corso (stesso layout blank / 66_PS EI).
    filler.setDate('D6', DateTime(2025, 3, 10));
    filler.setDate('J6', DateTime(2027, 2, 28));
    filler.setText('D7', Course.formatDurationWeeks(86));
    filler.setDate('B10', DateTime(2026, 9, 7));
    // First teaching hour is row 11 — row 10 stays Disposizione.
    filler.paintLessonRow(
      row1Based: 11,
      moduleNumber: 15,
      addestramento: 'Modulo 15 GAS TURBINE ENGINE',
      oreMod: 66,
      oreTot: '180+50',
      instructor: 'BALLOI',
      sott: 'T15.9',
      oreSub: 4,
      localita: 'AULA 3',
    );
    // Module fill must keep BLACK text (never white), even on darker fills.
    filler.paintLessonRow(
      row1Based: 12,
      moduleNumber: 6,
      addestramento: 'Modulo 6 MATERIALS & HARDWARE',
      oreMod: 1,
      oreTot: '50+20',
      instructor: 'ROSSI',
      sott: 'T6.1',
      oreSub: 1,
      localita: 'HANGAR 6',
    );
    final long =
        'Modulo 11A Turbine Aeroplane Aerodynamics, Structures and Systems';
    expect(long.length, greaterThan(ExcelExportService.addestramentoMaxChars));
    final fitted = ExcelExportService.fitAddestramento(long);
    expect(
      fitted.length,
      lessThanOrEqualTo(ExcelExportService.addestramentoMaxChars),
    );
    expect(fitted.endsWith('...'), isTrue);
    expect(fitted.contains('Structures'), isFalse);
    filler.paintLessonRow(
      row1Based: 13,
      moduleNumber: 11,
      addestramento: fitted,
      oreMod: 1,
      oreTot: '114+30',
      instructor: 'MATERNI',
      sott: 'T11A.18',
      oreSub: 1,
      localita: 'AULA 3',
    );
    final outBytes = filler.encode();
    File('build/ps_sample_ooxml.xlsx')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(outBytes);
    File('build/ps_fidelity/ooxml_sample.xlsx')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(outBytes);

    final out = _SheetZip(outBytes);

    expect(blank.mergeCount, 158);
    expect(out.mergeCount, 158);
    expect(out.sheetName, '07.09_11.09');
    expect(out.sheet, contains('86  SETTIMANE'));
    expect(RegExp(r'<c r="D6"[^>]*>\s*<v>').hasMatch(out.sheet), isTrue);
    expect(RegExp(r'<c r="J6"[^>]*>\s*<v>').hasMatch(out.sheet), isTrue);
    expect(out.sheet, contains('Modulo 15 GAS TURBINE ENGINE'));
    expect(out.sheet, contains('3° Corso BTC Cat.B1 2025'));
    expect(out.sheet, contains(fitted));
    expect(out.sheet, isNot(contains(long)));
    expect(out.sheet, contains('s="${psModuleXf(15)}"'));
    expect(out.sheet, contains('s="${psModuleXf(6)}"'));
    // Merge slaves E/F/J must carry the same module fill (not blank 1159/1160).
    final xf15L = psModuleXfLeft(15);
    final xf15C = psModuleXfCenter(15);
    expect(RegExp('<c r="E11"[^>]*s="$xf15L"').hasMatch(out.sheet), isTrue);
    expect(RegExp('<c r="F11"[^>]*s="$xf15L"').hasMatch(out.sheet), isTrue);
    expect(RegExp('<c r="J11"[^>]*s="$xf15L"').hasMatch(out.sheet), isTrue);
    expect(RegExp('<c r="G11"[^>]*s="$xf15C"').hasMatch(out.sheet), isTrue);
    expect(RegExp('<c r="M11"[^>]*s="$xf15C"').hasMatch(out.sheet), isTrue);
    // LOCALITA' filled with style 1230 (thin borders aligned to O=1231)
    expect(out.sheet, contains('AULA 3'));
    expect(out.sheet, contains('HANGAR 6'));
    expect(
      RegExp(r'<c r="N11" s="1230" t="inlineStr"><is><t>AULA 3</t>')
          .hasMatch(out.sheet),
      isTrue,
    );
    expect(
      RegExp(r'<c r="N12" s="1230" t="inlineStr"><is><t>HANGAR 6</t>')
          .hasMatch(out.sheet),
      isTrue,
    );
    // Empty taskId → self-closing L cell (no empty <t></t>)
    expect(
      RegExp(r'<c r="L11"[^>]*/>').hasMatch(out.sheet) ||
          RegExp(r'<c r="L12"[^>]*/>').hasMatch(out.sheet),
      isTrue,
    );
    // Header chrome still present (not rewritten away)
    expect(out.sheet, contains('r="B2"'));
    expect(out.sheet, contains('r="B6"'));
    expect(out.sheet, contains('r="D15"'));
    // Disposizione (first hour) kept as shared-string cell; lunch D15 empty yellow style
    expect(
      RegExp(r'<c r="D10"[^>]*t="s"[^>]*>\s*<v>141</v>').hasMatch(blank.sheet),
      isTrue,
    );
    expect(RegExp(r'<c r="D15" s="653"/>').hasMatch(blank.sheet), isTrue);
    // Lesson paint must not land on disposizione / lunch rows in this smoke sample
    expect(RegExp(r'<c r="D10"[^>]*/>|<c r="D10"[^>]*>.*?</c>', dotAll: true)
            .firstMatch(out.sheet)!
            .group(0)!,
        isNot(contains('GAS TURBINE')));
    expect(RegExp(r'<c r="D15"[^>]*/>|<c r="D15"[^>]*>.*?</c>', dotAll: true)
            .firstMatch(out.sheet)!
            .group(0)!,
        isNot(contains('GAS TURBINE')));
    expect(out.sheet, contains('<c r="D11"'));
    expect(RegExp(r'<c r="D11"[^>]*>.*?</c>', dotAll: true)
            .firstMatch(out.sheet)!
            .group(0)!,
        contains('GAS TURBINE'));
    // Module fonts are black only (corsi-dark = FF000000; no corsi-white)
    final stylesFile = archiveFile(outBytes, 'xl/styles.xml');
    expect(stylesFile, contains('<!-- corsi-dark -->'));
    expect(
      RegExp(
        r'<!-- corsi-dark -->.*?<color rgb="FF000000"/>',
        dotAll: true,
      ).hasMatch(stylesFile),
      isTrue,
    );
    expect(stylesFile, isNot(contains('corsi-white')));
    // Print: portrait fit 1×1
    expect(out.sheet, contains('orientation="portrait"'));
    expect(out.sheet, contains('fitToWidth="1"'));
    expect(out.sheet, contains('fitToHeight="1"'));
    expect(out.sheet, contains('fitToPage="1"'));
    expect(out.sheet, isNot(contains('pageBreakPreview')));
    expect(out.sheet, isNot(contains('colBreaks')));
    expect(out.sheet, isNot(contains('r:id="')));
    expect(out.sheet, isNot(contains('conditionalFormatting')));
    expect(out.sheet, isNot(contains('1048576')));
    expect(out.sheet, contains('ref="A1:AG65"'));
    expect(
      ZipDecoder()
          .decodeBytes(outBytes)
          .files
          .any((f) => f.name.contains('printerSettings')),
      isFalse,
    );
    // sheetPr children: tabColor before pageSetUpPr (OOXML order)
    final sheetPr =
        RegExp(r'<sheetPr>.*?</sheetPr>', dotAll: true).firstMatch(out.sheet)!;
    expect(sheetPr.group(0)!.indexOf('tabColor'), lessThan(sheetPr.group(0)!.indexOf('pageSetUpPr')));
    expect(out.workbook, contains("'07.09_11.09'!\$A\$1:\$O\$70"));
  });

  test('N8 LOCALITA single col + Accountable Manager footer', () {
    final blankBytes =
        File('assets/templates/ps_weekly_blank.xlsx').readAsBytesSync();
    final blank = _SheetZip(blankBytes);
    // Official 66_PS: one merge N8:O9 → ss 678 (LOCALITA'……AULA), not dual cols
    expect(
      RegExp(r'<c r="N8"[^>]*t="s"[^>]*>\s*<v>678</v>').hasMatch(blank.sheet) ||
          RegExp(r'<c r="N8"[^>]*>\s*<v>678</v>').hasMatch(blank.sheet),
      isTrue,
      reason: 'N8 must reference shared string 678 (single LOCALITA\'/AULA column)',
    );
    expect(blank.sheet, contains('<mergeCell ref="N8:O9"/>'));
    expect(blank.sheet, isNot(contains('t="inlineStr"><is><t>LOCALITA\'</t>')));
    // Lesson rows use style 1230 (not 1278) so N:O borders match official
    expect(RegExp(r'<c r="N11" s="1230"/>').hasMatch(blank.sheet), isTrue);
    expect(RegExp(r'<c r="N10" s="1278"/>').hasMatch(blank.sheet), isTrue,
        reason: 'Disposizione keeps style 1278');
    // PERSONALE INTERESSATO chrome
    expect(blank.sheet, contains('r="B48"'));
    expect(blank.sheet, contains('r="C49"'));
    expect(blank.sheet, contains('r="J49"'));
    // Bottom-right AM intestazione (ss 672/673); I64 signature empty
    expect(
      RegExp(r'<c r="I62"[^>]*t="s"[^>]*>\s*<v>672</v>').hasMatch(blank.sheet) ||
          RegExp(r'<c r="I62"[^>]*>\s*<v>672</v>').hasMatch(blank.sheet),
      isTrue,
      reason: 'I62 must keep IL COMANDANTE (ss 672)',
    );
    expect(
      RegExp(r'<c r="I63"[^>]*t="s"[^>]*>\s*<v>673</v>').hasMatch(blank.sheet) ||
          RegExp(r'<c r="I63"[^>]*>\s*<v>673</v>').hasMatch(blank.sheet),
      isTrue,
      reason: 'I63 must keep (Accountable Manager) (ss 673)',
    );
    expect(blank.sheet, contains('<mergeCell ref="I62:N62"/>'));
    expect(blank.sheet, contains('<mergeCell ref="I63:N63"/>'));
    expect(blank.sheet, contains('<mergeCell ref="I64:N64"/>'));
    final i64 = RegExp(r'<c r="I64"[^>]*/>|<c r="I64"[^>]*>.*?</c>',
            dotAll: true)
        .firstMatch(blank.sheet)!
        .group(0)!;
    expect(i64.contains('<v>'), isFalse, reason: 'I64 name/date stays empty');
  });

  test('attendee PS label and Carabinieri split match 66_PS columns', () {
    expect(
      ExcelExportService.attendeePsLabel(
        AppUser(
          id: '1',
          nome: 'Lorenzo',
          cognome: 'Codina',
          role: 'attendee',
          titolo: 'GRD',
          forza: 'EI',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ),
      'GRD LORENZO CODINA',
    );
    // forza=CC → destra (anche senza titolo CAR.)
    expect(
      ExcelExportService.isCarabinieriAttendee(
        AppUser(
          id: '2',
          nome: 'Christian',
          cognome: 'LA RASPATA',
          role: 'attendee',
          forza: 'CC',
          titolo: 'CAR. SC',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ),
      isTrue,
    );
    // titolo CAR. alone still counts
    expect(
      ExcelExportService.isCarabinieriAttendee(
        AppUser(
          id: '2b',
          nome: 'Christian',
          cognome: 'Laraspata',
          role: 'attendee',
          titolo: 'CAR. SC',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ),
      isTrue,
    );
    expect(
      ExcelExportService.isCarabinieriAttendee(
        AppUser(
          id: '3',
          nome: 'Giuseppe',
          cognome: 'Berni',
          role: 'attendee',
          titolo: 'GRD',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ),
      isFalse,
    );
    expect(ExcelExportService.attendeeDataStartRow, 50);
  });

  test('localitaLabel teoria AULA n / pratica HANGAR 6', () {
    expect(
      ExcelExportService.localitaLabel(isTheory: true, aula: 3),
      'AULA 3',
    );
    expect(
      ExcelExportService.localitaLabel(isTheory: false, aula: 3),
      'HANGAR 6',
    );
    expect(
      ExcelExportService.localitaLabel(isTheory: true, aula: null),
      isNull,
    );
  });

  test('Mon–Thu slot→row skips Disposizione and lunch (Desktop 66_PS)', () {
    // Lun block rows 10–17: +0 Disposizione, +5 lunch.
    expect(
      ExcelExportService.excelRowForSlot(startRow: 10, endRow: 17, timeSlot: 1),
      11,
    );
    expect(
      ExcelExportService.excelRowForSlot(startRow: 10, endRow: 17, timeSlot: 4),
      14,
    );
    expect(
      ExcelExportService.excelRowForSlot(startRow: 10, endRow: 17, timeSlot: 5),
      16,
    );
    expect(
      ExcelExportService.excelRowForSlot(startRow: 10, endRow: 17, timeSlot: 6),
      17,
    );
    expect(
      ExcelExportService.excelRowForSlot(startRow: 10, endRow: 17, timeSlot: 0),
      isNull,
    );
    expect(
      ExcelExportService.excelRowForSlot(startRow: 10, endRow: 17, timeSlot: 7),
      isNull,
    );
    // Never maps onto disposizione (10) or lunch (15).
    for (final s in ExcelExportService.monThuSlotRowOffset.keys) {
      final r = ExcelExportService.excelRowForSlot(
        startRow: 10,
        endRow: 17,
        timeSlot: s,
      )!;
      expect(r, isNot(10));
      expect(r, isNot(15));
    }
    // Mar block starts at 18.
    expect(
      ExcelExportService.excelRowForSlot(startRow: 18, endRow: 25, timeSlot: 5),
      24,
    );
    // Friday contiguous.
    expect(
      ExcelExportService.excelRowForSlot(startRow: 42, endRow: 44, timeSlot: 1),
      42,
    );
    expect(
      ExcelExportService.excelRowForSlot(startRow: 42, endRow: 44, timeSlot: 3),
      44,
    );
  });
}

String archiveFile(List<int> bytes, String name) {
  final archive = ZipDecoder().decodeBytes(bytes);
  for (final f in archive.files) {
    if (f.isFile && f.name == name) {
      return utf8.decode(f.content as List<int>);
    }
  }
  throw StateError('missing $name');
}

class _SheetZip {
  _SheetZip(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final data = f.content as List<int>;
      if (f.name == 'xl/worksheets/sheet1.xml') {
        sheet = utf8.decode(data);
      } else if (f.name == 'xl/workbook.xml') {
        workbook = utf8.decode(data);
      }
    }
  }

  late final String sheet;
  late final String workbook;

  int get mergeCount => RegExp(r'<mergeCell ').allMatches(sheet).length;

  String get sheetName {
    final m = RegExp(r'name="([^"]+)"').firstMatch(workbook);
    return m?.group(1) ?? '';
  }
}
