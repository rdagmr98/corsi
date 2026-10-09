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
    expect(GradeService.ojtGraceFor(u, DateTime(2026, 10, 8)), (teach: true, prof: true));
    expect(GradeService.ojtGraceFor(u, DateTime(2026, 10, 9)), (teach: false, prof: true));
    expect(GradeService.ojtGraceFor(u, DateTime(2027, 10, 9)), (teach: false, prof: false));
  });

  test('OJT chiuso (a 6 h o a mano): la deroga resta fino alla scadenza', () {
    final u = _u(ojtAt: at);
    expect(GradeService.ojtGraceFor(u, DateTime(2026, 3, 1)), (teach: true, prof: true));
    expect(GradeService.ojtGraceFor(u, DateTime(2026, 12, 1)), (teach: false, prof: true));
    expect(GradeService.ojtGraceFor(u, DateTime(2027, 12, 1)), (teach: false, prof: false));
  });

  test('legacy chiuso senza ojt_at: ancora sull\'ultimo evento OJT', () {
    final last = DateTime(2026, 7, 13);
    expect(GradeService.ojtGraceFor(_u(), DateTime(2026, 10, 9), lastOjt: last),
        (teach: true, prof: true));
    expect(GradeService.ojtGraceFor(_u(), DateTime(2027, 8, 1), lastOjt: last),
        (teach: false, prof: true));
    expect(GradeService.ojtGraceFor(_u(), DateTime(2028, 8, 1), lastOjt: last),
        (teach: false, prof: false));
  });

  test('legacy attivo senza data e istruttore senza OJT', () {
    final n = DateTime(2026, 3, 1);
    expect(GradeService.ojtGraceFor(_u(go: true), n), (teach: true, prof: true));
    // OJT attivo senza data: un vecchio evento OJT non lo ancora.
    expect(GradeService.ojtGraceFor(_u(go: true), DateTime(2030), lastOjt: DateTime(2026)),
        (teach: true, prof: true));
    expect(GradeService.ojtGraceFor(_u(), n), (teach: false, prof: false));
  });
}
