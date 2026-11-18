import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';

/// Cifratura PII (nome/cognome/email/username).
///
/// Formati ciphertext:
/// - `ENC1:<ivBase64>:<ctBase64>` — formato corrente, IV casuale per record
///   (non deterministico: due testi uguali producono ciphertext diversi).
/// - `ENC:<ctBase64>` — formato legacy con IV tutto-zero. Letto in sola
///   decifratura per retrocompatibilità con i dati già presenti in corsi-data.
///
/// NOTA: la chiave resta nel bundle web. L'IV casuale elimina il leak di
/// uguaglianza ma la riservatezza piena richiede spostare la chiave su un
/// backend/proxy (vedi PROXY_URL in GhConfig).
class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  static const String _rawKey = 'c9f4a12b83e06d5a71b2945bc80f3e1d';
  late final Key _key = Key.fromUtf8(_rawKey);
  final IV _legacyIv = IV.allZerosOfLength(16);
  late final Encrypter _encrypter = Encrypter(AES(_key, mode: AESMode.cbc));

  String encrypt(String plaintext) {
    if (plaintext.isEmpty) return plaintext;
    final iv = IV.fromSecureRandom(16);
    final ct = _encrypter.encrypt(plaintext, iv: iv).base64;
    return 'ENC1:${iv.base64}:$ct';
  }

  String decrypt(String ciphertext) {
    if (ciphertext.startsWith('ENC1:')) {
      try {
        final rest = ciphertext.substring(5);
        final sep = rest.indexOf(':');
        if (sep < 0) return ciphertext;
        final iv = IV.fromBase64(rest.substring(0, sep));
        return _encrypter.decrypt64(rest.substring(sep + 1), iv: iv);
      } catch (_) {
        return ciphertext;
      }
    }
    if (ciphertext.startsWith('ENC:')) {
      try {
        return _encrypter.decrypt64(ciphertext.substring(4), iv: _legacyIv);
      } catch (_) {
        return ciphertext;
      }
    }
    return ciphertext;
  }

  /// File binari (scansioni MAML): IV casuale di 16 byte in testa, poi AES-CBC PKCS7.
  Uint8List encryptBytes(Uint8List data) {
    final iv = IV.fromSecureRandom(16);
    return Uint8List.fromList([
      ...iv.bytes,
      ..._encrypter.encryptBytes(data, iv: iv).bytes,
    ]);
  }

  Uint8List decryptBytes(Uint8List data) => Uint8List.fromList(
    _encrypter.decryptBytes(
      Encrypted(data.sublist(16)),
      iv: IV(data.sublist(0, 16)),
    ),
  );

  String? encryptNullable(String? v) => v == null ? null : encrypt(v);
  String? decryptNullable(String? v) => v == null ? null : decrypt(v);
}
