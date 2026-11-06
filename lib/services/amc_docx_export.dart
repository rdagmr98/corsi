import 'dart:convert';
import 'dart:math';
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

  // ── Elenco personale (T1 teoria, T2 pratica): sottomodulo × istruttore ──
  static const personnelAsset = 'assets/templates/amc_personnel_blank.docx';
  static const _maxTableW = 9320, _maxColW = 422; // twip, come l'annesso
  static const _pb =
      '<w:tcBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
      '<w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
      '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
      '<w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/></w:tcBorders>';

  /// [theory]/[practice]: codice → id istruttori abilitati, nell'ordine
  /// delle righe. [labels]: id → «Cognome Nome (sigle)».
  static String fillPersonnel(String xml, Map<String, List<String>> theory,
      Map<String, List<String>> practice, Map<String, String> labels) {
    xml = _fillPersonnelTable(xml, '@@T_CODE@@', theory, labels);
    return _fillPersonnelTable(xml, '@@P_CODE@@', practice, labels);
  }

  static String _fillPersonnelTable(String xml, String marker,
      Map<String, List<String>> grid, Map<String, String> labels) {
    const esc = HtmlEscape(HtmlEscapeMode.element);
    final at = xml.indexOf(marker);
    final ts = xml.lastIndexOf('<w:tbl>', at);
    final te = xml.indexOf('</w:tbl>', at);
    var t = xml.substring(ts, te);

    String label(String uid) => labels[uid] ?? uid;
    final cols = {for (final v in grid.values) ...v}.toList()
      ..sort((a, b) => label(a).toLowerCase().compareTo(label(b).toLowerCase()));
    final codeW = int.parse(
        RegExp(r'<w:gridCol w:w="(\d+)"/>@@GRID@@').firstMatch(t)!.group(1)!);
    final w = cols.isEmpty
        ? _maxColW
        : min(_maxColW, (_maxTableW - codeW) ~/ cols.length);
    // Il nome ruotato occupa una riga larga quanto la colonna.
    final sz = min(22, w ~/ 13);
    t = t
        .replaceFirst('@@TW@@', '${codeW + w * cols.length}')
        .replaceFirst('@@GRID@@', '<w:gridCol w:w="$w"/>' * cols.length)
        .replaceAll('@@W@@', '$w');

    // (prima, cella che contiene m, dopo)
    (String, String, String) cell(String s, String m) {
      final i = s.indexOf(m);
      final a = s.lastIndexOf('<w:tc>', i);
      final b = s.indexOf('</w:tc>', i) + '</w:tc>'.length;
      return (s.substring(0, a), s.substring(a, b), s.substring(b));
    }

    final (h0, hc, h1) = cell(t, '@@NAME@@');
    final head = hc.replaceAll('@@SZ@@', '$sz');
    t = h0 +
        cols.map((u) => head.replaceFirst('@@NAME@@', esc.convert(label(u)))).join() +
        h1;

    final rs = t.lastIndexOf('<w:tr>', t.indexOf(marker));
    final re = t.indexOf('</w:tr>', rs) + '</w:tr>'.length;
    final (r0, dc, r1) = cell(t.substring(rs, re), '@@V@@');
    final [d0, d1] = dc.split('@@B@@');
    final [v0, v1] = d1.split('@@V@@');
    final buf = StringBuffer();
    for (final e in grid.entries) {
      final on = e.value.toSet();
      buf.write(r0.replaceFirst(marker, esc.convert(e.key)));
      for (final u in cols) {
        final yes = on.contains(u);
        buf.write('$d0$_pb<w:shd w:val="clear" w:color="auto" '
            'w:fill="${yes ? '000000' : 'auto'}"/>$v0${yes ? '1' : ' '}$v1');
      }
      buf.write(r1);
    }
    t = t.replaceRange(rs, re, buf.toString());
    return xml.replaceRange(ts, te, t);
  }

  static Uint8List _rezip(Uint8List template, String Function(String) fill) {
    final out = Archive();
    for (final f in ZipDecoder().decodeBytes(template).files) {
      if (!f.isFile) continue;
      var content = f.content as List<int>;
      if (f.name == 'word/document.xml') {
        content = utf8.encode(fill(utf8.decode(content)));
      }
      out.addFile(ArchiveFile(f.name, content.length, content));
    }
    return Uint8List.fromList(ZipEncoder().encode(out)!);
  }

  static Uint8List buildBytes(Uint8List template,
          Map<String, List<String>> theory, Map<String, List<String>> practice) =>
      _rezip(template, (x) => fillDocument(x, theory, practice));

  static Uint8List buildPersonnelBytes(
          Uint8List template,
          Map<String, List<String>> theory,
          Map<String, List<String>> practice,
          Map<String, String> labels) =>
      _rezip(template, (x) => fillPersonnel(x, theory, practice, labels));

  static const _docxMime =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

  static Future<void> download(Map<String, List<String>> theory,
      Map<String, List<String>> practice) async {
    final tpl = (await rootBundle.load(templateAsset)).buffer.asUint8List();
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await downloadBytes(buildBytes(tpl, theory, practice),
        'Annesso_MTOE-P-3-1_criteri_AMC_$date.docx',
        mimeType: _docxMime);
  }

  static Future<void> downloadPersonnel(Map<String, List<String>> theory,
      Map<String, List<String>> practice, Map<String, String> labels) async {
    final tpl = (await rootBundle.load(personnelAsset)).buffer.asUint8List();
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await downloadBytes(buildPersonnelBytes(tpl, theory, practice, labels),
        'Annesso_MTOE-P-3-1_elenco_personale_$date.docx',
        mimeType: _docxMime);
  }
}
