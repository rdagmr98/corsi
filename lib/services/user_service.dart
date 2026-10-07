import '../models/user_models.dart';
import 'gh_db_service.dart';

class UserService {
  final _db = GhDbService();

  List<AppUser> getAllUsers() {
    final users = _db.users.map(AppUser.fromJson).toList();
    users.sort((a, b) => a.fullName.compareTo(b.fullName));
    return users;
  }

  List<AppUser> getByRole(UserRole role) =>
      getAllUsers().where((u) => u.userRole == role && u.isActive).toList();

  List<AppUser> getInstructors() => getByRole(UserRole.instructor);
  List<AppUser> getAttendees() => getByRole(UserRole.attendee);
  List<AppUser> getDirectors() => getByRole(UserRole.courseDirector);

  AppUser? findById(String id) {
    for (final raw in _db.users) {
      if (raw['id'] == id) return AppUser.fromJson(raw);
    }
    return null;
  }

  AppUser? findByUsername(String username) {
    for (final raw in _db.users) {
      if ((raw['username'] as String?)?.toLowerCase() == username.toLowerCase()) {
        return AppUser.fromJson(raw);
      }
    }
    return null;
  }

  bool usernameExists(String username) => findByUsername(username) != null;

  Future<AppUser> createUser({
    required String nome,
    required String cognome,
    required String username,
    required String password,
    required UserRole role,
    String? email,
    List<String>? qualifications,
    String? titolo,
    String? licenza,
    String? forza,
  }) async {
    final users = _db.users.toList();
    final now = DateTime.now().toIso8601String();
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final newUser = {
      'id': id,
      'nome': nome,
      'cognome': cognome,
      'email': email,
      'username': username,
      'password_hash': GhDbService.hashPassword(password),
      'role': role.value,
      'is_active': true,
      if (qualifications != null) 'qualifications': qualifications,
      if (titolo != null && titolo.isNotEmpty) 'titolo': titolo,
      if (licenza != null && licenza.isNotEmpty) 'licenza': licenza,
      if (forza != null && forza.isNotEmpty) 'forza': forza,
      'created_at': now,
      'updated_at': now,
    };
    users.add(newUser);
    await _db.saveUsers(users);
    return AppUser.fromJson(newUser);
  }

  Future<void> updateUser(AppUser updated) async {
    final users = _db.users.toList();
    final idx = users.indexWhere((u) => u['id'] == updated.id);
    if (idx < 0) return;
    users[idx] = {
      ...users[idx],
      ...updated.toJson(),
      'updated_at': DateTime.now().toIso8601String(),
    };
    await _db.saveUsers(users);
  }

  Future<void> updatePassword(String userId, String newPassword) async {
    final users = _db.users.toList();
    final idx = users.indexWhere((u) => u['id'] == userId);
    if (idx < 0) return;
    users[idx] = {
      ...users[idx],
      'password_hash': GhDbService.hashPassword(newPassword),
      'updated_at': DateTime.now().toIso8601String(),
    };
    await _db.saveUsers(users);
  }

  Future<void> deleteUser(String userId) async {
    final users = _db.users.where((u) => u['id'] != userId).toList();
    await _db.saveUsers(users);
  }

  Future<void> deleteUsers(Iterable<String> userIds) async {
    final ids = userIds.toSet();
    if (ids.isEmpty) return;
    final users = _db.users.where((u) => !ids.contains(u['id'])).toList();
    await _db.saveUsers(users);
  }

  Future<void> deactivateUser(String userId) async {
    final users = _db.users.toList();
    final idx = users.indexWhere((u) => u['id'] == userId);
    if (idx < 0) return;
    users[idx] = {
      ...users[idx],
      'is_active': false,
      'updated_at': DateTime.now().toIso8601String(),
    };
    await _db.saveUsers(users);
  }

  static String _ymd(DateTime d) => d.toIso8601String().substring(0, 10);

  /// Attiva/chiude l'OJT. Attivando si azzera la data di fine; chiudendo la
  /// si registra ([ojtEndAt] o oggi) se non c'è già. Tipo, inizio e note
  /// restano nello stato di servizio.
  Future<void> setGoOverride(String userId, bool value,
      {String? ojtKind, DateTime? ojtAt, DateTime? ojtEndAt}) async {
    final users = _db.users.toList();
    final idx = users.indexWhere((u) => u['id'] == userId);
    if (idx < 0) return;
    final updated = Map<String, dynamic>.from(users[idx] as Map<String, dynamic>);
    updated['go_override'] = value;
    if (value) {
      if (ojtKind != null) updated['ojt_kind'] = ojtKind;
      if (ojtAt != null) updated['ojt_at'] = _ymd(ojtAt);
      updated.remove('ojt_end_at');
    } else if (updated['ojt_at'] != null) {
      updated['ojt_end_at'] ??= _ymd(ojtEndAt ?? DateTime.now());
    }
    updated['updated_at'] = DateTime.now().toIso8601String();
    users[idx] = updated;
    await _db.saveUsers(users);
  }

  /// Modifica manuale dello stato di servizio OJT (admin): tipo, inizio, fine
  /// e note. Con fine vuota l'OJT è in corso (GO attivo), con fine l'OJT è chiuso.
  Future<void> setOjt(String userId,
      {required String kind,
      required DateTime startAt,
      DateTime? endAt,
      String? note}) async {
    final users = _db.users.toList();
    final idx = users.indexWhere((u) => u['id'] == userId);
    if (idx < 0) return;
    final updated = Map<String, dynamic>.from(users[idx] as Map<String, dynamic>);
    updated['ojt_kind'] = kind;
    updated['ojt_at'] = _ymd(startAt);
    endAt == null ? updated.remove('ojt_end_at') : updated['ojt_end_at'] = _ymd(endAt);
    final n = note?.trim() ?? '';
    n.isEmpty ? updated.remove('ojt_note') : updated['ojt_note'] = n;
    updated['go_override'] = endAt == null;
    updated['updated_at'] = DateTime.now().toIso8601String();
    users[idx] = updated;
    await _db.saveUsers(users);
  }

  Future<void> setCurrencyLostAt(String userId, DateTime? date) async {
    final users = _db.users.toList();
    final idx = users.indexWhere((u) => u['id'] == userId);
    if (idx < 0) return;
    final updated = Map<String, dynamic>.from(users[idx] as Map<String, dynamic>);
    if (date == null) {
      updated.remove('currency_lost_at');
    } else {
      updated['currency_lost_at'] = date.toIso8601String().substring(0, 10);
    }
    updated['updated_at'] = DateTime.now().toIso8601String();
    users[idx] = updated;
    await _db.saveUsers(users);
  }

  Future<void> setDaaExpiry(String userId, DateTime? expiry) async {
    final users = _db.users.toList();
    final idx = users.indexWhere((u) => u['id'] == userId);
    if (idx < 0) return;
    final updated = Map<String, dynamic>.from(users[idx] as Map<String, dynamic>);
    if (expiry == null) {
      updated.remove('daaa_expiry');
    } else {
      updated['daaa_expiry'] = expiry.toIso8601String().substring(0, 10);
    }
    updated['updated_at'] = DateTime.now().toIso8601String();
    users[idx] = updated;
    await _db.saveUsers(users);
  }
}
