import 'package:flutter_test/flutter_test.dart';

import 'package:corsi/services/password_reset.dart';

void main() {
  final users = <Map<String, dynamic>>[
    {'username': 'Rossi'},
    {'username': 'bianchi', 'is_active': false},
    {'username': 'verdi', 'password_reset_requested_at': '2026-10-30'},
  ];

  test('richiesta accettata solo per utente attivo senza richiesta aperta', () {
    expect(resetRequestIndex(users, ' rossi '), 0);
    expect(resetRequestIndex(users, 'bianchi'), -1);
    expect(resetRequestIndex(users, 'verdi'), -1);
    expect(resetRequestIndex(users, 'nessuno'), -1);
  });

  test('password temporanea di 8 caratteri non ambigui', () {
    expect(generateTempPassword(), matches(RegExp(r'^[a-km-np-z2-9]{8}$')));
  });
}
