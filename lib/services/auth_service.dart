import '../models/user_models.dart';
import 'gh_db_service.dart';

class AuthService {
  final _db = GhDbService();

  AppUser? login(String username, String password) {
    final hash = GhDbService.hashPassword(password);
    for (final raw in _db.users) {
      final uname = raw['username'] as String?;
      final phash = raw['password_hash'] as String?;
      final active = raw['is_active'] as bool? ?? true;
      if (uname?.toLowerCase() == username.toLowerCase() &&
          phash == hash &&
          active) {
        return AppUser.fromJson(raw);
      }
    }
    return null;
  }
}
