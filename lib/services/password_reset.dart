import 'dart:math';

/// Riga da marcare per una richiesta di reset; -1 se l'utente non esiste,
/// è disattivato o ha già una richiesta aperta (niente notifiche doppie).
int resetRequestIndex(List<Map<String, dynamic>> users, String username) {
  final target = username.trim().toLowerCase();
  final i = users.indexWhere(
    (u) => (u['username'] as String?)?.toLowerCase() == target,
  );
  if (i < 0 ||
      users[i]['is_active'] == false ||
      users[i]['password_reset_requested_at'] != null) {
    return -1;
  }
  return i;
}

/// Password temporanea da comunicare a voce: senza caratteri ambigui (0/O, 1/l/I).
String generateTempPassword() {
  const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
  final random = Random.secure();
  return List.generate(8, (_) => alphabet[random.nextInt(alphabet.length)]).join();
}
