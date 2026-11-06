import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corsi/services/amc_docx_export.dart';

void main() {
  test('export criteri AMC: una riga per codice, celle nere sulle qualifiche', () {
    final tpl = File(AmcDocxExport.templateAsset).readAsBytesSync();
    final bytes = AmcDocxExport.buildBytes(tpl, {
      '12.2': ['b2_uc228', 'b1.3_nh90'],
      '12.3': [],
    }, {
      '12.2': ['b1.4'],
    });
    final doc = utf8.decode(ZipDecoder()
        .decodeBytes(bytes)
        .findFile('word/document.xml')!
        .content as List<int>);

    expect(doc.contains('@@'), isFalse);
    expect(RegExp(r'<w:t>12\.2</w:t>').allMatches(doc).length, 2);
    expect(RegExp(r'<w:t>12\.3</w:t>').allMatches(doc).length, 1);
    expect(RegExp('w:fill="000000"').allMatches(doc).length, 3);
    // 5 intestazione + 2 teoria + 5 intestazione + 1 pratica
    expect(RegExp('<w:tr>').allMatches(doc).length, 13);
  });
}
