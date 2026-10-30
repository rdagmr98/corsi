import 'package:corsi/models/schedule_models.dart';
import 'package:corsi/widgets/lesson_tile.dart';
import 'package:corsi/widgets/status_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Larghezza telefono stretto con lo stesso ingrandimento testo dell'app.
Future<void> _pump(WidgetTester tester, List<Widget> children) async {
  tester.view.physicalSize = const Size(320, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.35)),
      child: child!,
    ),
    home: Scaffold(body: ListView(padding: const EdgeInsets.all(16), children: children)),
  ));
}

void _expectNoCutText(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  for (final p in tester.renderObjectList<RenderParagraph>(find.byType(RichText))) {
    expect(p.didExceedMaxLines, isFalse, reason: p.text.toPlainText());
  }
}

void main() {
  testWidgets('due card affiancate: nessun overflow, testo intero', (tester) async {
    Widget card(String value, String? badge) => StatusCard(
          title: 'Aggiornamento',
          subtitle: 'Ultimi 2 anni di attività',
          value: value,
          badge: badge,
          footer: 'Da recuperare: 120 h su 1000 h',
          color: Colors.green,
          onTap: () {},
        );

    await _pump(tester, [
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: card('123.5 h', 'NO GO')),
          const SizedBox(width: 12),
          Expanded(child: card('100%', null)),
        ]),
      ),
    ]);
    _expectNoCutText(tester);
    expect(find.text('NO GO'), findsOneWidget);
    expect(find.text('Da recuperare: 120 h su 1000 h'), findsNWidgets(2));
  });

  testWidgets('riga lezione: numero dell\'ora sempre visibile, argomento al tap', (tester) async {
    final lesson = ScheduledLesson(
      id: 'l1',
      courseId: 'c1',
      date: DateTime(2026, 11, 2),
      timeSlot: 3,
      moduleNumber: 7,
      submoduleCode: '7.3',
      topic: 'Argomento molto lungo che su un telefono stretto occupa più di una riga intera di testo',
      type: 'teoria',
      instructorId: 'i1',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await _pump(tester, [LessonDescriber([lesson]).tile(lesson, action: const Text('Registra presenze'))]);

    expect(find.text('3ª ora'), findsOneWidget);
    expect(find.text('Registra presenze'), findsOneWidget);
    expect(find.text(lesson.topic), findsNothing);

    await tester.tap(find.text('3ª ora'));
    await tester.pumpAndSettle();
    expect(find.text(lesson.topic), findsOneWidget);
    _expectNoCutText(tester);
  });
}
