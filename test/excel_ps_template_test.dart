import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corsi/services/ps_module_style_map.dart';
import 'package:corsi/services/ps_ooxml_filler.dart';

void main() {
  test('OOXML fill preserves merges and header cells', () {
    final blankBytes =
        File('assets/templates/ps_weekly_blank.xlsx').readAsBytesSync();
    final blank = _SheetZip(blankBytes);

    final filler = PsOoxmlFiller(Uint8List.fromList(blankBytes));
    filler.load();
    filler.renameSheet('07.09_11.09');
    filler.setText('B5', '3° Corso BTC Cat.B1 2025');
    filler.setDate('B10', DateTime(2026, 9, 7));
    filler.paintLessonRow(
      row1Based: 11,
      moduleNumber: 15,
      addestramento: 'Modulo 15 GAS TURBINE ENGINE',
      oreMod: 66,
      oreTot: '180+50',
      instructor: 'BALLOI',
      sott: 'T15.9',
      oreSub: 4,
    );
    // Light fill module — must use dark text xf (contrast)
    filler.paintLessonRow(
      row1Based: 12,
      moduleNumber: 6,
      addestramento: 'Modulo 6 MATERIALS & HARDWARE',
      oreMod: 1,
      oreTot: '50+20',
      instructor: 'ROSSI',
      sott: 'T6.1',
      oreSub: 1,
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
    expect(out.sheet, contains('Modulo 15 GAS TURBINE ENGINE'));
    expect(out.sheet, contains('3° Corso BTC Cat.B1 2025'));
    expect(out.sheet, contains('s="${psModuleXf(15)}"'));
    expect(out.sheet, contains('s="${psModuleXf(6)}"'));
    // Header chrome still present (not rewritten away)
    expect(out.sheet, contains('r="B2"'));
    expect(out.sheet, contains('r="B6"'));
    expect(out.sheet, contains('r="D15"'));
    // Print: landscape fit 1×1
    expect(out.sheet, contains('orientation="landscape"'));
    expect(out.sheet, contains('fitToWidth="1"'));
    expect(out.sheet, contains('fitToHeight="1"'));
    expect(out.sheet, contains('fitToPage="1"'));
    expect(out.workbook, contains("'07.09_11.09'!\$A\$1:\$O\$70"));
  });
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
