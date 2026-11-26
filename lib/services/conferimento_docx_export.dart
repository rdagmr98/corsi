import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';

import '../models/user_models.dart';
import '../utils/file_download.dart';

/// Dati necessari per generare il conferimento di un istruttore.
class ConferimentoData {
  final String? grado;
  final String nome;
  final String cognome;
  final String? mamlNumber;
  final List<String>? qualifications;
  final List<String> theoryCodes;
  final List<String> practiceCodes;

  const ConferimentoData({
    this.grado,
    required this.nome,
    required this.cognome,
    this.mamlNumber,
    this.qualifications,
    required this.theoryCodes,
    required this.practiceCodes,
  });

  factory ConferimentoData.fromUser(
    AppUser user, {
    required Map<String, List<String>> theoryGrid,
    required Map<String, List<String>> practiceGrid,
  }) =>
      ConferimentoData(
        grado: user.grado,
        nome: user.nome,
        cognome: user.cognome,
        mamlNumber: user.mamlNumber,
        qualifications: user.qualifications,
        theoryCodes: [
          for (final e in theoryGrid.entries)
            if (e.value.contains(user.id)) e.key,
        ],
        practiceCodes: [
          for (final e in practiceGrid.entries)
            if (e.value.contains(user.id)) e.key,
        ],
      );
}

/// Export Word del conferimento dell'abilitazione all'insegnamento (MTOE-F-3-4):
/// uno o più istruttori in un unico .docx, uno per pagina.
/// Template: `tools/build_conferimento_template.py`.
class ConferimentoDocxExport {
  static const templateAsset = 'assets/templates/conferimento_blank.docx';
  static const _docxMime =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  static const _pageBreak = '<w:p><w:r><w:br w:type="page"/></w:r></w:p>';
  static const _esc = HtmlEscape(HtmlEscapeMode.element);
  static const _fontRpr =
      '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>';
  static const _tblBorders =
      '<w:tblBorders>'
      '<w:top w:val="single" w:sz="4" w:space="0" w:color="000000"/>'
      '<w:left w:val="single" w:sz="4" w:space="0" w:color="000000"/>'
      '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="000000"/>'
      '<w:right w:val="single" w:sz="4" w:space="0" w:color="000000"/>'
      '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="000000"/>'
      '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="000000"/>'
      '</w:tblBorders>';

  static const Map<String, String> _moduleNames = {
    '1': 'Mathematics',
    '2': 'Physics',
    '3': 'Electrical Fundamentals',
    '4': 'Electronic Fundamentals',
    '5': 'Digital Technique/Electronic Instrument System',
    '6': 'Materials And Hardware',
    '7': 'Maintenance Practices',
    '8': 'Basic Aerodynamics',
    '9': 'Human Factor',
    '10': 'Aviation Legislation',
    '11A': 'Turbine Aeroplane Aerodynamics, Structures and Systems',
    '11B': 'Piston Aeroplane Aerodynamics, Structures and Systems',
    '12': 'Helicopter Aerodynamics, Structure and Systems',
    '13': 'Aircraft Aerodynamics, Structures and Systems',
    '14': 'Propulsion',
    '15': 'Gas Turbine Engine',
    '16': 'Piston Engine',
    '17': 'Propeller',
    '50': 'Principles of Armament',
    '51': 'Weapons Systems',
    '53': 'Surveillance and Electronic Warfare',
    '54': 'Crew Safety',
    '55': 'Military Communication Systems',
  };

  static const List<String> theoryModules = [
    '1', '2', '3', '4', '5', '6', '7', '8', '9', '10',
    '11A', '11B', '12', '13', '14', '15', '16', '17',
    '50', '51', '53', '54', '55',
  ];

  static const List<String> practiceModules = [
    '3', '4', '5', '7',
    '11A', '11B', '12', '13', '14', '15', '16', '17',
    '50', '51', '53', '54', '55',
  ];

  /// Ordinamento numerico corretto: 1.1 < 1.2 < ... < 5.4 < 5.12 < 11A.1 < 11B.1 < 12.1.
  static int compareCode(String a, String b) {
    final pa = _parseCode(a);
    final pb = _parseCode(b);
    if (pa.$1 != pb.$1) return pa.$1.compareTo(pb.$1);
    if (pa.$2 != pb.$2) return pa.$2.compareTo(pb.$2);
    if (pa.$3 != pb.$3) return pa.$3.compareTo(pb.$3);
    return a.compareTo(b);
  }

  static (int, String, int) _parseCode(String code) {
    final parts = code.split('.');
    final m = RegExp(r'^(\d+)([A-Za-z]?)$').firstMatch(parts[0].trim());
    return (
      m != null ? (int.tryParse(m.group(1)!) ?? 0) : 0,
      m?.group(2)?.toUpperCase() ?? '',
      parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 0) : 0,
    );
  }

  static String formatName(ConferimentoData d) {
    final parts = <String>[
      if ((d.grado ?? '').trim().isNotEmpty) d.grado!.trim(),
      if (d.nome.trim().isNotEmpty) d.nome.trim(),
      if (d.cognome.trim().isNotEmpty) d.cognome.trim().toUpperCase(),
    ];
    return parts.join(' ');
  }

  static String formatQualifica(List<String>? qualifications) {
    final q = {
      for (final s in qualifications ?? const <String>[])
        if (s.trim().isNotEmpty) s.trim().toLowerCase(),
    };
    if (q.length == 1 && q.contains('sv')) return '"Istruttore SV"';
    const base =
        '"Tecnico Istruttore militare di materie tecnico aeronautiche (TI)"';
    return q.contains('nam') ? '$base e Istruttore NAM' : base;
  }

  static String formatMaml(String? mamlNumber) {
    final m = (mamlNumber ?? '').trim();
    return m.isNotEmpty ? ', possessore della MAML No.$m' : '';
  }

  static int _usableWidth(String sectPr) {
    final pgSz = RegExp(r'<w:pgSz\b[^>]*\bw:w="(\d+)"').firstMatch(sectPr);
    final pgMar =
        RegExp(r'<w:pgMar\b[^>]*/>').firstMatch(sectPr)?.group(0) ?? '';
    final left = RegExp(r'\bw:left="(\d+)"').firstMatch(pgMar);
    final right = RegExp(r'\bw:right="(\d+)"').firstMatch(pgMar);
    if (pgSz != null && left != null && right != null) {
      final w = int.parse(pgSz.group(1)!) -
          int.parse(left.group(1)!) -
          int.parse(right.group(1)!);
      if (w > 0) return w;
    }
    return 9638;
  }

  static String _buildTable(
    String title,
    List<String> fixedModules,
    List<String> codes,
    int tableW,
  ) {
    final fixedSet = fixedModules.toSet();
    final byMod = <String, Set<String>>{};
    for (final raw in codes) {
      final c = raw.trim();
      if (c.isEmpty) continue;
      final mod = c.split('.').first.trim().toUpperCase();
      if (mod.isEmpty) continue;
      byMod.putIfAbsent(mod, () => <String>{}).add(c);
    }

    final modules = {...fixedModules, ...byMod.keys}.toList()
      ..sort(compareCode);

    final col1W = tableW ~/ 2;
    final col2W = tableW - col1W;

    final buf = StringBuffer()
      ..write('<w:tbl><w:tblPr>')
      ..write('<w:tblW w:w="$tableW" w:type="dxa"/>')
      ..write('<w:jc w:val="center"/>')
      ..write(_tblBorders)
      ..write('<w:tblLayout w:type="fixed"/>')
      ..write(
          '<w:tblCellMar><w:top w:w="20" w:type="dxa"/><w:left w:w="80" w:type="dxa"/>'
          '<w:bottom w:w="20" w:type="dxa"/><w:right w:w="80" w:type="dxa"/></w:tblCellMar>')
      ..write('</w:tblPr>')
      ..write(
          '<w:tblGrid><w:gridCol w:w="$col1W"/><w:gridCol w:w="$col2W"/></w:tblGrid>')
      // Riga intestazione unita e centrata
      ..write(
          '<w:tr><w:trPr><w:cantSplit/><w:tblHeader/></w:trPr>'
          '<w:tc><w:tcPr><w:tcW w:w="$tableW" w:type="dxa"/><w:gridSpan w:val="2"/>'
          '<w:vAlign w:val="center"/></w:tcPr>'
          '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>'
          '<w:jc w:val="center"/></w:pPr>'
          '<w:r><w:rPr>$_fontRpr<w:b/><w:bCs/><w:sz w:val="16"/><w:szCs w:val="16"/></w:rPr>'
          '<w:t>${_esc.convert(title)}</w:t></w:r></w:p></w:tc></w:tr>');

    for (final mod in modules) {
      final modName = fixedSet.contains(mod) ? _moduleNames[mod] : null;
      final label = modName != null ? 'MODULE $mod $modName' : 'MODULE $mod';
      final modCodes = byMod[mod]?.toList();
      modCodes?.sort(compareCode);
      final codesText = (modCodes == null || modCodes.isEmpty)
          ? ''
          : '${modCodes.join(', ')}.';

      buf
        ..write('<w:tr><w:trPr><w:cantSplit/></w:trPr>')
        ..write(
            '<w:tc><w:tcPr><w:tcW w:w="$col1W" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>'
            '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>'
            '<w:r><w:rPr>$_fontRpr<w:i/><w:iCs/><w:sz w:val="16"/><w:szCs w:val="16"/></w:rPr>'
            '<w:t>${_esc.convert(label)}</w:t></w:r></w:p></w:tc>')
        ..write(
            '<w:tc><w:tcPr><w:tcW w:w="$col2W" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>'
            // rPr del segno di paragrafo a 8pt: la cella vuota non alza la riga
            '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>'
            '<w:rPr>$_fontRpr<w:sz w:val="16"/><w:szCs w:val="16"/></w:rPr></w:pPr>');
      if (codesText.isNotEmpty) {
        buf.write(
            '<w:r><w:rPr>$_fontRpr<w:sz w:val="16"/><w:szCs w:val="16"/></w:rPr>'
            '<w:t>${_esc.convert(codesText)}</w:t></w:r>');
      }
      buf.write('</w:p></w:tc></w:tr>');
    }
    buf.write('</w:tbl>');
    return buf.toString();
  }

  static String _buildCampo(ConferimentoData d, int tableW) {
    final theory =
        _buildTable('Theoretical element', theoryModules, d.theoryCodes, tableW);
    final gap =
        '<w:p><w:pPr><w:spacing w:before="0" w:after="120"/>'
        '<w:rPr>$_fontRpr<w:sz w:val="16"/><w:szCs w:val="16"/></w:rPr></w:pPr></w:p>';
    final practice = _buildTable(
        'Practical element', practiceModules, d.practiceCodes, tableW);
    return '$theory$gap$practice';
  }

  static String _replaceCampoParagraph(String body, String replacement) {
    final at = body.indexOf('@@CAMPO@@');
    if (at < 0) return body;
    final opens = RegExp(r'<w:p(?:>| )').allMatches(body.substring(0, at));
    if (opens.isEmpty) return body;
    final pStart = opens.last.start;
    final pEnd = body.indexOf('</w:p>', at) + '</w:p>'.length;
    return body.replaceRange(pStart, pEnd, replacement);
  }

  /// Compila `word/document.xml` ripetendo il corpo per ogni istruttore
  /// separato da un page break e rinumerando gli id `wp:docPr`/`pic:cNvPr`.
  static String fillDocument(
    String xml,
    List<ConferimentoData> items, {
    bool restartNumbering = false,
    String decorrenza = '',
  }) {
    if (items.isEmpty) {
      throw ArgumentError('Serve almeno un istruttore per generare il conferimento.');
    }
    final bodyOpen = xml.indexOf('<w:body>');
    final bodyStart = bodyOpen + '<w:body>'.length;
    final sectStart = xml.lastIndexOf('<w:sectPr');
    final prefix = xml.substring(0, bodyStart);
    final bodyTpl = xml.substring(bodyStart, sectStart);
    final suffix = xml.substring(sectStart);
    final tableW = _usableWidth(suffix);

    final pages = <String>[];
    for (var i = 0; i < items.length; i++) {
      final d = items[i];
      var b = bodyTpl
          .replaceAll('@@NOME@@', _esc.convert(formatName(d)))
          .replaceAll('@@QUALIFICA@@', _esc.convert(formatQualifica(d.qualifications)))
          .replaceAll('@@MAML@@', _esc.convert(formatMaml(d.mamlNumber)))
          .replaceAll('@@DECORRENZA@@', _esc.convert(decorrenza));
      b = _replaceCampoParagraph(b, _buildCampo(d, tableW));
      if (restartNumbering && i > 0) {
        b = b.replaceAll('<w:numId w:val="2"/>', '<w:numId w:val="${100 + i}"/>');
      }
      pages.add(b);
    }

    var combined = pages.join(_pageBreak);
    var docPrId = 10;
    combined = combined.replaceAllMapped(
      RegExp(r'(<wp:docPr\b[^>]*\bid=")\d+(")'),
      (m) => '${m.group(1)}${docPrId++}${m.group(2)}',
    );
    var cNvPrId = 10;
    combined = combined.replaceAllMapped(
      RegExp(r'(<pic:cNvPr\b[^>]*\bid=")\d+(")'),
      (m) => '${m.group(1)}${cNvPrId++}${m.group(2)}',
    );
    return '$prefix$combined$suffix';
  }

  static Uint8List buildBytes(
    Uint8List template,
    List<ConferimentoData> items, {
    String decorrenza = '',
  }) {
    if (items.isEmpty) {
      throw ArgumentError('Serve almeno un istruttore per generare il conferimento.');
    }
    final archive = ZipDecoder().decodeBytes(template);
    final numFile = archive.findFile('word/numbering.xml');
    final numXml =
        numFile != null ? utf8.decode(numFile.content as List<int>) : null;
    final canRestartNum = items.length > 1 &&
        numXml != null &&
        numXml.contains('w:abstractNumId="1"') &&
        numXml.contains('</w:numbering>');

    final out = Archive();
    for (final f in archive.files) {
      if (!f.isFile) continue;
      var content = f.content as List<int>;
      if (f.name == 'word/document.xml') {
        content = utf8.encode(fillDocument(
          utf8.decode(content),
          items,
          restartNumbering: canRestartNum,
          decorrenza: decorrenza,
        ));
      } else if (f.name == 'word/numbering.xml' && canRestartNum) {
        final extraNums = StringBuffer();
        for (var i = 1; i < items.length; i++) {
          extraNums.write(
              '<w:num w:numId="${100 + i}"><w:abstractNumId w:val="1"/>'
              '<w:lvlOverride w:ilvl="0"><w:startOverride w:val="1"/></w:lvlOverride>'
              '</w:num>');
        }
        content = utf8.encode(
            numXml.replaceFirst('</w:numbering>', '$extraNums</w:numbering>'));
      }
      out.addFile(ArchiveFile(f.name, content.length, content));
    }
    return Uint8List.fromList(ZipEncoder().encode(out)!);
  }

  static String fileName(List<ConferimentoData> items, {DateTime? now}) {
    final date = DateFormat('yyyy-MM-dd').format(now ?? DateTime.now());
    if (items.length == 1) {
      final safe = items.first.cognome
          .trim()
          .toUpperCase()
          .replaceAll(RegExp(r'[^\w-]+', unicode: true), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      final surname = safe.isEmpty ? 'ISTRUTTORE' : safe;
      return 'Conferimento_${surname}_$date.docx';
    }
    return 'Conferimenti_istruttori_$date.docx';
  }

  static Future<void> download(List<ConferimentoData> items,
      {String decorrenza = ''}) async {
    final tpl = (await rootBundle.load(templateAsset)).buffer.asUint8List();
    await downloadBytes(
      buildBytes(tpl, items, decorrenza: decorrenza),
      fileName(items),
      mimeType: _docxMime,
    );
  }
}
