import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corsi/models/user_models.dart';
import 'package:corsi/services/conferimento_docx_export.dart';

void main() {
  test('export conferimenti: 2 istruttori su template reale', () {
    final tpl = File(ConferimentoDocxExport.templateAsset).readAsBytesSync();
    final bytes = ConferimentoDocxExport.buildBytes(tpl, const [
      ConferimentoData(
        grado: '1°Lgt.',
        nome: 'Luca',
        cognome: 'Verdi',
        mamlNumber: 'IT.EMAR66.EI000000',
        qualifications: ['b1.3_uh212', 'nam'],
        theoryCodes: ['5.12', '5.4', '11A.5', '12.2'],
        practiceCodes: ['3.7'],
      ),
      ConferimentoData(
        nome: 'Mario',
        cognome: 'Rossi',
        qualifications: ['sv'],
        theoryCodes: ['9.1'],
        practiceCodes: [],
      ),
    ], decorrenza: '01/12/2026');

    final archive = ZipDecoder().decodeBytes(bytes);
    expect(archive.findFile('word/media/image3.emf'), isNull);

    final doc = utf8.decode(
      archive.findFile('word/document.xml')!.content as List<int>,
    );

    // Nessun segnaposto residuo
    expect(doc.contains('@@'), isFalse);
    expect('Decorrenza: 01/12/2026'.allMatches(doc).length, 2);

    // Entrambi i nomi in OGGETTO e corpo (2 occorrenze ciascuno)
    expect(
      RegExp(r'1°Lgt\. Luca VERDI').allMatches(doc).length,
      2,
    );
    expect(
      RegExp(r'Mario ROSSI').allMatches(doc).length,
      2,
    );

    // MAML solo sul primo istruttore
    expect(doc.contains('MAML No.IT.EMAR66.EI000000'), isTrue);
    expect(RegExp(r'possessore della MAML').allMatches(doc).length, 1);

    // Ordine numerico codici (5.4 prima di 5.12) e altri codici
    expect(doc.contains('<w:t>5.4, 5.12.</w:t>'), isTrue);
    expect(doc.contains('<w:t>11A.5.</w:t>'), isTrue);
    expect(doc.contains('<w:t>12.2.</w:t>'), isTrue);
    expect(doc.contains('<w:t>3.7.</w:t>'), isTrue);
    expect(doc.contains('<w:t>9.1.</w:t>'), isTrue);

    // Qualifiche NAM e SV
    expect(doc.contains('e Istruttore NAM'), isTrue);
    expect(doc.contains('Istruttore SV'), isTrue);

    // Un solo page break tra i due istruttori, un solo sectPr finale
    expect(
      RegExp(r'<w:br w:type="page"/>').allMatches(doc).length,
      1,
    );
    expect(RegExp(r'<w:sectPr\b').allMatches(doc).length, 1);

    // Tutti gli id wp:docPr (e pic:cNvPr) unici nel documento
    final docPrIds = [
      for (final m in RegExp(r'<wp:docPr\b[^>]*\bid="(\d+)"').allMatches(doc))
        m.group(1)!,
    ];
    expect(docPrIds.length, greaterThanOrEqualTo(4));
    expect(docPrIds.toSet().length, docPrIds.length);

    final cNvPrIds = [
      for (final m in RegExp(r'<pic:cNvPr\b[^>]*\bid="(\d+)"').allMatches(doc))
        m.group(1)!,
    ];
    expect(cNvPrIds.toSet().length, cNvPrIds.length);

    // Nome file: singolo vs multiplo
    expect(
      ConferimentoDocxExport.fileName(
        const [
          ConferimentoData(
            nome: 'Luca',
            cognome: 'Verdi',
            theoryCodes: [],
            practiceCodes: [],
          ),
        ],
        now: DateTime(2026, 11, 26),
      ),
      'Conferimento_VERDI_2026-11-26.docx',
    );
    expect(
      ConferimentoDocxExport.fileName(
        const [
          ConferimentoData(
            nome: 'A',
            cognome: 'B',
            theoryCodes: [],
            practiceCodes: [],
          ),
          ConferimentoData(
            nome: 'C',
            cognome: 'D',
            theoryCodes: [],
            practiceCodes: [],
          ),
        ],
        now: DateTime(2026, 11, 26),
      ),
      'Conferimenti_istruttori_2026-11-26.docx',
    );
  });

  test('modulo non in elenco inserito nella posizione numerica giusta', () {
    final tpl = File(ConferimentoDocxExport.templateAsset).readAsBytesSync();
    final bytes = ConferimentoDocxExport.buildBytes(tpl, const [
      ConferimentoData(
        nome: 'Luca',
        cognome: 'Bianchi',
        theoryCodes: ['52.2', '52.10'],
        practiceCodes: ['1.1'],
      ),
    ]);
    final doc = utf8.decode(
      ZipDecoder()
          .decodeBytes(bytes)
          .findFile('word/document.xml')!
          .content as List<int>,
    );

    final idx51 = doc.indexOf('MODULE 51 Weapons Systems');
    final idx52 = doc.indexOf('<w:t>MODULE 52</w:t>');
    final idx53 = doc.indexOf('MODULE 53 Surveillance and Electronic Warfare');
    expect(idx51, greaterThan(0));
    expect(idx52, greaterThan(idx51));
    expect(idx53, greaterThan(idx52));
    expect(doc.contains('<w:t>52.2, 52.10.</w:t>'), isTrue);

    final pracStart = doc.indexOf('Practical element');
    final idxP1 = doc.indexOf('<w:t>MODULE 1</w:t>', pracStart);
    final idxP3 = doc.indexOf('MODULE 3 Electrical Fundamentals', pracStart);
    expect(idxP1, greaterThan(pracStart));
    expect(idxP3, greaterThan(idxP1));
    expect(doc.contains('<w:t>1.1.</w:t>'), isTrue);
  });

  test('AppUser grado/maml_number e ConferimentoData.fromUser', () {
    final u = AppUser.fromJson({
      'id': 'u1',
      'nome': 'Luca',
      'cognome': 'Verdi',
      'role': 'instructor',
      'grado': '1°Lgt.',
      'maml_number': 'IT.EMAR66.EI000000',
      'titolo': 'TI - ETP',
      'qualifications': ['b1.3_uh212', 'nam'],
    });
    expect(u.grado, '1°Lgt.');
    expect(u.mamlNumber, 'IT.EMAR66.EI000000');
    expect(u.titolo, 'TI - ETP');
    expect(u.toJson()['grado'], '1°Lgt.');
    expect(u.toJson()['maml_number'], 'IT.EMAR66.EI000000');

    final cleared = u.copyWith(grado: null, mamlNumber: null);
    expect(cleared.grado, isNull);
    expect(cleared.mamlNumber, isNull);
    expect(cleared.titolo, 'TI - ETP');
    expect(cleared.toJson().containsKey('grado'), isFalse);
    expect(cleared.toJson().containsKey('maml_number'), isFalse);

    final data = ConferimentoData.fromUser(
      u,
      theoryGrid: {
        '5.12': ['u1'],
        '5.4': ['u1', 'u2'],
        '6.1': ['u2'],
      },
      practiceGrid: {
        '3.7': ['u1'],
      },
    );
    expect(data.theoryCodes, containsAll(['5.12', '5.4']));
    expect(data.theoryCodes, isNot(contains('6.1')));
    expect(data.practiceCodes, ['3.7']);
  });
}
