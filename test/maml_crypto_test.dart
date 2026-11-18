import 'dart:typed_data';

import 'package:corsi/services/crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encryptBytes / decryptBytes round-trip con IV casuale', () {
    final c = CryptoService();
    final plain = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, ...List.generate(512, (i) => i % 251)]);
    final a = c.encryptBytes(plain);
    final b = c.encryptBytes(plain);

    expect(a.length, greaterThan(plain.length + 16));
    expect(a.sublist(0, 16), isNot(equals(b.sublist(0, 16))));
    expect(c.decryptBytes(a), equals(plain));
    expect(c.decryptBytes(b), equals(plain));
  });
}
