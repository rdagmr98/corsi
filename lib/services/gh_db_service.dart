import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../config/gh_config.dart';
import 'crypto_service.dart';

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
    await Future.wait([
      _loadFile('reference.json'),
      _loadFile('users.json'),
      _loadFile('courses.json'),
      _loadFile('schedules.json'),
      _loadFile('records.json'),
      _loadFile('grades.json'),
      _loadFile('updates.json'),
    ]);
  }

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
      final content = utf8.decode(
        base64.decode((j['content'] as String).replaceAll('\n', '')),
      );
      _cache[fileName] = {
        'data': _normalizeLoaded(fileName, jsonDecode(content)),
        'sha': j['sha'] as String,
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

  Future<void> saveSchedules(List<Map<String, dynamic>> data) =>
      _writeFile('schedules.json', data, 'aggiornamento pianificazione');

  List<Map<String, dynamic>> get records =>
      List<Map<String, dynamic>>.from(_getData('records.json') as List? ?? []);

  Future<void> saveRecords(List<Map<String, dynamic>> data) =>
      _writeFile('records.json', data, 'aggiornamento presenze');

  List<Map<String, dynamic>> get grades =>
      List<Map<String, dynamic>>.from(_getData('grades.json') as List? ?? []);

  Future<void> saveGrades(List<Map<String, dynamic>> data) =>
      _writeFile('grades.json', data, 'aggiornamento voti');

  List<Map<String, dynamic>> get updates =>
      List<Map<String, dynamic>>.from(_getData('updates.json') as List? ?? []);

  Future<void> saveUpdates(List<Map<String, dynamic>> data) =>
      _writeFile('updates.json', data, 'aggiornamento ore istruttore');

  Future<void> reloadAll() => init();
}

class ConflictException implements Exception {
  final String message;
  ConflictException(this.message);
  @override
  String toString() => message;
}
