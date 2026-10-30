import 'package:corsi/widgets/status_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('due card affiancate a larghezza telefono: nessun overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget card(String value) => StatusCard(
          title: 'Aggiornamento continuo',
          subtitle: 'Ultimi 2 anni di attività',
          value: value,
          progress: 2, // oltre il massimo: l'anello resta pieno
          footer: 'Da recuperare: 120 h su 1000 h',
          color: Colors.green,
          onTap: () {},
        );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(padding: const EdgeInsets.all(16), children: [
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: card('NO GO')),
              const SizedBox(width: 12),
              Expanded(child: card('100%')),
            ]),
          ),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('NO GO'), findsOneWidget);
  });
}
