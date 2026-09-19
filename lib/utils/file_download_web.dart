import 'dart:html' as html;
import 'dart:typed_data';

Future<void> downloadBytes(
  Uint8List bytes,
  String filename, {
  String mimeType = 'application/octet-stream',
}) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
