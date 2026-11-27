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

  // Colori e colonne uguali a tools/build_conferimento_template.py.
  static const _blu = '1F3A68';
  static const _chiaro = 'E6EAF1';
  static const _linea = 'A9B4C6';

  static String _rpr(int halfPt,
          {bool bold = false, bool italic = false, String? color, String extra = ''}) =>
      '<w:rPr>${bold ? '<w:b/>' : ''}${italic ? '<w:i/>' : ''}'
      '${color != null ? '<w:color w:val="$color"/>' : ''}'
      '<w:sz w:val="$halfPt"/><w:szCs w:val="$halfPt"/>$extra</w:rPr>';

  static String _run(String text, String rpr) =>
      '<w:r>$rpr<w:t xml:space="preserve">${_esc.convert(text)}</w:t></w:r>';

  static String _tc(int w, String paragraphs,
          {String? fill, String vMerge = '', int span = 1}) =>
      '<w:tc><w:tcPr><w:tcW w:w="$w" w:type="dxa"/>'
      '${span > 1 ? '<w:gridSpan w:val="$span"/>' : ''}$vMerge'
      '${fill != null ? '<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>' : ''}'
      '<w:vAlign w:val="center"/></w:tcPr>$paragraphs</w:tc>';

  static String _p(String runs, {String jc = '', String spacing = ''}) =>
      '<w:p><w:pPr>$spacing${jc.isEmpty ? '' : '<w:jc w:val="$jc"/>'}</w:pPr>$runs</w:p>';

  /// Codici come «chip»: run con bordo e sfondo, spazi non separabili dentro
  /// (il chip non si spezza a fine riga), spazio normale tra un chip e l'altro.
  static String _chips(List<String> codes, {required bool teoria}) {
    final rpr = _rpr(17,
        bold: true,
        color: _blu,
        extra: '<w:bdr w:val="single" w:sz="4" w:space="0" '
            'w:color="${teoria ? _linea : _blu}"/>'
            '<w:shd w:val="clear" w:color="auto" w:fill="${teoria ? _chiaro : 'FFFFFF'}"/>');
    final sep = _run('  ', _rpr(17));
    return codes.map((c) => _run(' $c ', rpr)).join(sep);
  }

  static Map<String, List<String>> _byModule(List<String> codes) {
    final byMod = <String, List<String>>{};
    for (final raw in codes) {
      final c = raw.trim();
      if (c.isEmpty) continue;
      byMod.putIfAbsent(c.split('.').first.toUpperCase(), () => []).add(c);
    }
    for (final l in byMod.values) {
      l.sort(compareCode);
    }
    return byMod;
  }

  static String _conta(int n, int mods) =>
      '$n ${n == 1 ? 'sottomodulo' : 'sottomoduli'} in $mods ${mods == 1 ? 'modulo' : 'moduli'}';

  /// Tabella unica dei sottomoduli assegnati: una «card» per modulo con la
  /// cella del modulo unita in verticale, badge TEORIA (pieno) / PRATICA
  /// (chiaro) leggibili anche in bianco e nero, codici a chip.
  static String _buildCampo(ConferimentoData d, int tableW) {
    final t = _byModule(d.theoryCodes);
    final p = _byModule(d.practiceCodes);
    final modules = {...t.keys, ...p.keys}.toList()..sort(compareCode);
    final c1 = tableW * 46 ~/ 170;
    final c2 = tableW * 17 ~/ 170;
    final c3 = tableW - c1 - c2;
    const sp = '<w:spacing w:before="30" w:after="30"/>';

    final buf = StringBuffer()
      ..write('<w:tbl><w:tblPr><w:tblW w:w="$tableW" w:type="dxa"/><w:jc w:val="center"/>'
          '<w:tblBorders>'
          '<w:top w:val="single" w:sz="8" w:space="0" w:color="$_blu"/>'
          '<w:left w:val="single" w:sz="8" w:space="0" w:color="$_blu"/>'
          '<w:bottom w:val="single" w:sz="8" w:space="0" w:color="$_blu"/>'
          '<w:right w:val="single" w:sz="8" w:space="0" w:color="$_blu"/>'
          '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="$_linea"/>'
          '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="$_linea"/>'
          '</w:tblBorders><w:tblLayout w:type="fixed"/>'
          '<w:tblCellMar><w:top w:w="20" w:type="dxa"/><w:left w:w="90" w:type="dxa"/>'
          '<w:bottom w:w="20" w:type="dxa"/><w:right w:w="90" w:type="dxa"/></w:tblCellMar>'
          '</w:tblPr><w:tblGrid><w:gridCol w:w="$c1"/><w:gridCol w:w="$c2"/>'
          '<w:gridCol w:w="$c3"/></w:tblGrid>')
      ..write('<w:tr><w:trPr><w:cantSplit/><w:tblHeader/></w:trPr>${_tc(
        tableW,
        _p(
          _run('SOTTOMODULI ASSEGNATI', _rpr(18, bold: true, color: 'FFFFFF')) +
              _run('\tTeoria: ${_conta(t.values.fold(0, (s, l) => s + l.length), t.length)}'
                  '   ·   Pratica: ${_conta(p.values.fold(0, (s, l) => s + l.length), p.length)}',
                  _rpr(15, italic: true, color: 'FFFFFF')),
          spacing: '<w:tabs><w:tab w:val="right" w:pos="${tableW - 200}"/></w:tabs>$sp',
        ),
        fill: _blu,
        span: 3,
      )}</w:tr>');
    if (modules.isEmpty) {
      buf.write('<w:tr>${_tc(tableW, _p(_run('—', _rpr(18)), jc: 'center', spacing: sp), span: 3)}</w:tr>');
    }
    for (final mod in modules) {
      final rows = [
        if (t.containsKey(mod)) (true, t[mod]!),
        if (p.containsKey(mod)) (false, p[mod]!),
      ];
      final name = _moduleNames[mod];
      for (var i = 0; i < rows.length; i++) {
        final (teoria, codes) = rows[i];
        final modCell = i == 0
            ? _tc(
                c1,
                _p(_run('MODULO $mod', _rpr(19, bold: true, color: _blu))) +
                    (name != null
                        ? _p(_run(name, _rpr(13, italic: true, color: '4A5A75')))
                        : ''),
                fill: _chiaro,
                vMerge: rows.length > 1 ? '<w:vMerge w:val="restart"/>' : '')
            : _tc(c1, '<w:p/>', fill: _chiaro, vMerge: '<w:vMerge/>');
        final badge = _tc(
            c2,
            _p(_run(teoria ? 'TEORIA' : 'PRATICA',
                    _rpr(14, bold: true, color: teoria ? 'FFFFFF' : _blu)),
                jc: 'center'),
            fill: teoria ? _blu : _chiaro);
        final chips = _tc(
            c3,
            _p(_chips(codes, teoria: teoria),
                spacing: '<w:spacing w:before="40" w:after="40" w:line="300" w:lineRule="auto"/>'));
        buf.write('<w:tr><w:trPr><w:cantSplit/></w:trPr>$modCell$badge$chips</w:tr>');
      }
    }
    buf.write('</w:tbl>');
    return buf.toString();
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
  /// separato da un page break. Il corpo contiene l'intestazione con emblema e
  /// fregio: i `wp:docPr id` vanno resi univoci a ogni copia (Word altrimenti
  /// segnala contenuto illeggibile); gli `r:embed` restano gli stessi.
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
              .replaceAll('@@ISTRUTTORE@@',
                  _esc.convert('${d.grado?.trim() ?? ''} ${formatName(d)}'.trim()))
              .replaceAll('@@QUALIFICA@@', _esc.convert(formatQualifica(d.qualifications)))
              .replaceAll('@@MAML@@', _esc.convert(_orDash(d.mamlNumber)))
              .replaceAll('@@DECORRENZA@@', _esc.convert(decorrenza))
              .replaceAll('@@TM@@', tm)
              .replaceAll('@@AM@@', am),
          _buildCampo(d, tableW),
        ),
    ];
    var n = 0;
    final body = pages
        .join(_pageBreak)
        .replaceAllMapped(RegExp(r'<wp:docPr id="\d+"'), (_) => '<wp:docPr id="${++n}"');
    return '${xml.substring(0, bodyStart)}$body$suffix';
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
