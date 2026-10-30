import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corsi/models/course_models.dart';
import 'package:corsi/screens/attendee/questionnaire_screen.dart';
import 'package:corsi/services/questionnaire_service.dart';

void main() {
  test('MTOE-F-2-7: 35 voci, valori distinti per voce (analisi valore→risposta)', () {
    expect(qItems.length, 35);
    for (final it in qItems) {
      final values = it.opts.map((o) => o.$2).toList();
      expect(values.toSet().length, values.length, reason: it.q);
      expect(values.reduce((a, b) => a > b ? a : b), 3);
    }
  });

  test('MTOE-A-2-1 (b): indice = totale/35, fasce IQ', () {
    final r = QResponse.fromJson({
      'attendee_id': null,
      'date': '2026-10-30',
      'answers': List.filled(35, 2),
      'services': List.filled(5, null),
    });
    expect(r.index, 2);
    expect(iqBand(1.80), 'NON ACCETTABILE');
    expect(iqBand(1.804), 'NON ACCETTABILE');
    expect(iqBand(1.81), 'BUONO');
    expect(iqBand(2.50), 'BUONO');
    expect(iqBand(2.51), 'OTTIMO');
  });

  testWidgets('form a larghezza telefono: nessun overflow, invio bloccato finché incompleto',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = Course(
      id: 'x',
      courseTypeId: 'b1',
      title: '3° Corso BTC Cat.B1 2025',
      startDate: DateTime(2025, 3, 10),
      endDate: DateTime(2027, 2, 28),
      status: 'active',
      createdBy: 't',
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );
    await tester.pumpWidget(MaterialApp(
        home: QuestionnaireScreen(course: c, module: 5, userId: 'u', onClose: () {})));
    for (var i = 0; i < 80; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
    }
    expect(find.text('SUGGERIMENTI'), findsOneWidget);
    expect(find.text('Rispondi a tutte le voci (0/35)'), findsOneWidget);
  });
}
