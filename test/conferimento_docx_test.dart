import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corsi/models/user_models.dart';
import 'package:corsi/services/conferimento_docx_export.dart';

String _doc(List<int> bytes) => utf8.decode(
      ZipDecoder().decodeBytes(bytes).findFile('word/document.xml')!.content
          as List<int>,
    );

void main() {
  final tpl = File(ConferimentoDocxExport.templateAsset).readAsBytesSync();

  test('modulo F-3-4: 2 istruttori, campi, firme e pagine', () {
    final doc = _doc(ConferimentoDocxExport.buildBytes(tpl, const [
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
    ], decorrenza: '01/12/2026', firmaTm: 'IL TRAINING MANAGER\nCap. Tizio CAIO', firmaAm: ''));

    expect(doc.contains('@@'), isFalse);
    expect('>01/12/2026<'.allMatches(doc).length, 2);
    expect(doc.contains('>Luca VERDI<'), isTrue);
    expect(doc.contains('>Mario ROSSI<'), isTrue);
    expect(doc.contains('>1°Lgt.<'), isTrue);
    expect(doc.contains('>IT.EMAR66.EI000000<'), isTrue);
    expect('>—<'.allMatches(doc).length, greaterThanOrEqualTo(3)); // grado, MAML, pratica vuota di Rossi

    // Qualifiche NAM e SV
    expect(doc.contains('e Istruttore NAM'), isTrue);
    expect(doc.contains('>Istruttore SV<'), isTrue);

    // Solo moduli assegnati, codici in ordine numerico (5.4 prima di 5.12)
    expect(doc.contains('>5.4, 5.12.<'), isTrue);
    expect(doc.contains('>11A.5.<'), isTrue);
    expect(doc.contains('>3.7.<'), isTrue);
    expect(doc.contains('>9.1.<'), isTrue);
    expect(doc.contains('MODULE 6 '), isFalse);

    // Firme: TM su due righe, AM di default
    expect(doc.contains('IL TRAINING MANAGER</w:t><w:br/><w:t xml:space="preserve">Cap. Tizio CAIO'), isTrue);
    expect('>${ConferimentoDocxExport.defaultAm.replaceAll("'", '&#39;')}<'.allMatches(doc).length +
        ">${ConferimentoDocxExport.defaultAm}<".allMatches(doc).length, 2);

    // Un page break tra i due istruttori, un solo sectPr
    expect(RegExp(r'<w:br w:type="page"/>').allMatches(doc).length, 1);
    expect(RegExp(r'<w:sectPr\b').allMatches(doc).length, 1);

    expect(
      ConferimentoDocxExport.fileName(const [
        ConferimentoData(nome: 'Luca', cognome: 'Verdi', theoryCodes: [], practiceCodes: []),
      ], now: DateTime(2026, 11, 26)),
      'Conferimento_VERDI_2026-11-26.docx',
    );
    expect(
      ConferimentoDocxExport.fileName(const [
        ConferimentoData(nome: 'A', cognome: 'B', theoryCodes: [], practiceCodes: []),
        ConferimentoData(nome: 'C', cognome: 'D', theoryCodes: [], practiceCodes: []),
      ], now: DateTime(2026, 11, 26)),
      'Conferimenti_istruttori_2026-11-26.docx',
    );
  });

  test('moduli in ordine numerico, anche fuori elenco nomi', () {
    final doc = _doc(ConferimentoDocxExport.buildBytes(tpl, const [
      ConferimentoData(
        nome: 'Luca',
        cognome: 'Bianchi',
        theoryCodes: ['53.1', '52.10', '52.2', '51.1'],
        practiceCodes: ['3.1', '1.1'],
      ),
    ]));
    final i51 = doc.indexOf('MODULE 51 Weapons Systems');
    final i52 = doc.indexOf('>MODULE 52<');
    final i53 = doc.indexOf('MODULE 53 Surveillance and Electronic Warfare');
    expect(i51, greaterThan(0));
    expect(i52, greaterThan(i51));
    expect(i53, greaterThan(i52));
    expect(doc.contains('>52.2, 52.10.<'), isTrue);

    final prac = doc.indexOf('Practical element');
    final p1 = doc.indexOf('MODULE 1 ', prac);
    final p3 = doc.indexOf('MODULE 3 Electrical Fundamentals', prac);
    expect(p1, greaterThan(prac));
    expect(p3, greaterThan(p1));
  });

  test('AppUser grado/maml e insegnabili dalla griglia AMC', () {
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
    expect(u.toJson()['maml_number'], 'IT.EMAR66.EI000000');
    final cleared = u.copyWith(grado: null, mamlNumber: null);
    expect(cleared.toJson().containsKey('grado'), isFalse);
    expect(cleared.toJson().containsKey('maml_number'), isFalse);
    expect(cleared.titolo, 'TI - ETP');

    final teach = ConferimentoData.teachable({
      '5.12': ['u1'],
      '5.4': ['u1', 'u2'],
      '6.1': ['u2'],
    }, 'u1');
    expect(teach, ['5.4', '5.12']);

    final data = ConferimentoData.fromUser(u, theoryCodes: ['5.4'], practiceCodes: const []);
    expect(data.cognome, 'Verdi');
    expect(data.theoryCodes, ['5.4']);
    expect(data.qualifications, ['b1.3_uh212', 'nam']);
  });
}
