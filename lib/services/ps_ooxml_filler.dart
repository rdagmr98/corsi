import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'ps_module_style_map.dart';

/// Fills the official PS weekly template by patching OOXML in-place.
/// Does NOT use `package:excel` encode (that destroys borders/fonts/fills).
class PsOoxmlFiller {
  PsOoxmlFiller(Uint8List templateBytes)
      : _files = _decode(templateBytes);

  final Map<String, ArchiveFile> _files;
  late String _sheet;
  late String _workbook;

  static Map<String, ArchiveFile> _decode(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final map = <String, ArchiveFile>{};
    for (final f in archive.files) {
      if (f.isFile) map[f.name] = f;
    }
    return map;
  }

  void load() {
    _sheet = utf8.decode(_files['xl/worksheets/sheet1.xml']!.content as List<int>);
    _workbook = utf8.decode(_files['xl/workbook.xml']!.content as List<int>);
  }

  void renameSheet(String name) {
    final safe = _xmlEscape(name);
    final oldName = RegExp(r'name="([^"]*)"').firstMatch(_workbook)?.group(1);
    _workbook = _workbook.replaceFirst(
      RegExp(r'name="[^"]*"'),
      'name="$safe"',
    );
    // Keep Print_Area formula in sync with sheet rename.
    if (oldName != null && oldName.isNotEmpty) {
      _workbook = _workbook.replaceAll('$oldName!', '$safe!');
    }
  }

  /// Landscape, fit 1×1 page — applied at encode so every export prints usable.
  ///
  /// OOXML `sheetPr` child order is strict: tabColor?, outlinePr?, pageSetUpPr?.
  /// Inserting pageSetUpPr before tabColor makes Excel refuse to open the file.
  /// `view="pageBreakPreview"` on sheetView also makes Excel refuse this package.
  void ensurePrintSetup() {
    _sheet = _sheet.replaceFirst(
      RegExp(r'\s*view="pageBreakPreview"'),
      '',
    );
    final sheetPrMatch =
        RegExp(r'<sheetPr>(.*?)</sheetPr>', dotAll: true).firstMatch(_sheet);
    if (sheetPrMatch != null) {
      final body = sheetPrMatch.group(1)!;
      final tab = RegExp(r'<tabColor\b[^/]*/>').firstMatch(body)?.group(0);
      final outline =
          RegExp(r'<outlinePr\b[^/]*/>').firstMatch(body)?.group(0);
      final rebuilt = StringBuffer('<sheetPr>');
      if (tab != null) rebuilt.write(tab);
      if (outline != null) rebuilt.write(outline);
      rebuilt.write('<pageSetUpPr fitToPage="1"/>');
      rebuilt.write('</sheetPr>');
      _sheet = _sheet.replaceFirst(sheetPrMatch.group(0)!, rebuilt.toString());
    } else if (RegExp(r'<sheetPr\b[^>]*/>').hasMatch(_sheet)) {
      _sheet = _sheet.replaceFirst(
        RegExp(r'<sheetPr\b[^>]*/>'),
        '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>',
      );
    } else {
      _sheet = _sheet.replaceFirst(
        '<dimension',
        '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr><dimension',
      );
    }

    // Preserve printerSettings r:id when present on the template.
    final hasPrinterRid =
        RegExp(r'<pageSetup\b[^>]*\br:id="').hasMatch(_sheet);
    final pageSetup =
        '<pageSetup paperSize="9" fitToWidth="1" fitToHeight="1" '
        'orientation="landscape"'
        '${hasPrinterRid ? ' r:id="rId1"' : ''}/>';
    if (RegExp(r'<pageSetup\b').hasMatch(_sheet)) {
      _sheet = _sheet.replaceFirst(RegExp(r'<pageSetup\b[^/]*/>'), pageSetup);
    } else if (_sheet.contains('<pageMargins')) {
      _sheet = _sheet.replaceFirst('<pageMargins', '$pageSetup<pageMargins');
    } else {
      _sheet = _sheet.replaceFirst('</worksheet>', '$pageSetup</worksheet>');
    }

    const margins =
        '<pageMargins left="0.25" right="0.25" top="0.3" bottom="0.3" '
        'header="0.2" footer="0.2"/>';
    _sheet = _sheet.replaceFirst(RegExp(r'<pageMargins\b[^/]*/>'), margins);

    final sheetName =
        RegExp(r'name="([^"]+)"').firstMatch(_workbook)?.group(1) ??
            'Settimana';
    final safe = sheetName.replaceAll("'", "''");
    final dn =
        '<definedName name="_xlnm.Print_Area" localSheetId="0">'
        "'$safe'!\$A\$1:\$O\$70</definedName>";
    if (_workbook.contains('_xlnm.Print_Area')) {
      _workbook = _workbook.replaceFirst(
        RegExp(
          r'<definedName name="_xlnm\.Print_Area"[^>]*>.*?</definedName>',
          dotAll: true,
        ),
        dn,
      );
    } else if (_workbook.contains('<definedNames>')) {
      _workbook =
          _workbook.replaceFirst('<definedNames>', '<definedNames>$dn');
    } else {
      _workbook = _workbook.replaceFirst(
        '</workbook>',
        '<definedNames>$dn</definedNames></workbook>',
      );
    }
  }

  void setText(String addr, String text, {int? styleId}) {
    final body =
        ' t="inlineStr"><is><t>${_xmlEscape(text)}</t></is></c>';
    _upsertCell(addr, body, styleId: styleId);
  }

  void setInt(String addr, int value, {int? styleId}) {
    _upsertCell(addr, '><v>$value</v></c>', styleId: styleId);
  }

  void setDate(String addr, DateTime date, {int? styleId}) {
    // Excel serial date (1900 date system)
    final serial = _excelSerial(date);
    _upsertCell(addr, '><v>$serial</v></c>', styleId: styleId);
  }

  void paintLessonRow({
    required int row1Based,
    required int moduleNumber,
    required String addestramento,
    required int oreMod,
    required String oreTot,
    required String instructor,
    required String sott,
    String? taskId,
    required int oreSub,
    String? localita,
  }) {
    final xfL = psModuleXfLeft(moduleNumber);
    final xfC = psModuleXfCenter(moduleNumber);
    // D:F is merged — paint E/F too so the fill spans the whole ADDESTRAMENTO block.
    setText('D$row1Based', addestramento, styleId: xfL);
    _upsertCell('E$row1Based', '/>', styleId: xfL);
    _upsertCell('F$row1Based', '/>', styleId: xfL);
    setInt('G$row1Based', oreMod, styleId: xfC);
    setText('H$row1Based', oreTot, styleId: xfC);
    // I:J is merged — paint J fill to match instructor block.
    setText('I$row1Based', instructor, styleId: xfL);
    _upsertCell('J$row1Based', '/>', styleId: xfL);
    setText('K$row1Based', sott, styleId: xfC);
    if (taskId != null && taskId.isNotEmpty) {
      setText('L$row1Based', taskId, styleId: xfC);
    } else {
      // Leave ID TASK empty (unknown) — style only, no value.
      _upsertCell('L$row1Based', '/>', styleId: xfC);
    }
    setInt('M$row1Based', oreSub, styleId: xfC);
    // LOCALITA'/AULA (merge N:O). Preserve blank per-row border style (1230/1255…).
    // Do not touch O (merge slave) — keeps right-edge chrome.
    if (localita != null && localita.isNotEmpty) {
      setText('N$row1Based', localita); // keep existing s=
    }
  }

  Uint8List encode() {
    ensurePrintSetup();
    final sheetBytes = utf8.encode(_sheet);
    final wbBytes = utf8.encode(_workbook);
    _files['xl/worksheets/sheet1.xml'] = ArchiveFile(
      'xl/worksheets/sheet1.xml',
      sheetBytes.length,
      sheetBytes,
    );
    _files['xl/workbook.xml'] = ArchiveFile(
      'xl/workbook.xml',
      wbBytes.length,
      wbBytes,
    );

    final out = Archive();
    // Stable order helps Excel; Content_Types first.
    final keys = _files.keys.toList()
      ..sort((a, b) {
        if (a == '[Content_Types].xml') return -1;
        if (b == '[Content_Types].xml') return 1;
        return a.compareTo(b);
      });
    for (final key in keys) {
      final content = _files[key]!.content as List<int>;
      out.addFile(ArchiveFile(key, content.length, content));
    }
    final bytes = ZipEncoder().encode(out);
    if (bytes == null) {
      throw StateError('ZipEncoder failed');
    }
    // archive sets UTF-8 GP bit (0x800); clear it — Excel is picky.
    return _clearZipUtf8Flags(Uint8List.fromList(bytes));
  }

  /// Clear general-purpose bit 11 (UTF-8) on every local + central header.
  static Uint8List _clearZipUtf8Flags(Uint8List zip) {
    final out = Uint8List.fromList(zip);
    var i = 0;
    while (i + 30 <= out.length) {
      final sig = out[i] |
          (out[i + 1] << 8) |
          (out[i + 2] << 16) |
          (out[i + 3] << 24);
      if (sig == 0x04034b50) {
        // local file header
        final flags = out[i + 6] | (out[i + 7] << 8);
        final cleared = flags & ~0x800;
        out[i + 6] = cleared & 0xff;
        out[i + 7] = (cleared >> 8) & 0xff;
        final nameLen = out[i + 26] | (out[i + 27] << 8);
        final extraLen = out[i + 28] | (out[i + 29] << 8);
        final compSize = out[i + 18] |
            (out[i + 19] << 8) |
            (out[i + 20] << 16) |
            (out[i + 21] << 24);
        i += 30 + nameLen + extraLen + compSize;
        continue;
      }
      if (sig == 0x02014b50) {
        // central directory header
        final flags = out[i + 8] | (out[i + 9] << 8);
        final cleared = flags & ~0x800;
        out[i + 8] = cleared & 0xff;
        out[i + 9] = (cleared >> 8) & 0xff;
        final nameLen = out[i + 28] | (out[i + 29] << 8);
        final extraLen = out[i + 30] | (out[i + 31] << 8);
        final commentLen = out[i + 32] | (out[i + 33] << 8);
        i += 46 + nameLen + extraLen + commentLen;
        continue;
      }
      if (sig == 0x06054b50) break; // end of central directory
      break;
    }
    return out;
  }

  void _upsertCell(String addr, String afterOpenAttrs, {int? styleId}) {
    // afterOpenAttrs examples:
    //   't="inlineStr"><is><t>x</t></is></c>'
    //   '><v>1</v></c>'
    final sAttr = styleId != null ? ' s="$styleId"' : '';
    final replacement = '<c r="$addr"$sAttr$afterOpenAttrs';
    // If styleId null, preserve existing s=
    final pat = RegExp(
      '<c r="$addr"[^>]*?/>|<c r="$addr"[^>]*?>.*?</c>',
      dotAll: true,
    );
    if (!pat.hasMatch(_sheet)) {
      _sheet = _sheet.replaceFirst('</sheetData>', '$replacement</sheetData>');
      return;
    }
    if (styleId != null) {
      _sheet = _sheet.replaceFirst(pat, replacement);
      return;
    }
    _sheet = _sheet.replaceFirstMapped(pat, (m) {
      final old = m.group(0)!;
      final sm = RegExp(r'\bs="(\d+)"').firstMatch(old);
      final keep = sm != null ? ' s="${sm.group(1)}"' : '';
      return '<c r="$addr"$keep$afterOpenAttrs';
    });
  }

  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static int _excelSerial(DateTime d) {
    final utc = DateTime.utc(d.year, d.month, d.day);
    final epoch = DateTime.utc(1899, 12, 30);
    return utc.difference(epoch).inDays;
  }
}
