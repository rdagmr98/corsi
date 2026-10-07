import 'package:flutter_test/flutter_test.dart';

import 'package:corsi/models/schedule_models.dart';
import 'package:corsi/services/schedule_service.dart';

ScheduledLesson _l(int day, {String? i1, String? i2, bool confirmed = false}) =>
    ScheduledLesson(
      id: 'l$day',
      courseId: 'c',
      moduleNumber: 1,
      submoduleCode: '1.1',
      topic: 't',
      type: 'teoria',
      date: DateTime(2026, 10, day),
      timeSlot: 1,
      instructorId: i1,
      instructorId2: i2,
      confirmed: confirmed,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  test('istruttori solo di lezioni non svolte + frequentatori, senza duplicati', () {
    final today = DateTime(2026, 10, 8);
    final r = ScheduleService.plannerRecipients([
      _l(5, i1: 'passata'),
      _l(8, i1: 'validata', confirmed: true),
      _l(9, i1: 'A', i2: 'B'),
      _l(12, i1: 'A'),
      _l(13),
    ], ['f1', 'A'], today);
    expect(r, {'A', 'B', 'f1'});
  });
}
