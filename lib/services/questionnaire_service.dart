import 'dart:math';

import '../models/course_models.dart';
import 'gh_db_service.dart';
import 'reference_service.dart';

/// Voce del questionario: domanda + risposte con il loro valore indice.
typedef QItem = ({String q, List<(String, double)> opts});

const _scuola = [
  ('OTTIMO', 3.0),
  ('BUONO', 2.0),
  ('SUFFICIENTE', 1.0),
  ('INSUFFICIENTE', 0.0),
];
const _ambiente =
    "L'ambiente in cui sono svolte le attività didattiche è stato:";
const _esposti =
    'I contenuti teorici sono stati esposti dai formatori/istruttori in modo:';
const _istruttore = 'Durante le lezioni, il formatore/istruttore:';
const _contributo =
    "Il contributo del formatore/istruttore al raggiungimento degli obiettivi del corso è stato:";
const _comunicazioni =
    "Le comunicazioni di ordine operativo/organizzativo/logistico da parte del direttore del corso sono:";

/// MTOE-F-2-7 "Questionario di qualità percepita" (testo del modulo cartaceo):
/// voci 1-28 DIDATTICA, 29-35 VALUTAZIONE SOGGETTIVA DELLA SCUOLA.
const qItems = <QItem>[
  (q: 'Gli obiettivi generali del corso/modulo:', opts: [
    ('Sono stati presentati in maniera dettagliata', 3),
    ('Sono stati presentati in maniera generica', 1),
    ('Sono stati presentati in maniera confusa', 0.5),
    ('Non sono stati presentati', 0),
  ]),
  (q: 'Gli obiettivi generali del corso/modulo hanno creato aspettative:', opts: [
    ('Coerenti con i risultati effettivi', 3),
    ('Eccessive in relazione ai risultati effettivi', 1),
    ('Inferiori ai risultati effettivi', 0.5),
    ('Fuorvianti rispetto ai risultati effettivi', 0),
  ]),
  (q: "L'agenda del corso e delle varie attività didattiche:", opts: [
    ('È stata descritta in modo analitico', 3),
    ('È stata descritta in modo generico', 1),
    ('È stata descritta in modo confuso', 0.5),
    ('Non è stata descritta', 0),
  ]),
  (q: 'Il tempo dedicato alle attività didattiche è stato:', opts: [
    ('Adeguato agli obiettivi del corso', 3),
    ('Sovradimensionato rispetto agli obiettivi del corso', 1.5),
    ('Sottodimensionato rispetto agli obiettivi del corso', 0),
  ]),
  (q: 'I carichi di lavoro necessari al raggiungimento degli obiettivi didattici in relazione allo svolgimento del corso sono stati:', opts: [
    ('Eccessivi', 2),
    ('Adeguati', 3),
    ('Sottodimensionati', 1),
    ('Assenti', 0),
  ]),
  (q: 'Gli argomenti trattati durante il corso:', opts: [
    ('Si integrano perfettamente e consentono il raggiungimento degli obiettivi', 3),
    ('Si integrano parzialmente consentendo comunque il raggiungimento degli obiettivi', 2),
    ('Si integrano parzialmente non consentendo il raggiungimento degli obiettivi', 1),
    ('Non si integrano e sono avulse dal contesto formativo proposto', 0),
  ]),
  (q: "Le metodologie utilizzate nell'ambito del corso:", opts: [
    ("Hanno facilitato l'acquisizione dei contenuti proposti", 3),
    ("Non hanno facilitato l'acquisizione dei contenuti proposti", 0),
  ]),
  (q: 'Le attività di esercitazione/pratica:', opts: [
    ('Sono coerenti con gli obiettivi generali', 3),
    ("Sono troppo difficili poiché richiedono l'acquisizione di conoscenze ulteriori a quelle condivise durante le lezioni", 1),
    ('Sono troppo facili poiché richiedono conoscenze meno complesse di quelle condivise durante le lezioni', 1.5),
    ('Non sono coerenti con gli obiettivi generali', 0),
  ]),
  (q: 'I dispositivi elettronici in dotazione:', opts: [
    ('Sono stati essenziali per lo svolgimento delle lezioni', 3),
    ('Non hanno prodotto alcun valore aggiunto', 0),
  ]),
  (q: _ambiente, opts: [
    ('Adeguato agli obiettivi del corso', 3),
    ('Inadeguato agli obiettivi del corso', 0),
  ]),
  (q: _ambiente, opts: [
    ("Ha favorito la concentrazione e l'attenzione", 3),
    ("Non ha favorito la concentrazione e l'attenzione", 0),
  ]),
  (q: _ambiente, opts: [
    ('Ha agevolato la comprensione dei contenuti', 3),
    ('Non ha agevolato la comprensione dei contenuti', 0),
  ]),
  (q: 'Questo corso/modulo:', opts: [
    ('Ha consentito di acquisire una parte rilevante dei contenuti esposti', 3),
    ('Ha consentito di acquisire solamente una piccola parte dei contenuti esposti', 1),
    ('Non ha prodotto alcun valore aggiunto in termini di conoscenze', 0),
  ]),
  (q: 'Questo corso/modulo:', opts: [
    ('Ha effettivamente consentito di acquisire nuove conoscenze/abilità', 3),
    ('Ha consentito di condividere conoscenze ed esperienze', 2),
    ('Ha consentito di acquisire consapevolezza delle mie esigenze formative', 1),
    ('Ha generato confusione sulle tematiche affrontate', 0),
  ]),
  (q: 'Le informazioni acquisite durante il corso/modulo:', opts: [
    ('Possono migliorare la qualità del lavoro', 3),
    ('Contribuiscono marginalmente a migliorare la qualità del lavoro', 2),
    ('Hanno generato nuove aspettative in ambito lavorativo', 1),
    ('Non contribuiscono a migliorare la qualità del lavoro', 0.5),
    ('Sono totalmente inapplicabili a qualsiasi ambito', 0),
  ]),
  (q: _esposti, opts: [
    ('Chiaro', 3),
    ('Logico', 2),
    ('Confuso', 1),
    ('Incomprensibile', 0),
  ]),
  (q: _esposti, opts: [
    ('Analitico', 3),
    ('Prolisso', 1),
    ('Generico', 0),
  ]),
  (q: "L'esposizione teorica del formatore/istruttore è stata:", opts: [
    ('Integrata in maniera funzionale con la presentazione di casi ed esempi', 3),
    ('Condotta in maniera chiara senza alcun riferimento a casi ed esempi', 2),
    ('Accompagnata dalla presentazione di un numero eccessivo di casi ed esempi', 1),
    ('Poco chiara a causa della mancata presentazione di casi ed esempi', 0),
  ]),
  (q: 'Il materiale didattico fornito:', opts: [
    ('Ha effettivamente supportato nel raggiungimento degli obiettivi del corso', 3),
    ('Ha prodotto un valore aggiunto marginale', 2),
    ('Ha prodotto solamente confusione e problemi di comprensione', 1),
    ('Non ha prodotto alcun valore aggiunto', 0),
  ]),
  (q: _istruttore, opts: [
    ('Ha favorito in maniera funzionale vari momenti di confronto e di discussione', 3),
    ("Ha concesso poco spazio alla discussione e all'interazione con i partecipanti", 0),
  ]),
  (q: _istruttore, opts: [
    ('Ha prestato la dovuta attenzione alle sollecitazioni/domande dei partecipanti', 3),
    ("Ha dedicato troppo tempo all'interazione con i partecipanti e al confronto", 1),
    ('Non ha prestato la dovuta attenzione alle sollecitazioni/domande dei partecipanti', 0),
  ]),
  (q: 'Il formatore/istruttore:', opts: [
    ('Ha svolto in itinere delle attività di verifica', 3),
    ('Non ha svolto in itinere delle attività di verifica', 0),
  ]),
  (q: _contributo, opts: [('Fondamentale', 3), ('Nullo', 0)]),
  (q: _contributo, opts: [('Costante', 3), ('Incostante', 0)]),
  (q: _contributo, opts: [('Notevole', 3), ('Limitato', 1), ('Controproducente', 0)]),
  (q: _comunicazioni, opts: [('Chiare e funzionali', 3), ('Confuse e inutili', 0)]),
  (q: _comunicazioni, opts: [
    ('Tempestive', 3),
    ('Continue', 2),
    ('Discontinue', 1),
    ('Molto rare', 0),
  ]),
  (q: _comunicazioni, opts: [
    ('Analitiche e dettagliate', 3),
    ('Generiche', 1),
    ('Controproducenti e contraddittorie', 0),
  ]),
  (q: 'Personale docente', opts: _scuola),
  (q: 'Infrastrutture', opts: _scuola),
  (q: 'Organizzazione scolastica', opts: _scuola),
  (q: 'Capacità didattica degli insegnanti', opts: _scuola),
  (q: 'Disponibilità degli insegnanti', opts: _scuola),
  (q: 'Rispetto degli orari', opts: _scuola),
  (q: 'Ausili didattici', opts: _scuola),
];

/// Intestazioni di sezione, per numero della prima voce.
const qSections = {
  1: 'DIDATTICA',
  29: 'VALUTAZIONE SOGGETTIVA DELLA SCUOLA · 1. Elementi generali',
  32: 'VALUTAZIONE SOGGETTIVA DELLA SCUOLA · 2. Organizzazione dei corsi',
};

/// Servizi (senza punteggio): valutati 0 OTTIMO … 3 INSUFFICIENTE.
const qServices = [
  'Amministrativi',
  'Sistemazione alloggiativa',
  'Trasporti',
  'Mensa e Bar',
  'Rapporti con il personale addetto',
];
const qServiceScale = ['OTTIMO', 'BUONO', 'SUFFICIENTE', 'INSUFF.'];

/// Una compilazione. [answers] = valore indice delle 35 voci in ordine,
/// [services] = indice in [qServiceScale] (null = non risposto).
class QResponse {
  final String? attendeeId; // null = anonimo
  final DateTime date;
  final List<double> answers;
  final List<int?> services;
  final String suggestions;

  QResponse.fromJson(Map<String, dynamic> j)
      : attendeeId = j['attendee_id'] as String?,
        date = DateTime.parse(j['date'] as String),
        answers = [for (final a in j['answers'] as List) (a as num).toDouble()],
        services = [for (final s in j['services'] as List) s as int?],
        suggestions = j['suggestions'] as String? ?? '';

  /// MTOE-A-2-1 (b): totale / 35, da 0 a 3.
  double get index => answers.fold(0.0, (a, b) => a + b) / qItems.length;
}

/// Questionario di un modulo: aperto/chiuso da direttore o admin.
class QSession {
  final String courseId;
  final int module;
  final bool open;
  final DateTime openedAt;
  final List<String> submittedBy;
  final List<QResponse> responses;

  QSession.fromJson(Map<String, dynamic> j)
      : courseId = j['course_id'] as String,
        module = j['module_number'] as int,
        open = j['open'] == true,
        openedAt = DateTime.parse(j['opened_at'] as String),
        submittedBy = List<String>.from(j['submitted_by'] as List? ?? []),
        responses = [
          for (final r in j['responses'] as List? ?? [])
            QResponse.fromJson(Map<String, dynamic>.from(r as Map))
        ];

  double? get iq => iqOf(responses);
}

/// IQ = Σ indici / n questionari.
double? iqOf(List<QResponse> rs) => rs.isEmpty
    ? null
    : rs.map((r) => r.index).reduce((a, b) => a + b) / rs.length;

/// Fascia MTOE-A-2-1 (b) sull'IQ arrotondato a 2 decimali.
String iqBand(double iq) {
  final v = (iq * 100).round() / 100;
  if (v <= 1.80) return 'NON ACCETTABILE';
  if (v <= 2.50) return 'BUONO';
  return 'OTTIMO';
}

class QuestionnaireService {
  final _db = GhDbService();

  static String _id(String courseId, int module) => '${courseId}_$module';
  static String _day(DateTime d) =>
      DateTime(d.year, d.month, d.day).toIso8601String().substring(0, 10);

  static String moduleLabel(Course c, int module) {
    final m = ReferenceService()
        .getEffectiveCourseType(
            c.courseTypeId, c.extensionTypeId, c.mamlCombinationId)
        ?.modules
        .where((m) => m.number == module)
        .firstOrNull;
    return m == null ? 'Modulo $module' : 'Modulo ${m.displayCode} ${m.name}';
  }

  List<QSession> _all() => _db.questionnaires.map(QSession.fromJson).toList();

  QSession? session(String courseId, int module) => _all()
      .where((s) => s.courseId == courseId && s.module == module)
      .firstOrNull;

  /// Questionari aperti nei corsi dell'utente e non ancora compilati.
  List<QSession> pendingFor(String userId, Iterable<String> courseIds) {
    final ids = courseIds.toSet();
    return _all()
        .where((s) =>
            s.open && ids.contains(s.courseId) && !s.submittedBy.contains(userId))
        .toList();
  }

  Future<void> setOpen(Course course, int module, {required bool open}) async {
    final id = _id(course.id, module);
    await _db.editQuestionnaires((all) {
      final i = all.indexWhere((s) => s['id'] == id);
      if (i == -1) {
        if (!open) return false;
        all.add({
          'id': id,
          'course_id': course.id,
          'module_number': module,
          'open': true,
          'opened_at': _day(DateTime.now()),
          'submitted_by': <String>[],
          'responses': <dynamic>[],
        });
        return true;
      }
      if ((all[i]['open'] == true) == open) return false;
      all[i] = {...all[i], 'open': open};
      return true;
    });
  }

  /// Invio unico per frequentatore. Le risposte non sono collegate a
  /// [userId] (che va solo in `submitted_by`, ordinato) se [anonymous]:
  /// la risposta finisce in una posizione casuale della lista.
  // ponytail: la storia git di corsi-data mostra risposta e submitted_by nello stesso commit; anonimato solo in app
  Future<void> submit({
    required String courseId,
    required int module,
    required String userId,
    required bool anonymous,
    required List<double> answers,
    required List<int?> services,
    required String suggestions,
  }) async {
    final rid = '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(1 << 30)}';
    final id = _id(courseId, module);
    await _db.editQuestionnaires((all) {
      final i = all.indexWhere((s) => s['id'] == id);
      if (i == -1 || all[i]['open'] != true) {
        throw StateError('Il questionario è stato chiuso.');
      }
      final s = all[i];
      final resp = List<dynamic>.from(s['responses'] as List? ?? []);
      // Ritentativo dopo una PUT riuscita ma senza risposta: già salvato.
      if (resp.any((r) => (r as Map)['rid'] == rid)) return false;
      final by = List<String>.from(s['submitted_by'] as List? ?? []);
      if (by.contains(userId)) {
        throw StateError('Hai già compilato questo questionario.');
      }
      by
        ..add(userId)
        ..sort();
      resp.insert(Random().nextInt(resp.length + 1), {
        'rid': rid,
        'attendee_id': anonymous ? null : userId,
        'date': _day(DateTime.now()),
        'answers': answers,
        'services': services,
        'suggestions': suggestions.trim(),
      });
      all[i] = {...s, 'submitted_by': by, 'responses': resp};
      return true;
    });
  }
}
