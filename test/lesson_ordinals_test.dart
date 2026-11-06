import 'package:corsi/models/schedule_models.dart';
import 'package:corsi/services/schedule_service.dart';
import 'package:flutter_test/flutter_test.dart';

ScheduledLesson _l(String id, String sub, DateTime d, int slot) => ScheduledLesson(
      id: id,
      courseId: 'c',
      moduleNumber: 6,
      submoduleCode: sub,
      topic: '',
      type: 'teoria',
      date: d,
      timeSlot: slot,
      createdAt: d,
      updatedAt: d,
    );

void main() {
  test('ordinale cronologico per chiave, non totale aggregato', () {
    final d1 = DateTime(2025, 11, 3), d2 = DateTime(2025, 11, 4);
    // Ordine di input mescolato: conta data + slot, non la posizione nella lista.
    final ord = ScheduleService.ordinals([
      _l('c', '6.1', d2, 1),
      _l('b', '6.1', d1, 2),
      _l('a', '6.1', d1, 1),
      _l('x', '6.2', d1, 3),
      _l('z', '6.1', d1, 0), // slot 0 escluso
    ], (l) => l.submoduleCode);
    expect(ord, {'a': 1, 'b': 2, 'c': 3, 'x': 1});
  });
}
