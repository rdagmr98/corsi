import 'package:encrypt/encrypt.dart';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  static const String _rawKey = 'c9f4a12b83e06d5a71b2945bc80f3e1d';
  late final Key _key = Key.fromUtf8(_rawKey);
  final IV _iv = IV.allZerosOfLength(16);
  late final Encrypter _encrypter = Encrypter(AES(_key, mode: AESMode.cbc));

  String encrypt(String plaintext) {
    if (plaintext.isEmpty) return plaintext;
    return 'ENC:${_encrypter.encrypt(plaintext, iv: _iv).base64}';
  }

  String decrypt(String ciphertext) {
    if (!ciphertext.startsWith('ENC:')) return ciphertext;
    try {
      return _encrypter.decrypt64(ciphertext.substring(4), iv: _iv);
    } catch (_) {
      return ciphertext;
    }
  }

  String? encryptNullable(String? v) => v == null ? null : encrypt(v);
  String? decryptNullable(String? v) => v == null ? null : decrypt(v);
}
