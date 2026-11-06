import 'dart:convert';
import 'dart:typed_data';

import 'gh_db_service.dart';

/// File JSON con tutti i dati di un corso: si scarica all'archiviazione, si
/// conserva fuori da GitHub (AER(EP).P-147, 147.A.125: registrazioni dei
/// frequentatori per almeno 20 anni dal termine del corso) e si ricarica
/// nell'app con [importJson]. I nomi sono in chiaro: in 20 anni la chiave
/// AES dell'app può cambiare, il file deve restare leggibile comunque.
class CourseArchiveService {
  static const format = 'corsi-smam-archivio-corso';
  final _db = GhDbService();

  /// Collezioni legate al corso via `course_id`: elenco attuale e come
  /// aggiungervi righe nuove.
  Map<String, (List<Map<String, dynamic>>, Future<void> Function(List<Map<String, dynamic>>))>
      get _collections => {
            'schedules': (_db.schedules, (n) => _db.saveSchedules([..._db.schedules, ...n])),
            'records': (_db.records, (n) => _db.saveRecords([..._db.records, ...n])),
            'grades': (_db.grades, (n) => _db.saveGrades([..._db.grades, ...n])),
            'notes': (_db.slotNotes, (n) => _db.saveSlotNotes([..._db.slotNotes, ...n])),
            // questionari: scrittura con merge, come le risposte dei frequentatori
            'questionnaires': (
              _db.questionnaires,
              (n) => _db.editQuestionnaires((all) {
                    final ids = {for (final m in all) m['id']};
                    final add = n.where((m) => !ids.contains(m['id'])).toList();
                    all.addAll(add);
                    return add.isNotEmpty;
                  })
            ),
            'updates': (_db.updates, (n) => _db.saveUpdates([..._db.updates, ...n])),
          };

  Map<String, dynamic> build(String courseId) {
    final course = _db.courses.firstWhere((m) => m['id'] == courseId);
    final data = {
      for (final e in _collections.entries)
        e.key: e.value.$1.where((m) => m['course_id'] == courseId).toList(),
    };
    final userIds = <Object?>{
      ...?course['attendee_ids'] as List?,
      ...?course['director_ids'] as List?,
      ...?course['instructor_ids'] as List?,
      for (final s in data['schedules']!) ...[s['instructor_id'], s['instructor_id_2']],
    };
    return {
      'format': format,
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      // Il file si genera prima del cambio di stato: va ricaricato archiviato.
      'course': {...course, 'status': 'archived'},
      // Senza hash password: un account ricaricato non deve poter entrare.
      'users': [
        for (final u in _db.users)
          if (userIds.contains(u['id'])) Map.of(u)..remove('password_hash'),
      ],
      ...data,
    };
  }

  Uint8List bytes(String courseId) => Uint8List.fromList(utf8.encode(
      const JsonEncoder.withIndent(' ').convert(build(courseId))));

  /// Aggiunge solo ciò che manca (stesso id = già presente). Restituisce il
  /// riepilogo per il messaggio all'utente.
  Future<String> importJson(String text) async {
    final j = jsonDecode(text);
    if (j is! Map || j['format'] != format) {
      throw const FormatException('il file non è un archivio corso di Corsi SMAM');
    }
    List<Map<String, dynamic>> list(String k) =>
        [for (final m in j[k] as List? ?? const []) Map<String, dynamic>.from(m as Map)];
    final course = Map<String, dynamic>.from(j['course'] as Map);
    if (_db.courses.any((m) => m['id'] == course['id'])) {
      throw StateError('il corso «${course['title']}» è già presente nell\'app');
    }

    Future<int> merge(List<Map<String, dynamic>> cur, List<Map<String, dynamic>> add,
        Future<void> Function(List<Map<String, dynamic>>) append) async {
      final ids = {for (final m in cur) m['id']};
      final fresh = add.where((m) => !ids.contains(m['id'])).toList();
      if (fresh.isNotEmpty) await append(fresh);
      return fresh.length;
    }

    // Username già preso da un utente attuale: l'account ricaricato lo perde.
    final taken = {for (final u in _db.users) (u['username'] as String?)?.toLowerCase()};
    final users = [
      for (final u in list('users'))
        taken.contains((u['username'] as String?)?.toLowerCase())
            ? (Map.of(u)..remove('username'))
            : u,
    ];
    final nUsers = await merge(_db.users, users, (n) => _db.saveUsers([..._db.users, ...n]));
    var nLessons = 0;
    for (final e in _collections.entries) {
      final n = await merge(e.value.$1, list(e.key), e.value.$2);
      if (e.key == 'schedules') nLessons = n;
    }
    await _db.saveCourses([..._db.courses, course]);
    return '«${course['title']}» ricaricato: $nLessons lezioni, $nUsers utenti';
  }
}
