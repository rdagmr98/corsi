import 'package:flutter_test/flutter_test.dart';

import 'package:corsi/models/user_models.dart';
import 'package:corsi/services/currency_loss_service.dart';

final _u = AppUser(
  id: 'i1',
  nome: 'N',
  cognome: 'C',
  role: 'instructor',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

List<LossEvent> _ev(Map<String, double> m) =>
    [for (final e in m.entries) (DateTime.parse(e.key), e.value)];

void main() {
  final today = DateTime(2026, 10, 15);

  test('lossDate exact: primo giorno NO-GO dopo l\'ultimo GO', () {
    // 6h insegnamento il 2025-10-10 (valide fino al 2026-10-09), 35h prof recenti.
    final teach = _ev({'2025-10-10': 6});
    final prof = _ev({'2026-01-10': 35});
    final r = lossDate(teach: teach, prof: prof, user: _u, today: today);
    expect(r.exact, isTrue);
    expect(r.date, DateTime(2026, 10, 10));
  });

  test('lossDate senza alcun dato: nessuna data', () {
    final r = lossDate(teach: [], prof: [], user: _u, today: today);
    expect(r.exact, isFalse);
    expect(r.date, isNull);
  });

  test('lossDate never-GO: stima = giorno dopo l\'ultimo criterio soddisfatto', () {
    // Solo insegnamento (6h il 2024-11-26): criterio teach vero fino al 2025-11-25,
    // prof mai -> mai GO.
    final teach = _ev({'2024-11-26': 6});
    final r = lossDate(teach: teach, prof: [], user: _u, today: today);
    expect(r.exact, isFalse);
    expect(r.date, DateTime(2025, 11, 26));
  });

  test('priorityBucket: ordine NO-GO non validato, scadenza, GO, NO-GO validato', () {
    int b(bool go, bool val, bool exp) =>
        priorityBucket(go: go, lossValidated: val, expiringSoon: exp);
    expect(b(false, false, false), 0);
    expect(b(true, false, true), 1);
    expect(b(true, false, false), 2);
    expect(b(false, true, false), 3);
  });
}
