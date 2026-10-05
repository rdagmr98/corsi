import 'package:flutter_test/flutter_test.dart';

import 'package:corsi/models/schedule_models.dart';
import 'package:corsi/services/schedule_service.dart';

ScheduledLesson _l(String id, int day, int slot, {bool confirmed = false}) =>
    ScheduledLesson(
      id: id,
      courseId: 'c',
      moduleNumber: 1,
      submoduleCode: '1.1',
      topic: id,
      type: 'teoria',
      date: DateTime(2026, 10, day), // 5 ott 2026 = lunedì
      timeSlot: slot,
      confirmed: confirmed,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  // Lun 5: A1 B2 C3(confermata) D4 · Mar 6: E1 · Ven 9: F3 · Lun 12: G1
  final a = _l('A', 5, 1), b = _l('B', 5, 2), c = _l('C', 5, 3, confirmed: true);
  final d = _l('D', 5, 4), e = _l('E', 6, 1), f = _l('F', 9, 3), g = _l('G', 12, 1);
  final all = [a, b, c, d, e, f, g];
  final today = DateTime(2026, 10, 5);

  test('cella libera: sposta solo la lezione', () {
    expect(ScheduleService.planDrop(all, a, DateTime(2026, 10, 7), 2, today: today),
        {'A': (DateTime(2026, 10, 7), 2)});
  });

  test('avanti su occupata: le intermedie scalano indietro, confermata ferma', () {
    final m = ScheduleService.planDrop(all, a, DateTime(2026, 10, 6), 1, today: today);
    expect(m, {
      'B': (DateTime(2026, 10, 5), 1),
      'D': (DateTime(2026, 10, 5), 2),
      'E': (DateTime(2026, 10, 5), 4),
      'A': (DateTime(2026, 10, 6), 1),
    });
  });

  test('indietro tra settimane: le intermedie scalano avanti', () {
    final m = ScheduleService.planDrop(all, g, DateTime(2026, 10, 6), 1, today: today);
    expect(m, {
      'G': (DateTime(2026, 10, 6), 1),
      'E': (DateTime(2026, 10, 9), 3),
      'F': (DateTime(2026, 10, 12), 1),
    });
  });

  test('lezioni passate non validate: ferme, non scalano e non si scavalcano', () {
    // Oggi = mar 6: A, B, C (lun 5) sono passate. G (lun 12) cade su B (passata).
    final t = DateTime(2026, 10, 6);
    expect(ScheduleService.isFrozen(a, t), isTrue);
    expect(ScheduleService.isFrozen(e, t), isFalse);
    expect(ScheduleService.planDrop(all, g, DateTime(2026, 10, 5), 2, today: t), isEmpty);
    // verso il futuro scalano solo le non passate: D (lun 5, passata) non si tocca
    final m = ScheduleService.planDrop(all, g, DateTime(2026, 10, 6), 1, today: t);
    expect(m.keys, isNot(contains('D')));
  });

  test('slot fuori orario regolare', () {
    expect(ScheduleService.isRegularSlot(DateTime(2026, 10, 9), 3), isTrue);
    expect(ScheduleService.isRegularSlot(DateTime(2026, 10, 9), 4), isFalse);
    expect(ScheduleService.isRegularSlot(DateTime(2026, 10, 10), 1), isFalse);
  });
}
