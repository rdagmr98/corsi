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
    _workbook = _workbook.replaceFirst(
      RegExp(r'name="[^"]*"'),
      'name="$safe"',
    );
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
  }) {
    final xf = psModuleXf(moduleNumber);
    setText('D$row1Based', addestramento, styleId: xf);
    // D:F / I:J are merged — only top-left needs value+style
    setInt('G$row1Based', oreMod, styleId: xf);
    setText('H$row1Based', oreTot, styleId: xf);
    setText('I$row1Based', instructor, styleId: xf);
    setText('K$row1Based', sott, styleId: xf);
    if (taskId != null && taskId.isNotEmpty) {
      setText('L$row1Based', taskId, styleId: xf);
    } else {
      setText('L$row1Based', '', styleId: xf);
    }
    setInt('M$row1Based', oreSub, styleId: xf);
  }

  Uint8List encode() {
    _files['xl/worksheets/sheet1.xml'] = ArchiveFile(
      'xl/worksheets/sheet1.xml',
      utf8.encode(_sheet).length,
      utf8.encode(_sheet),
    );
    _files['xl/workbook.xml'] = ArchiveFile(
      'xl/workbook.xml',
      utf8.encode(_workbook).length,
      utf8.encode(_workbook),
    );

    final out = Archive();
    for (final e in _files.entries) {
      final content = e.value.content as List<int>;
      out.addFile(ArchiveFile(e.key, content.length, content));
    }
    final bytes = ZipEncoder().encode(out);
    if (bytes == null) {
      throw StateError('ZipEncoder failed');
    }
    return Uint8List.fromList(bytes);
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
