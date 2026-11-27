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

  /// [theoryCodes]/[practiceCodes] = materie ASSEGNATE dall'AM, sottoinsieme
  /// di quelle insegnabili ([teachable] sulle griglie AMC).
  factory ConferimentoData.fromUser(
    AppUser user, {
    required List<String> theoryCodes,
    required List<String> practiceCodes,
  }) =>
      ConferimentoData(
        grado: user.grado,
        nome: user.nome,
        cognome: user.cognome,
        mamlNumber: user.mamlNumber,
        qualifications: user.qualifications,
        theoryCodes: theoryCodes,
        practiceCodes: practiceCodes,
      );

  /// Codici della griglia AMC che [uid] può insegnare, ordinati.
  static List<String> teachable(Map<String, List<String>> grid, String uid) =>
      [
        for (final e in grid.entries)
          if (e.value.contains(uid)) e.key,
      ]..sort(ConferimentoDocxExport.compareCode);
}

/// Export Word del modulo MTOE-F-3-4 «Atto di conferimento dell'abilitazione
/// all'insegnamento»: uno o più istruttori in un unico .docx, uno per pagina.
/// Template: `tools/build_conferimento_template.py`.
class ConferimentoDocxExport {
  static const templateAsset = 'assets/templates/conferimento_blank.docx';
  static const defaultTm = 'IL TRAINING MANAGER';
  static const defaultAm = "L'ACCOUNTABLE MANAGER";
  static const _docxMime =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  static const _pageBreak = '<w:p><w:r><w:br w:type="page"/></w:r></w:p>';
  static const _esc = HtmlEscape(HtmlEscapeMode.element);
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

  /// «Nome COGNOME» (il grado ha un campo suo nel modulo).
  static String formatName(ConferimentoData d) => [
        if (d.nome.trim().isNotEmpty) d.nome.trim(),
        if (d.cognome.trim().isNotEmpty) d.cognome.trim().toUpperCase(),
      ].join(' ');

  static String formatQualifica(List<String>? qualifications) {
    final q = {
      for (final s in qualifications ?? const <String>[])
        if (s.trim().isNotEmpty) s.trim().toLowerCase(),
    };
    if (q.length == 1 && q.contains('sv')) return 'Istruttore SV';
    const base =
        'Tecnico Istruttore militare di materie tecnico aeronautiche (TI)';
    return q.contains('nam') ? '$base e Istruttore NAM' : base;
  }

  static String _orDash(String? s) =>
      (s ?? '').trim().isEmpty ? '—' : s!.trim();

  /// Gruppo firma su più righe dentro un unico `<w:t>` del template.
  static String _multiline(String text) => text
      .trim()
      .split('\n')
      .map((l) => _esc.convert(l.trim()))
      .join('</w:t><w:br/><w:t xml:space="preserve">');

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

  static String _cell(int w, String text,
      {bool bold = false, bool italic = false, String? fill, int span = 1}) {
    final rpr = '<w:rPr>${bold ? '<w:b/>' : ''}${italic ? '<w:i/>' : ''}'
        '<w:sz w:val="17"/><w:szCs w:val="17"/></w:rPr>';
    return '<w:tc><w:tcPr><w:tcW w:w="$w" w:type="dxa"/>'
        '${span > 1 ? '<w:gridSpan w:val="$span"/>' : ''}'
        '${fill != null ? '<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>' : ''}'
        '<w:vAlign w:val="center"/></w:tcPr>'
        '<w:p><w:pPr>${span > 1 ? '<w:jc w:val="center"/>' : ''}$rpr</w:pPr>'
        '${text.isEmpty ? '' : '<w:r>$rpr<w:t xml:space="preserve">${_esc.convert(text)}</w:t></w:r>'}'
        '</w:p></w:tc>';
  }

  /// Tabella dei soli moduli assegnati: «MODULE N Nome» | codici.
  /// Colonne 7/17 e 10/17 come `COL_CAMPO` del builder.
  static String _buildTable(String title, List<String> codes, int tableW) {
    final byMod = <String, List<String>>{};
    for (final raw in codes) {
      final c = raw.trim();
      if (c.isEmpty) continue;
      byMod.putIfAbsent(c.split('.').first.toUpperCase(), () => []).add(c);
    }
    final modules = byMod.keys.toList()..sort(compareCode);
    final c1 = tableW * 7 ~/ 17;
    final c2 = tableW - c1;

    final buf = StringBuffer()
      ..write('<w:tbl><w:tblPr><w:tblW w:w="$tableW" w:type="dxa"/>'
          '<w:jc w:val="center"/>$_tblBorders<w:tblLayout w:type="fixed"/>'
          '<w:tblCellMar><w:top w:w="15" w:type="dxa"/><w:left w:w="80" w:type="dxa"/>'
          '<w:bottom w:w="15" w:type="dxa"/><w:right w:w="80" w:type="dxa"/></w:tblCellMar>'
          '</w:tblPr><w:tblGrid><w:gridCol w:w="$c1"/><w:gridCol w:w="$c2"/></w:tblGrid>')
      ..write('<w:tr><w:trPr><w:cantSplit/><w:tblHeader/></w:trPr>'
          '${_cell(tableW, title, bold: true, span: 2)}</w:tr>')
      ..write('<w:tr><w:trPr><w:cantSplit/><w:tblHeader/></w:trPr>'
          '${_cell(c1, 'Modulo', italic: true, fill: 'EDEFF3')}'
          '${_cell(c2, 'Sottomoduli', italic: true, fill: 'EDEFF3')}</w:tr>');
    if (modules.isEmpty) {
      buf.write('<w:tr>${_cell(c1, '—')}${_cell(c2, '')}</w:tr>');
    }
    for (final mod in modules) {
      final name = _moduleNames[mod];
      final list = byMod[mod]!..sort(compareCode);
      buf.write('<w:tr><w:trPr><w:cantSplit/></w:trPr>'
          '${_cell(c1, name != null ? 'MODULE $mod $name' : 'MODULE $mod', italic: true)}'
          '${_cell(c2, '${list.join(', ')}.')}</w:tr>');
    }
    buf.write('</w:tbl>');
    return buf.toString();
  }

  static String _buildCampo(ConferimentoData d, int tableW) {
    const gap = '<w:p><w:pPr><w:spacing w:after="80"/>'
        '<w:rPr><w:sz w:val="8"/></w:rPr></w:pPr></w:p>';
    return _buildTable('Theoretical element', d.theoryCodes, tableW) +
        gap +
        _buildTable('Practical element', d.practiceCodes, tableW);
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

  /// Compila `word/document.xml` ripetendo il corpo per ogni istruttore,
  /// separato da un page break (il corpo non ha immagini: lo stemma è nell'header).
  static String fillDocument(
    String xml,
    List<ConferimentoData> items, {
    String decorrenza = '',
    String firmaTm = '',
    String firmaAm = '',
  }) {
    if (items.isEmpty) {
      throw ArgumentError('Serve almeno un istruttore per generare il conferimento.');
    }
    final bodyStart = xml.indexOf('<w:body>') + '<w:body>'.length;
    final sectStart = xml.lastIndexOf('<w:sectPr');
    final bodyTpl = xml.substring(bodyStart, sectStart);
    final suffix = xml.substring(sectStart);
    final tableW = _usableWidth(suffix);
    final tm = _multiline(firmaTm.trim().isEmpty ? defaultTm : firmaTm);
    final am = _multiline(firmaAm.trim().isEmpty ? defaultAm : firmaAm);

    final pages = [
      for (final d in items)
        _replaceCampoParagraph(
          bodyTpl
              .replaceAll('@@GRADO@@', _esc.convert(_orDash(d.grado)))
              .replaceAll('@@NOME@@', _esc.convert(formatName(d)))
              .replaceAll('@@QUALIFICA@@', _esc.convert(formatQualifica(d.qualifications)))
              .replaceAll('@@MAML@@', _esc.convert(_orDash(d.mamlNumber)))
              .replaceAll('@@DECORRENZA@@', _esc.convert(decorrenza))
              .replaceAll('@@TM@@', tm)
              .replaceAll('@@AM@@', am),
          _buildCampo(d, tableW),
        ),
    ];
    return '${xml.substring(0, bodyStart)}${pages.join(_pageBreak)}$suffix';
  }

  static Uint8List buildBytes(
    Uint8List template,
    List<ConferimentoData> items, {
    String decorrenza = '',
    String firmaTm = '',
    String firmaAm = '',
  }) {
    final archive = ZipDecoder().decodeBytes(template);
    final out = Archive();
    for (final f in archive.files) {
      if (!f.isFile) continue;
      var content = f.content as List<int>;
      if (f.name == 'word/document.xml') {
        content = utf8.encode(fillDocument(utf8.decode(content), items,
            decorrenza: decorrenza, firmaTm: firmaTm, firmaAm: firmaAm));
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
      {String decorrenza = '', String firmaTm = '', String firmaAm = ''}) async {
    final tpl = (await rootBundle.load(templateAsset)).buffer.asUint8List();
    await downloadBytes(
      buildBytes(tpl, items,
          decorrenza: decorrenza, firmaTm: firmaTm, firmaAm: firmaAm),
      fileName(items),
      mimeType: _docxMime,
    );
  }
}
