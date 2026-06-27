import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_models.dart';
import 'gh_db_service.dart';
import 'web_notification_service.dart';

class NotificationService {
  final _db = GhDbService();

  static const _appTitle = 'Corsi SMAM';
  static const _seenLimit = 250;

  int _nextId() {
    final ids = _db.notifications.map((n) => n['id']).whereType<int>().toSet();
    var candidate = DateTime.now().millisecondsSinceEpoch % 1000000000 + 1;
    while (ids.contains(candidate)) candidate++;
    return candidate;
  }

  // ── CRUD ────────────────────────────────────────────────────────────────────

  Future<void> createNotification({
    required String userId,
    required String type,
    required String message,
    bool dedupeUnread = false,
    Map<String, dynamic>? metadata,
  }) async {
    final all = _db.notifications;
    if (dedupeUnread &&
        all.any((n) =>
            n['user_id'] == userId &&
            n['type'] == type &&
            n['message'] == message &&
            n['is_read'] != true)) {
      return;
    }
    all.add({
      'id': _nextId(),
      'user_id': userId,
      'type': type,
      'message': message,
      'metadata': metadata,
      'is_read': false,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _db.saveNotifications(all);
  }

  Future<void> createNotifications(
    Iterable<
            ({
              String userId,
              String type,
              String message,
              Map<String, dynamic>? metadata
            })>
        entries, {
    bool dedupeUnread = false,
  }) async {
    final all = _db.notifications;
    var changed = false;
    for (final e in entries) {
      if (dedupeUnread &&
          all.any((n) =>
              n['user_id'] == e.userId &&
              n['type'] == e.type &&
              n['message'] == e.message &&
              n['is_read'] != true)) {
        continue;
      }
      all.add({
        'id': _nextId(),
        'user_id': e.userId,
        'type': e.type,
        'message': e.message,
        'metadata': e.metadata,
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
      changed = true;
    }
    if (changed) await _db.saveNotifications(all);
  }

  List<AppNotification> getNotifications(String userId) {
    return _db.notifications
        .where((n) => n['user_id'] == userId)
        .map(AppNotification.fromJson)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  int getUnreadCount(String userId) =>
      _db.notifications
          .where((n) => n['user_id'] == userId && n['is_read'] != true)
          .length;

  Future<void> markAsRead(int id) async {
    final all = _db.notifications;
    final idx = all.indexWhere((n) => n['id'] == id);
    if (idx == -1) return;
    all[idx] = {...all[idx], 'is_read': true};
    await _db.saveNotifications(all);
  }

  Future<void> markAllAsRead(String userId) async {
    final all = _db.notifications;
    var changed = false;
    for (var i = 0; i < all.length; i++) {
      if (all[i]['user_id'] == userId && all[i]['is_read'] != true) {
        all[i] = {...all[i], 'is_read': true};
        changed = true;
      }
    }
    if (changed) await _db.saveNotifications(all);
  }

  Future<void> deleteNotification(int id) async {
    final all = _db.notifications.where((n) => n['id'] != id).toList();
    await _db.saveNotifications(all);
  }

  Future<void> deleteAll(String userId) async {
    final all = _db.notifications.where((n) => n['user_id'] != userId).toList();
    await _db.saveNotifications(all);
  }

  // ── Domain helpers ───────────────────────────────────────────────────────────

  List<String> _adminIds() => _db.users
      .where((u) =>
          u['is_active'] != false &&
          ((u['role'] as String? ?? '').startsWith('admin')))
      .map((u) => u['id'] as String)
      .toList();

  /// Lezione aggiunta al calendario: notifica frequentatori + istruttore.
  Future<void> notifyLessonScheduled({
    required List<String> attendeeIds,
    String? instructorId,
    required String courseTitle,
    required String dateLabel,
    required String moduleLabel,
  }) async {
    final msg = 'Nuova lezione: $moduleLabel – $dateLabel ($courseTitle)';
    await createNotifications(
      [
        ...attendeeIds.map((id) => (
          userId: id,
          type: 'LESSON_SCHEDULED',
          message: msg,
          metadata: null,
        )),
        if (instructorId != null && instructorId.isNotEmpty)
          (
            userId: instructorId,
            type: 'LESSON_SCHEDULED',
            message: msg,
            metadata: null,
          ),
      ],
      dedupeUnread: false,
    );
  }

  /// Lezione modificata (istruttore o sottomodulo cambiato): notifica l'istruttore.
  Future<void> notifyLessonChanged({
    required String instructorId,
    required String courseTitle,
    required String dateLabel,
    required String moduleLabel,
  }) async {
    if (instructorId.isEmpty) return;
    await createNotification(
      userId: instructorId,
      type: 'LESSON_CHANGED',
      message: 'Lezione modificata: $moduleLabel – $dateLabel ($courseTitle)',
    );
  }

  /// Istruttore ha registrato le presenze: notifica il/i direttore/i.
  Future<void> notifyLessonValidated({
    required List<String> directorIds,
    required String instructorName,
    required String courseTitle,
    required String dateLabel,
    required String moduleLabel,
  }) async {
    final msg =
        '$instructorName ha registrato la lezione: $moduleLabel – $dateLabel ($courseTitle)';
    await createNotifications(
      directorIds.map((id) => (
        userId: id,
        type: 'LESSON_VALIDATED',
        message: msg,
        metadata: null,
      )),
    );
  }

  /// Reminder giorno prima per l'istruttore (dedup: non duplica se già presente e non letto).
  Future<void> notifyLessonReminder({
    required String instructorId,
    required String courseTitle,
    required String dateLabel,
    required String moduleLabel,
  }) async {
    await createNotification(
      userId: instructorId,
      type: 'LESSON_REMINDER',
      message: 'Reminder: lezione domani – $moduleLabel ($courseTitle)',
      dedupeUnread: true,
    );
  }

  /// Istruttore ha inviato un aggiornamento in attesa: notifica gli admin.
  Future<void> notifyUpdateSubmitted({
    required String instructorName,
    required String updateDescription,
  }) async {
    final msg =
        '$instructorName ha inviato un aggiornamento da validare: $updateDescription';
    await createNotifications(
      _adminIds().map((id) => (
        userId: id,
        type: 'UPDATE_SUBMITTED',
        message: msg,
        metadata: null,
      )),
    );
  }

  /// Admin ha approvato un aggiornamento: notifica l'istruttore.
  Future<void> notifyUpdateApproved({
    required String instructorId,
    required String description,
  }) async {
    await createNotification(
      userId: instructorId,
      type: 'UPDATE_APPROVED',
      message: 'Aggiornamento validato: $description',
    );
  }

  // ── Browser notifications sync ───────────────────────────────────────────────

  Future<void> syncBrowserNotifications(String userId) async {
    final unread = _db.notifications
        .where((n) => n['user_id'] == userId && n['is_read'] != true)
        .map(AppNotification.fromJson)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (unread.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final key = 'corsi_notif_seen_$userId';
    final seenList = prefs.getStringList(key) ?? <String>[];
    final seenSet = seenList.toSet();
    final updatedSeen = [...seenList];

    for (final n in unread) {
      final id = n.id.toString();
      if (seenSet.contains(id)) continue;
      WebNotificationService.showNotification(_appTitle, n.message);
      seenSet.add(id);
      updatedSeen.add(id);
    }

    if (updatedSeen.length > _seenLimit) {
      updatedSeen.removeRange(0, updatedSeen.length - _seenLimit);
    }
    await prefs.setStringList(key, updatedSeen);
  }
}
