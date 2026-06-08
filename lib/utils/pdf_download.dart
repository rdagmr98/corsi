import 'dart:typed_data';
export 'pdf_download_stub.dart'
    if (dart.library.html) 'pdf_download_web.dart';

typedef PdfDownloadFn = Future<void> Function(Uint8List bytes, String filename);
