import 'dart:async';
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

/// Apre il selettore file del browser e restituisce il testo del file scelto.
/// ponytail: se l'utente annulla il future non si completa mai (il browser non
/// lo segnala); innocuo, nessuno resta in attesa con la UI bloccata.
Future<String?> pickTextFile({String accept = '.json'}) {
  final done = Completer<String?>();
  final input = html.FileUploadInputElement()..accept = accept;
  input.onChange.listen((_) {
    final files = input.files;
    if (files == null || files.isEmpty) return done.complete(null);
    final reader = html.FileReader();
    reader.onLoadEnd.listen((_) => done.complete(reader.result as String?));
    reader.onError.listen((_) => done.completeError('lettura del file non riuscita'));
    reader.readAsText(files.first);
  });
  input.click();
  return done.future;
}
