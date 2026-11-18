import 'dart:typed_data';

import 'crypto_service.dart';
import 'gh_db_service.dart';
import 'notification_service.dart';

/// Scansione della MAML di un istruttore, cifrata in `corsi-data/maml/<id>/`.
/// L'istruttore la carica in attesa, l'admin la verifica e la approva; quella
/// caricata da un admin è già approvata.
class MamlScanService {
  final _db = GhDbService();
  final _crypto = CryptoService();
  final _notifications = NotificationService();

  static const maxBytes = 8 * 1024 * 1024;

  Map<String, dynamic> record(String userId) =>
      _db.mamlScans.where((r) => r['id'] == userId).firstOrNull ??
      {'id': userId};

  List<Map<String, dynamic>> pendingRecords() =>
      _db.mamlScans.where((r) => r['pending'] != null).toList();

  Future<Uint8List> load(Map<String, dynamic> file) async =>
      _crypto.decryptBytes(await _db.getBinary(file['path'] as String));

  Future<void> _save(Map<String, dynamic> rec) async {
    final all = _db.mamlScans..removeWhere((r) => r['id'] == rec['id']);
    await _db.saveMamlScans([...all, rec]);
  }

  void _drop(Map? file) {
    if (file != null) {
      _db.deleteBinary(
        file['path'] as String,
        file['sha'] as String,
        'rimozione scansione MAML',
      );
    }
  }

  Future<void> upload(
    String userId,
    Uint8List bytes,
    String mime, {
    required String byId,
    required bool approved,
  }) async {
    if (bytes.length > maxBytes) {
      throw Exception('File troppo grande (massimo 8 MB)');
    }
    final now = DateTime.now();
    final path = 'maml/$userId/${now.millisecondsSinceEpoch}.bin';
    final sha = await _db.putBinary(
      path,
      _crypto.encryptBytes(bytes),
      'scansione MAML',
    );
    final file = {
      'path': path,
      'sha': sha,
      'mime': mime,
      'at': now.toIso8601String(),
      'by': byId,
    };
    final rec = record(userId);
    final slot = approved ? 'approved' : 'pending';
    _drop(rec[slot] as Map?);
    await _save({...rec, slot: file});
    if (!approved) {
      final u = _db.users.where((u) => u['id'] == userId).firstOrNull ?? {};
      await _notifications.notifyAllAdmins(
        type: 'MAML_PENDING',
        message:
            'Scansione MAML da verificare: ${u['cognome'] ?? ''} ${u['nome'] ?? ''}.',
      );
    }
  }

  Future<void> approve(String userId, String adminId) async {
    final rec = record(userId);
    final pending = rec['pending'] as Map?;
    if (pending == null) return;
    _drop(rec['approved'] as Map?);
    await _save({
      ...rec,
      'approved': {...pending, 'approved_by': adminId},
      'pending': null,
    });
    await _notifications.createNotification(
      userId: userId,
      type: 'MAML_APPROVED',
      message: 'La scansione della tua MAML è stata verificata e approvata.',
    );
  }

  Future<void> reject(String userId, {String? reason}) async {
    final rec = record(userId);
    _drop(rec['pending'] as Map?);
    await _save({...rec, 'pending': null});
    final why = (reason ?? '').trim();
    await _notifications.createNotification(
      userId: userId,
      type: 'MAML_REJECTED',
      message:
          'La scansione della MAML non è stata approvata${why.isEmpty ? '' : ': $why'}. Caricane una nuova.',
    );
  }
}
