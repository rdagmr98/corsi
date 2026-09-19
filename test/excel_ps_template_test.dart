import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PS blank template roundtrip preserves merges', () async {
    final bytes = await File('assets/templates/ps_weekly_blank.xlsx').readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    expect(excel.sheets.containsKey('Settimana'), isTrue);
    final sheet = excel['Settimana'];

    // Write a sample lesson like production
    final style = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('FF6366F1'),
      fontColorHex: ExcelColor.white,
      fontSize: 9,
      bold: true,
    );
    void paint(int col, int row, CellValue v) {
      final c = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
      c.value = v;
      c.cellStyle = style;
    }

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 4)).value =
        TextCellValue('TEST CORSO BTC');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 9)).value =
        DateCellValue(year: 2026, month: 9, day: 7);
    paint(3, 10, TextCellValue('Modulo 15 GAS TURBINE ENGINE'));
    paint(6, 10, IntCellValue(66));
    paint(7, 10, TextCellValue('180+50'));
    paint(8, 10, TextCellValue('BALLOI'));
    paint(10, 10, TextCellValue('T15.9'));
    paint(12, 10, IntCellValue(4));

    final out = excel.encode();
    expect(out, isNotNull);
    final outFile = File('build/ps_weekly_roundtrip_test.xlsx');
    outFile.parent.createSync(recursive: true);
    await outFile.writeAsBytes(Uint8List.fromList(out!));

    final again = Excel.decodeBytes(out);
    final s2 = again.tables.values.first;
    expect(s2.cell(CellIndex.indexByString('D11')).value.toString(),
        contains('Modulo 15'));
    // spans / merges present
    expect(s2.spannedItems.isNotEmpty, isTrue);
  });
}
