import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';

import '../utils/file_download.dart';

/// Tabelle criteri AMC (teoria e pratica) dell'ANNESSO MTOE-P-3-1 nel
/// formato dell'originale, da incollare nell'MTOE in caso di variazioni.
/// Template: `tools/build_amc_docx_template.py`.
class AmcDocxExport {
  static const templateAsset = 'assets/templates/amc_criteria_blank.docx';

  // Ordine colonne = intestazione fissa del template (come l'annesso).
  static const theoryCols = [
    'laurea_elettronica', 'laurea_meccanica', 'laurea_aerospaziale',
    'b1.1_uc228', 'b1.1_vc180a', 'b1.2',
    'b1.3_ah129d', 'b1.3_ch47f', 'b1.3_hh412a', 'b1.3_uh212',
    'b1.3_rh206c', 'b1.3_uh205a', 'b1.3_nh90', 'b1.3_uh169d', 'b1.4',
    'b2_uc228', 'b2_vc180a', 'b2_apr', 'b2_ah129d', 'b2_ch47f', 'b2_hh412a',
    'b2_uh212', 'b2_rh206c', 'b2_uh205a', 'b2_nh90', 'b2_uh169d',
    'sv', 'nam',
  ];
  static final practiceCols = theoryCols.sublist(3, 26);

  static const _on =
      '<w:tcBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="FFFFFF"/>'
      '<w:left w:val="single" w:sz="4" w:space="0" w:color="FFFFFF"/>'
      '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="FFFFFF"/>'
      '<w:right w:val="single" w:sz="4" w:space="0" w:color="FFFFFF"/></w:tcBorders>'
      '<w:shd w:val="clear" w:color="000000" w:fill="000000"/>';
  static const _off =
      '<w:tcBorders><w:top w:val="nil"/><w:left w:val="nil"/>'
      '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
      '<w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/></w:tcBorders>'
      '<w:shd w:val="clear" w:color="auto" w:fill="auto"/>';

  static String fillDocument(String xml, Map<String, List<String>> theory,
      Map<String, List<String>> practice) {
    xml = _fillTable(xml, '@@T_CODE@@', theoryCols, theory);
    return _fillTable(xml, '@@P_CODE@@', practiceCols, practice);
  }

  /// Sostituisce la riga prototipo con una riga per codice.
  static String _fillTable(String xml, String marker, List<String> cols,
      Map<String, List<String>> rules) {
    final at = xml.indexOf(marker);
    final start = xml.lastIndexOf('<w:tr>', at);
    final end = xml.indexOf('</w:tr>', at) + '</w:tr>'.length;
    final parts = xml.substring(start, end).split('@@B@@');
    assert(parts.length == cols.length + 1);
    final cells = [for (final p in parts.skip(1)) p.split('@@V@@')];
    const esc = HtmlEscape(HtmlEscapeMode.element);
    final buf = StringBuffer();
    for (final e in rules.entries) {
      final q = e.value.toSet();
      buf.write(parts.first.replaceFirst(marker, esc.convert(e.key)));
      for (var i = 0; i < cols.length; i++) {
        final on = q.contains(cols[i]);
        buf
          ..write(on ? _on : _off)
          ..write(cells[i][0])
          ..write(on ? '1' : ' ')
          ..write(cells[i][1]);
      }
    }
    return xml.replaceRange(start, end, buf.toString());
  }

  static Uint8List buildBytes(Uint8List template,
      Map<String, List<String>> theory, Map<String, List<String>> practice) {
    final out = Archive();
    for (final f in ZipDecoder().decodeBytes(template).files) {
      if (!f.isFile) continue;
      var content = f.content as List<int>;
      if (f.name == 'word/document.xml') {
        content = utf8.encode(fillDocument(utf8.decode(content), theory, practice));
      }
      out.addFile(ArchiveFile(f.name, content.length, content));
    }
    return Uint8List.fromList(ZipEncoder().encode(out)!);
  }

  static Future<void> download(Map<String, List<String>> theory,
      Map<String, List<String>> practice) async {
    final tpl = (await rootBundle.load(templateAsset)).buffer.asUint8List();
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await downloadBytes(
      buildBytes(tpl, theory, practice),
      'Annesso_MTOE-P-3-1_criteri_AMC_$date.docx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    );
  }
}
