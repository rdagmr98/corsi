import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/gh_config.dart';
import 'crypto_service.dart';
import 'reference_service.dart';

class GhDbService {
  static final GhDbService _instance = GhDbService._internal();
  factory GhDbService() => _instance;
  GhDbService._internal();

  static const String _base =
      'https://api.github.com/repos/${GhConfig.owner}/${GhConfig.dataRepo}/contents/db';

  final Map<String, Map<String, dynamic>> _cache = {};
  final _crypto = CryptoService();

  static String hashPassword(String password) {
    final bytes = utf8.encode(password + GhConfig.passwordSalt);
    return sha256.convert(bytes).toString();
  }

  Map<String, dynamic> _encryptUser(Map<String, dynamic> u) => {
    ...u,
    'nome': _crypto.encryptNullable(u['nome'] as String?),
    'cognome': _crypto.encryptNullable(u['cognome'] as String?),
    'email': _crypto.encryptNullable(u['email'] as String?),
    'username': _crypto.encryptNullable(u['username'] as String?),
  };

  Map<String, dynamic> _decryptUser(Map<String, dynamic> u) => {
    ...u,
    'nome': _crypto.decryptNullable(u['nome'] as String?),
    'cognome': _crypto.decryptNullable(u['cognome'] as String?),
    'email': _crypto.decryptNullable(u['email'] as String?),
    'username': _crypto.decryptNullable(u['username'] as String?),
  };

  dynamic _normalizeLoaded(String fileName, dynamic data) {
    if (fileName == 'users.json') {
      final items = List<Map<String, dynamic>>.from(data as List? ?? []);
      return items.map(_decryptUser).toList();
    }
    return data;
  }

  Future<void> init() async {
    _cache.clear();
    ReferenceService.invalidateLabelCache();
    await Future.wait([
      _loadFile('reference.json'),
      _loadFile('users.json'),
      _loadFile('courses.json'),
      _loadFile('schedules.json'),
      _loadFile('records.json'),
      _loadFile('grades.json'),
      _loadFile('updates.json'),
      _loadFile('amc.json'),
      _loadFile('notes.json'),
    ]);
  }

  static const String _blobBase =
      'https://api.github.com/repos/${GhConfig.owner}/${GhConfig.dataRepo}/git/blobs';

  Future<void> _loadFile(String fileName) async {
    final res = await http.get(
      Uri.parse('$_base/$fileName'),
      headers: {
        'Authorization': 'Bearer ${GhConfig.readPat}',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );
    if (res.statusCode == 200) {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final sha = j['sha'] as String;
      String content;

      final inlineContent = j['content'] as String?;
      if (inlineContent != null && inlineContent.trim().isNotEmpty) {
        // File ≤1MB: content is inline base64 in the metadata response
        content = utf8.decode(base64.decode(inlineContent.replaceAll('\n', '')));
      } else {
        // File >1MB: fetch raw via Git Blobs API
        final blobRes = await http.get(
          Uri.parse('$_blobBase/$sha'),
          headers: {
            'Authorization': 'Bearer ${GhConfig.readPat}',
            'Accept': 'application/vnd.github.raw+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        );
        if (blobRes.statusCode != 200) {
          throw Exception('GitHub blob ${blobRes.statusCode} loading $fileName');
        }
        content = blobRes.body;
      }

      _cache[fileName] = {
        'data': _normalizeLoaded(fileName, jsonDecode(content)),
        'sha': sha,
      };
      return;
    }
    if (res.statusCode == 404) {
      _cache[fileName] = {
        'data': fileName == 'reference.json' ? <String, dynamic>{} : <dynamic>[],
        'sha': '',
      };
      return;
    }
    throw Exception('GitHub API ${res.statusCode} loading $fileName');
  }

  dynamic _getData(String f) => _cache[f]?['data'];
  String _getSha(String f) => _cache[f]?['sha'] as String? ?? '';

  // ── Coda di scrittura ottimistica (file ad alta frequenza) ─────────────────
  // La cache viene aggiornata subito e la PUT su GitHub avviene in background;
  // salvataggi ravvicinati sullo stesso file vengono fusi nell'ultimo payload,
  // quindi N salvataggi consecutivi costano 1-2 PUT invece di N.

  /// Numero di file con scritture in corso o in attesa (per l'indicatore UI).
  static final ValueNotifier<int> pendingSaves = ValueNotifier<int>(0);

  /// Ultimo errore di salvataggio in background (null = tutto ok).
  static final ValueNotifier<String?> saveError = ValueNotifier<String?>(null);

  final Map<String, ({dynamic data, String msg})> _pending = {};
  final Map<String, Future<void>> _drains = {};

  void _updatePendingCount() {
    pendingSaves.value = {..._drains.keys, ..._pending.keys}.length;
  }

  void _enqueueWrite(String fileName, dynamic data, String msg) {
    _cache[fileName] = {'data': data, 'sha': _getSha(fileName)};
    _pending[fileName] = (data: data, msg: msg);
    saveError.value = null;
    _startDrain(fileName);
  }

  void _startDrain(String fileName) {
    if (!_drains.containsKey(fileName) && _pending.containsKey(fileName)) {
      _drains[fileName] = _drain(fileName).whenComplete(() {
        _drains.remove(fileName);
        _updatePendingCount();
      });
    }
    _updatePendingCount();
  }

  Future<void> _drain(String fileName) async {
    while (_pending.containsKey(fileName)) {
      final job = _pending.remove(fileName)!;
      try {
        await _putLatest(fileName, job.data, job.msg);
      } catch (e) {
        // Non perdere il payload: se nel frattempo non ne è arrivato uno più
        // recente, rimettilo in coda; verrà ritentato al prossimo salvataggio
        // o da flushPending().
        _pending.putIfAbsent(fileName, () => job);
        saveError.value = 'Salvataggio $fileName non riuscito: $e';
        return;
      }
    }
  }

  Future<void> _putLatest(String fileName, dynamic data, String msg) async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final body = <String, dynamic>{
        'message': msg,
        'content': base64.encode(utf8.encode(jsonEncode(data))),
      };
      final sha = _getSha(fileName);
      if (sha.isNotEmpty) body['sha'] = sha;
      final res = await http.put(
        Uri.parse('$_base/$fileName'),
        headers: {
          'Authorization': 'Bearer ${GhConfig.readPat}',
          'Accept': 'application/vnd.github+json',
          'Content-Type': 'application/json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
        body: jsonEncode(body),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        final newSha =
            ((jsonDecode(res.body) as Map)['content'] as Map)['sha'] as String;
        // Aggiorna solo lo sha: la cache può già contenere dati più recenti
        // in attesa di scrittura.
        final cur = _cache[fileName];
        _cache[fileName] = {'data': cur?['data'] ?? data, 'sha': newSha};
        return;
      }
      if (res.statusCode == 409 && attempt < maxAttempts) {
        await _refreshSha(fileName);
        await Future<void>.delayed(const Duration(seconds: 1));
        continue;
      }
      if (res.statusCode == 409) {
        throw ConflictException('Conflitto scrittura dopo $maxAttempts tentativi.');
      }
      throw Exception('GitHub API ${res.statusCode}: ${res.body}');
    }
  }

  /// Recupera solo lo sha corrente del file (listing della directory, senza
  /// scaricare il contenuto) mantenendo i dati ottimistici in cache.
  Future<void> _refreshSha(String fileName) async {
    final res = await http.get(
      Uri.parse(_base),
      headers: {
        'Authorization': 'Bearer ${GhConfig.readPat}',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );
    if (res.statusCode != 200) return;
    for (final e in (jsonDecode(res.body) as List).cast<Map<String, dynamic>>()) {
      if (e['name'] == fileName) {
        final cur = _cache[fileName];
        _cache[fileName] = {'data': cur?['data'], 'sha': e['sha'] as String};
        return;
      }
    }
  }

  /// Attende il completamento di tutte le scritture in coda; ritenta una volta
  /// quelle fallite. Lancia se restano salvataggi non scritti.
  Future<void> flushPending() async {
    for (var round = 0; round < 2; round++) {
      while (_drains.isNotEmpty) {
        await Future.wait(_drains.values.toList());
      }
      if (_pending.isEmpty) return;
      for (final f in _pending.keys.toList()) {
        _startDrain(f);
      }
    }
    while (_drains.isNotEmpty) {
      await Future.wait(_drains.values.toList());
    }
    if (_pending.isNotEmpty) {
      throw Exception(saveError.value ??
          'Salvataggi in sospeso non completati: ${_pending.keys.join(', ')}');
    }
  }

  Future<void> _writeFile(String fileName, dynamic data, String msg) async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final body = <String, dynamic>{
        'message': msg,
        'content': base64.encode(utf8.encode(jsonEncode(data))),
      };
      final sha = _getSha(fileName);
      if (sha.isNotEmpty) body['sha'] = sha;
      final res = await http.put(
        Uri.parse('$_base/$fileName'),
        headers: {
          'Authorization': 'Bearer ${GhConfig.readPat}',
          'Accept': 'application/vnd.github+json',
          'Content-Type': 'application/json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
        body: jsonEncode(body),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        final newSha =
            ((jsonDecode(res.body) as Map)['content'] as Map)['sha'] as String;
        _cache[fileName] = {'data': data, 'sha': newSha};
        return;
      }
      if (res.statusCode == 409) {
        await _loadFile(fileName);
        if (attempt < maxAttempts) {
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
        throw ConflictException('Conflitto scrittura dopo $maxAttempts tentativi.');
      }
      throw Exception('GitHub API ${res.statusCode}: ${res.body}');
    }
  }

  int nextId(Iterable<Map<String, dynamic>> existing) {
    final ids = existing.map((e) => e['id']).whereType<int>().toSet();
    var candidate = DateTime.now().microsecondsSinceEpoch;
    while (ids.contains(candidate)) candidate++;
    return candidate;
  }

  Map<String, dynamic> get referenceData =>
      (_getData('reference.json') as Map<String, dynamic>?) ?? {};

  Map<String, dynamic> get amcData =>
      (_getData('amc.json') as Map<String, dynamic>?) ?? {};

  Future<void> saveAmc(Map<String, dynamic> data) =>
      _writeFile('amc.json', data, 'aggiornamento AMC');

  List<Map<String, dynamic>> get users =>
      List<Map<String, dynamic>>.from(_getData('users.json') as List? ?? []);

  Future<void> saveUsers(List<Map<String, dynamic>> data) async {
    final encrypted = data.map(_encryptUser).toList();
    await _writeFile('users.json', encrypted, 'aggiornamento utenti');
    _cache['users.json'] = {'data': data, 'sha': _getSha('users.json')};
  }

  List<Map<String, dynamic>> get courses =>
      List<Map<String, dynamic>>.from(_getData('courses.json') as List? ?? []);

  Future<void> saveCourses(List<Map<String, dynamic>> data) =>
      _writeFile('courses.json', data, 'aggiornamento corsi');

  List<Map<String, dynamic>> get schedules =>
      List<Map<String, dynamic>>.from(_getData('schedules.json') as List? ?? []);

  Future<void> saveSchedules(List<Map<String, dynamic>> data) async =>
      _enqueueWrite('schedules.json', data, 'aggiornamento pianificazione');

  List<Map<String, dynamic>> get records =>
      List<Map<String, dynamic>>.from(_getData('records.json') as List? ?? []);

  Future<void> saveRecords(List<Map<String, dynamic>> data) async =>
      _enqueueWrite('records.json', data, 'aggiornamento presenze');

  List<Map<String, dynamic>> get grades =>
      List<Map<String, dynamic>>.from(_getData('grades.json') as List? ?? []);

  Future<void> saveGrades(List<Map<String, dynamic>> data) async =>
      _enqueueWrite('grades.json', data, 'aggiornamento voti');

  List<Map<String, dynamic>> get updates =>
      List<Map<String, dynamic>>.from(_getData('updates.json') as List? ?? []);

  Future<void> saveUpdates(List<Map<String, dynamic>> data) async =>
      _enqueueWrite('updates.json', data, 'aggiornamento ore istruttore');

  List<Map<String, dynamic>> get slotNotes =>
      List<Map<String, dynamic>>.from(_getData('notes.json') as List? ?? []);

  Future<void> saveSlotNotes(List<Map<String, dynamic>> data) async =>
      _enqueueWrite('notes.json', data, 'aggiornamento note slot');

  Future<void> updateUserPassword(String userId, String newHash) async {
    final all = users;
    final idx = all.indexWhere((u) => u['id'] == userId);
    if (idx == -1) throw Exception('Utente non trovato');
    all[idx] = {...all[idx], 'password_hash': newHash,
      'updated_at': DateTime.now().toUtc().toIso8601String()};
    await saveUsers(all);
  }

  Future<void> reloadAll() async {
    // Prima scrivi ciò che è in coda, altrimenti il reload sovrascriverebbe
    // in cache i dati ottimistici non ancora salvati.
    await flushPending();
    await init();
  }
}

class ConflictException implements Exception {
  final String message;
  ConflictException(this.message);
  @override
  String toString() => message;
}
