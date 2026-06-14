import 'dart:async';
import '../models/user_models.dart';
import 'gh_db_service.dart';

class AuthService {
  final _db = GhDbService();

  AppUser? login(String username, String password) {
    final target = username.toLowerCase();
    for (final raw in _db.users) {
      final uname = raw['username'] as String?;
      if (uname?.toLowerCase() != target) continue;
      final active = raw['is_active'] as bool? ?? true;
      if (!active) return null;
      final stored = raw['password_hash'] as String?;
      if (stored == null || stored.isEmpty) return null;
      if (!GhDbService.verifyPassword(password, stored)) return null;
      // Migrazione trasparente: aggiorna i vecchi hash SHA-256 al formato
      // PBKDF2 al primo login andato a buon fine. Best-effort: se la scrittura
      // fallisce il login resta comunque valido.
      if (GhDbService.isLegacyHash(stored)) {
        final id = raw['id'] as String?;
        if (id != null) {
          _db.updateUserPassword(id, GhDbService.hashPassword(password)).ignore();
        }
      }
      return AppUser.fromJson(raw);
    }
    return null;
  }
}
