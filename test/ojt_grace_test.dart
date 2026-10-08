import 'package:flutter_test/flutter_test.dart';

import 'package:corsi/models/user_models.dart';
import 'package:corsi/services/grade_service.dart';

AppUser _u({bool go = false, DateTime? ojtAt}) => AppUser(
      id: 'i',
      nome: 'A',
      cognome: 'B',
      role: 'instructor',
      goOverride: go,
      ojtAt: ojtAt,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  final at = DateTime(2025, 10, 9);

  test('OJT aperto: GO sulle 6 h entro 1 anno, sulle 35 h entro 2 anni', () {
    final u = _u(go: true, ojtAt: at);
    expect(GradeService.ojtGraceFor(u, 0, DateTime(2026, 10, 8)), (teach: true, prof: true));
    expect(GradeService.ojtGraceFor(u, 0, DateTime(2026, 10, 9)), (teach: false, prof: true));
    expect(GradeService.ojtGraceFor(u, 0, DateTime(2027, 10, 9)), (teach: false, prof: false));
  });

  test('OJT chiuso a 6 h: le 35 h restano in deroga fino a 2 anni', () {
    final u = _u(ojtAt: at);
    expect(GradeService.ojtGraceFor(u, 6, DateTime(2026, 3, 1)), (teach: false, prof: true));
  });

  test('OJT chiuso a mano prima delle 6 h: nessuna deroga', () {
    final u = _u(ojtAt: at);
    expect(GradeService.ojtGraceFor(u, 2, DateTime(2026, 3, 1)), (teach: false, prof: false));
  });

  test('legacy goOverride senza data inizio e istruttore senza OJT', () {
    expect(GradeService.ojtGraceFor(_u(go: true), 0, DateTime(2026, 3, 1)), (teach: true, prof: true));
    expect(GradeService.ojtGraceFor(_u(), 0, DateTime(2026, 3, 1)), (teach: false, prof: false));
  });
}
