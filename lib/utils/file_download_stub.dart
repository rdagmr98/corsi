import 'dart:typed_data';
import 'package:printing/printing.dart';

Future<void> downloadBytes(
  Uint8List bytes,
  String filename, {
  String mimeType = 'application/octet-stream',
}) async {
  await Printing.sharePdf(bytes: bytes, filename: filename);
}
