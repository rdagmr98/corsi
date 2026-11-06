import 'dart:typed_data';

import 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart' as impl;

Future<void> downloadBytes(
  Uint8List bytes,
  String filename, {
  String mimeType = 'application/octet-stream',
}) =>
    impl.downloadBytes(bytes, filename, mimeType: mimeType);

/// Compatibilità call-site PDF esistenti.
Future<void> downloadPdf(Uint8List bytes, String filename) =>
    downloadBytes(bytes, filename, mimeType: 'application/pdf');

/// Testo di un file scelto dall'utente (web); null se non disponibile.
Future<String?> pickTextFile({String accept = '.json'}) =>
    impl.pickTextFile(accept: accept);
