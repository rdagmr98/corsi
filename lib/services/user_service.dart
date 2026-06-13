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

  Future<void> setGoOverride(String userId, bool value) async {
    final users = _db.users.toList();
    final idx = users.indexWhere((u) => u['id'] == userId);
    if (idx < 0) return;
    users[idx] = {
      ...users[idx],
      'go_override': value,
      'updated_at': DateTime.now().toIso8601String(),
    };
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
