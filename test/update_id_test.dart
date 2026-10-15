import 'package:flutter_test/flutter_test.dart';

import 'package:corsi/services/grade_service.dart';

Map<String, dynamic> _u(String id, String instr) =>
    {'id': id, 'instructor_id': instr};

void main() {
  test('newUpdateId: id distinti anche in un loop bulk nello stesso millisecondo', () {
    final updates = <Map<String, dynamic>>[];
    for (var i = 0; i < 500; i++) {
      updates.add(_u(GradeService.newUpdateId(updates), 'i$i'));
    }
    expect(updates.map((u) => u['id']).toSet().length, 500);
  });

  test('updateIndex: id duplicato tra istruttori diversi, vince l\'istruttore', () {
    final updates = [_u('abc', 'A'), _u('abc', 'B'), _u('def', 'B')];
    expect(GradeService.updateIndex(updates, 'abc', 'A'), 0);
    expect(GradeService.updateIndex(updates, 'abc', 'B'), 1);
    expect(GradeService.updateIndex(updates, 'abc', 'C'), -1);
  });
}
