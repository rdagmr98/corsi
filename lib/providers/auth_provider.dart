import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_models.dart';
import '../services/auth_service.dart';
import '../services/gh_db_service.dart';

final authProvider = ChangeNotifierProvider((ref) => AuthProvider());

class AuthProvider extends ChangeNotifier {
  final _auth = AuthService();
  final _db = GhDbService();

  AppUser? _user;
  bool _loading = false;
  bool _dbInitialized = false;
  String? _error;
  int _unreadCount = 0;

  AppUser? get currentUser => _user;
  bool get isLoading => _loading;
  bool get dbInitialized => _dbInitialized;
  String? get error => _error;
  bool get isLoggedIn => _user != null;
  int get unreadCount => _unreadCount;

  void setUnreadCount(int v) {
    _unreadCount = v;
    notifyListeners();
  }

  void decrementUnread() {
    if (_unreadCount > 0) {
      _unreadCount--;
      notifyListeners();
    }
  }

  Future<void> initDb() async {
    if (_dbInitialized) return;
    await _db.init();
    _dbInitialized = true;
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      if (!_dbInitialized) {
        await _db.init();
        _dbInitialized = true;
      }
      final user = _auth.login(username, password);
      if (user == null) {
        _error = 'Credenziali non valide.';
        _loading = false;
        notifyListeners();
        return false;
      }
      _user = user;
      _unreadCount = _db.notifications
          .where((n) => n['user_id'] == user.id && n['is_read'] != true)
          .length;
      _loading = false;
      notifyListeners();
      // ponytail: solo l'id utente nel browser, mai la password
      (await SharedPreferences.getInstance()).setString(_uidKey, user.id);
      return true;
    } catch (e) {
      _error = 'Errore di connessione: $e';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  static const _uidKey = 'corsi_uid';

  /// Ripristina la sessione salvata (id utente) dopo un reload della pagina.
  Future<bool> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString(_uidKey);
    if (uid == null) return false;
    try {
      await initDb();
    } catch (_) {
      return false;
    }
    final raw = _db.users
        .where((u) => u['id'] == uid && u['is_active'] != false)
        .firstOrNull;
    if (raw == null) {
      await prefs.remove(_uidKey);
      return false;
    }
    _user = AppUser.fromJson(raw);
    _unreadCount = _db.notifications
        .where((n) => n['user_id'] == uid && n['is_read'] != true)
        .length;
    notifyListeners();
    return true;
  }

  Future<void> reloadDb() async {
    await _db.reloadAll();
    if (_user != null) {
      _unreadCount = _db.notifications
          .where((n) => n['user_id'] == _user!.id && n['is_read'] != true)
          .length;
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    (await SharedPreferences.getInstance()).remove(_uidKey);
    _user = null;
    _unreadCount = 0;
    _dbInitialized = false;
    notifyListeners();
  }
}
