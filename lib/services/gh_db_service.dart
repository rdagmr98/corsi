import 'dart:convert';
import 'dart:math';
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

  static String get _base =>
      '${GhConfig.apiRoot}/repos/${GhConfig.owner}/${GhConfig.dataRepo}/contents/db';

  final Map<String, Map<String, dynamic>> _cache = {};
  final _crypto = CryptoService();

  // ── Hashing password (PBKDF2-HMAC-SHA256, salt per-utente) ──────────────────
  // Formato corrente: `pbkdf2$<iter>$<saltB64>$<hashB64>`.
  // Formato legacy: SHA-256 esadecimale di (password + salt globale).
  // `verifyPassword` accetta entrambi; i vecchi hash vengono migrati al primo
  // login andato a buon fine (vedi AuthService).
  static const int _pbkdf2Iterations = 10000;

  static String hashPassword(String password) {
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    final dk = _pbkdf2(utf8.encode(password), salt, _pbkdf2Iterations, 32);
    return 'pbkdf2\$$_pbkdf2Iterations\$${base64.encode(salt)}\$${base64.encode(dk)}';
  }

  static bool isLegacyHash(String stored) => !stored.startsWith('pbkdf2\$');

  static bool verifyPassword(String password, String stored) {
    if (stored.startsWith('pbkdf2\$')) {
      final parts = stored.split('\$');
      if (parts.length != 4) return false;
      final iter = int.tryParse(parts[1]) ?? 0;
      if (iter <= 0) return false;
      final salt = base64.decode(parts[2]);
      final expected = base64.decode(parts[3]);
      final dk = _pbkdf2(utf8.encode(password), salt, iter, expected.length);
      return _constTimeEquals(dk, expected);
    }
    // Legacy: SHA-256(password + salt globale)
    final legacy = sha256.convert(utf8.encode(password + GhConfig.passwordSalt)).toString();
    return _constTimeEquals(utf8.encode(legacy), utf8.encode(stored));
  }

  static List<int> _pbkdf2(List<int> password, List<int> salt, int iterations, int dkLen) {
    final hmac = Hmac(sha256, password);
    final out = <int>[];
    var block = 1;
    while (out.length < dkLen) {
      final blockSalt = <int>[
        ...salt,
        (block >> 24) & 0xff,
        (block >> 16) & 0xff,
        (block >> 8) & 0xff,
        block & 0xff,
      ];
      var u = hmac.convert(blockSalt).bytes;
      final t = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.addAll(t);
      block++;
    }
    return out.sublist(0, dkLen);
  }

  static bool _constTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
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
      _loadFile('notifications.json'),
    ]);
  }

  static String get _blobBase =>
      '${GhConfig.apiRoot}/repos/${GhConfig.owner}/${GhConfig.dataRepo}/git/blobs';

  Future<void> _loadFile(String fileName) async {
    final res = await http.get(
      Uri.parse('$_base/$fileName'),
      headers: {
        ...GhConfig.authHeaders(),
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    ).timeout(const Duration(seconds: 30));
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
            ...GhConfig.authHeaders(),
            'Accept': 'application/vnd.github.raw+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        ).timeout(const Duration(seconds: 30));
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

  final Map<String, ({dynamic data, dynamic wire, String msg})> _pending = {};
  final Map<String, Future<void>> _drains = {};

  void _updatePendingCount() {
    pendingSaves.value = {..._drains.keys, ..._pending.keys}.length;
  }

  /// [wire] è il payload effettivamente spedito a GitHub, se diverso da
  /// [data] (es. users.json: cache in chiaro, scrittura cifrata).
  void _enqueueWrite(String fileName, dynamic data, String msg, {dynamic wire}) {
    _cache[fileName] = {'data': data, 'sha': _getSha(fileName)};
    _pending[fileName] = (data: data, wire: wire ?? data, msg: msg);
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
        await _putLatest(fileName, job.wire, job.msg);
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
    final newSha = await _putToGitHub(fileName, data, msg);
    // Aggiorna solo lo sha: la cache può già contenere dati più recenti
    // in attesa di scrittura.
    final cur = _cache[fileName];
    _cache[fileName] = {'data': cur?['data'] ?? data, 'sha': newSha};
  }

  /// Tentativi massimi per una scrittura (1 iniziale + retry).
  static const int _maxWriteAttempts = 6;
  final _rng = Random();

  /// PUT su GitHub con retry ed exponential backoff. Ritenta sia sui
  /// conflitti (409, con refresh dello sha) sia sugli errori transitori
  /// (403/429/5xx, timeout, rete assente): con un token condiviso da tutti
  /// gli utenti un rate-limit momentaneo o un hiccup di rete non deve far
  /// fallire il salvataggio al primo colpo. Ritorna lo sha aggiornato.
  Future<String> _putToGitHub(String fileName, dynamic data, String msg) async {
    for (var attempt = 1; attempt <= _maxWriteAttempts; attempt++) {
      final sha = _getSha(fileName);
      final body = <String, dynamic>{
        'message': msg,
        'content': base64.encode(utf8.encode(jsonEncode(data))),
        if (sha.isNotEmpty) 'sha': sha,
      };

      final http.Response res;
      try {
        res = await http
            .put(
              Uri.parse('$_base/$fileName'),
              headers: {
                ...GhConfig.authHeaders(),
                'Accept': 'application/vnd.github+json',
                'Content-Type': 'application/json',
                'X-GitHub-Api-Version': '2022-11-28',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 30));
      } catch (e) {
        if (attempt == _maxWriteAttempts) {
          throw Exception('Rete non raggiungibile scrivendo $fileName: $e');
        }
        await _backoff(attempt);
        continue;
      }

      if (res.statusCode == 200 || res.statusCode == 201) {
        return ((jsonDecode(res.body) as Map)['content'] as Map)['sha'] as String;
      }

      final retryable = res.statusCode == 409 ||
          res.statusCode == 403 ||
          res.statusCode == 429 ||
          res.statusCode >= 500;
      if (!retryable || attempt == _maxWriteAttempts) {
        if (res.statusCode == 409) {
          throw ConflictException('Conflitto scrittura dopo $attempt tentativi.');
        }
        throw Exception('GitHub API ${res.statusCode}: ${res.body}');
      }

      if (res.statusCode == 409) {
        await _refreshSha(fileName);
        await _backoff(attempt);
      } else {
        await _waitForRateLimit(res);
      }
    }
    throw Exception('Salvataggio $fileName non riuscito dopo $_maxWriteAttempts tentativi.');
  }

  Future<void> _backoff(int attempt) async {
    final ms = min(1000 * (1 << (attempt - 1)), 16000);
    await Future<void>.delayed(Duration(milliseconds: ms + _rng.nextInt(400)));
  }

  /// Attende secondo l'header Retry-After / X-RateLimit-Reset di GitHub
  /// quando presente (rate-limit primario o secondario), altrimenti applica
  /// un'attesa di default.
  Future<void> _waitForRateLimit(http.Response res) async {
    final retryAfter = int.tryParse(res.headers['retry-after'] ?? '');
    if (retryAfter != null) {
      await Future<void>.delayed(Duration(seconds: retryAfter.clamp(1, 30)));
      return;
    }
    final resetEpoch = int.tryParse(res.headers['x-ratelimit-reset'] ?? '');
    if (resetEpoch != null) {
      final waitSecs = resetEpoch - DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (waitSecs > 0) {
        await Future<void>.delayed(Duration(seconds: waitSecs.clamp(1, 30)));
        return;
      }
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  /// Recupera solo lo sha corrente del file (listing della directory, senza
  /// scaricare il contenuto) mantenendo i dati ottimistici in cache.
  Future<void> _refreshSha(String fileName) async {
    final http.Response res;
    try {
      res = await http.get(
        Uri.parse(_base),
        headers: {
          ...GhConfig.authHeaders(),
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      return;
    }
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
    try {
      final newSha = await _putToGitHub(fileName, data, msg);
      _cache[fileName] = {'data': data, 'sha': newSha};
      saveError.value = null;
    } catch (e) {
      saveError.value = 'Salvataggio $fileName non riuscito: $e';
      rethrow;
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

  Future<void> saveReference(Map<String, dynamic> data) =>
      _writeFile('reference.json', data, 'aggiornamento tipi corso');

  List<Map<String, dynamic>> get users =>
      List<Map<String, dynamic>>.from(_getData('users.json') as List? ?? []);

  Future<void> saveUsers(List<Map<String, dynamic>> data) async {
    final encrypted = data.map(_encryptUser).toList();
    _enqueueWrite('users.json', data, 'aggiornamento utenti', wire: encrypted);
    await _awaitWrite('users.json');
  }

  List<Map<String, dynamic>> get courses =>
      List<Map<String, dynamic>>.from(_getData('courses.json') as List? ?? []);

  Future<void> saveCourses(List<Map<String, dynamic>> data) async {
    _enqueueWrite('courses.json', data, 'aggiornamento corsi');
    await _awaitWrite('courses.json');
  }

  /// Attende che la scrittura in coda per [fileName] arrivi davvero su
  /// GitHub. users.json/courses.json sono a bassa frequenza: meglio bloccare
  /// il chiamante che rischiare una ricarica pagina prima che il PUT sia
  /// arrivato (la cache ottimistica da sola non basta, viene svuotata da
  /// init()). Rilancia l'errore se il salvataggio ha esaurito i retry.
  Future<void> _awaitWrite(String fileName) async {
    final drain = _drains[fileName];
    if (drain != null) await drain;
    if (_pending.containsKey(fileName)) {
      throw Exception(saveError.value ?? 'Salvataggio $fileName non riuscito');
    }
  }

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

  List<Map<String, dynamic>> get notifications =>
      List<Map<String, dynamic>>.from(_getData('notifications.json') as List? ?? []);

  Future<void> saveNotifications(List<Map<String, dynamic>> data) async =>
      _enqueueWrite('notifications.json', data, 'aggiornamento notifiche');

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
