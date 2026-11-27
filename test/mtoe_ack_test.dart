import 'package:flutter_test/flutter_test.dart';

import 'package:corsi/models/user_models.dart';
import 'package:corsi/services/grade_service.dart';

void main() {
  final u = AppUser.fromJson({
    'id': 'i',
    'nome': 'A',
    'cognome': 'B',
    'role': 'instructor',
    'mtoe_acks': {'1': '2026-11-28'},
    'created_at': '2026-01-01',
    'updated_at': '2026-01-01',
  });

  test('presa visione dell\'ultimo emendamento del MTOE', () {
    expect(u.mtoeAcks, {'1': '2026-11-28'});
    expect(GradeService.mtoeAcked(u, null), isTrue); // nessun emendamento
    expect(GradeService.mtoeAcked(u, {'n': 1}), isTrue);
    expect(GradeService.mtoeAcked(u, {'n': 2}), isFalse);
    // Sola lettura: la modifica admin non la riscrive.
    expect(u.toJson().containsKey('mtoe_acks'), isFalse);
    expect(u.copyWith().mtoeAcks, u.mtoeAcks);
  });
}
