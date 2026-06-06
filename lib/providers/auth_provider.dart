import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  AppUser? get currentUser => _user;
  bool get isLoading => _loading;
  bool get dbInitialized => _dbInitialized;
  String? get error => _error;
  bool get isLoggedIn => _user != null;

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
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Errore di connessione: $e';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> reloadDb() async {
    await _db.reloadAll();
    notifyListeners();
  }

  Future<void> signOut() async {
    _user = null;
    _dbInitialized = false;
    notifyListeners();
  }
}
