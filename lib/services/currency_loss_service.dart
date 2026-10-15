import '../models/grade_models.dart';
import '../models/user_models.dart';
import 'gh_db_service.dart';
import 'grade_service.dart';
import 'user_service.dart';

/// Evento che conta per la currency: (data, ore).
typedef LossEvent = (DateTime, double);

/// Descrizione delle voci `currency_loss` create dal rilevamento automatico.
const autoLossDescription = 'Perdita della currency (rilevata automaticamente)';

/// Giorni entro cui un GO è "prossimo alla scadenza" (stati di servizio).
const expiringSoonDays = 90;

// ponytail: primo import Excel degli stati di servizio (2026-06-06). Chi era già
// NO-GO a quella data ha la perdita validata in automatico; da lì in poi ogni
// perdita rilevata aspetta la validazione dell'admin.
final lossBackfillCutoff = DateTime(2026, 6, 6);

// Aritmetica sui giorni di calendario (DST-safe).
DateTime _back(DateTime d, int k) => DateTime(d.year, d.month, d.day - k);

double _sum(List<LossEvent> ev, DateTime d, int days) {
  final cutoff = _back(d, days);
  var s = 0.0;
  for (final (dt, h) in ev) {
    if (dt.isAfter(cutoff) && !dt.isAfter(d)) s += h;
  }
  return s;
}

/// Criteri di currency alla data [d]: 6 h di insegnamento negli ultimi 365 gg e
/// 35 h di aggiornamento negli ultimi 730 gg (2 anni), oppure deroga OJT.
/// Replica `GradeService.isGo` su una data qualsiasi.
({bool teach, bool prof}) criteriaOn(
  DateTime d, {
  required List<LossEvent> teach,
  required List<LossEvent> prof,
  required AppUser user,
  DateTime? lastOjt,
}) {
  final g = GradeService.ojtGraceFor(user, d, lastOjt: lastOjt);
  return (
    teach: g.teach || _sum(teach, d, 365) >= 6,
    prof: g.prof || _sum(prof, d, 730) >= 35,
  );
}

bool goOn(
  DateTime d, {
  required List<LossEvent> teach,
  required List<LossEvent> prof,
  required AppUser user,
  DateTime? lastOjt,
}) {
  final c = criteriaOn(d, teach: teach, prof: prof, user: user, lastOjt: lastOjt);
  return c.teach && c.prof;
}

/// Data in cui [user] ha perso la currency (primo giorno NO-GO). Da chiamare
/// solo per chi oggi è NO-GO.
/// - `exact`: ricostruita camminando all'indietro fino all'ultimo giorno GO;
/// - non `exact`: mai GO nell'orizzonte, data = giorno dopo l'ultimo in cui
///   almeno un criterio era soddisfatto (stima); `date` null se non c'è alcun dato.
({DateTime? date, bool exact}) lossDate({
  required List<LossEvent> teach,
  required List<LossEvent> prof,
  required AppUser user,
  required DateTime today,
  DateTime? lastOjt,
  int horizonDays = 2000,
}) {
  DateTime? lastT, lastP;
  for (var k = 0; k <= horizonDays; k++) {
    final d = _back(today, k);
    final c = criteriaOn(d, teach: teach, prof: prof, user: user, lastOjt: lastOjt);
    if (c.teach && c.prof) {
      return (date: k == 0 ? today : _back(today, k - 1), exact: true);
    }
    if (c.teach) lastT ??= d;
    if (c.prof) lastP ??= d;
  }
  final last = [lastT, lastP].whereType<DateTime>();
  if (last.isEmpty) return (date: null, exact: false);
  final m = last.reduce((a, b) => a.isAfter(b) ? a : b);
  return (date: DateTime(m.year, m.month, m.day + 1), exact: false);
}

/// Priorità di visualizzazione degli stati di servizio (0 = prima):
/// 0 NO-GO con perdita non validata · 1 GO prossimo alla scadenza · 2 GO ·
/// 3 NO-GO con perdita validata.
int priorityBucket({
  required bool go,
  required bool lossValidated,
  required bool expiringSoon,
}) {
  if (!go) return lossValidated ? 3 : 0;
  return expiringSoon ? 1 : 2;
}

/// Rilevamento automatico della perdita currency con validazione admin.
/// `currency_lost_at` (utente) è la perdita validata: la voce `currency_loss`
/// `pending` è la proposta, `rejected` la proposta scartata.
class CurrencyLossService {
  final _db = GhDbService();
  final _grades = GradeService();
  final _users = UserService();

  static bool _isLoss(Map<String, dynamic> u) => u['type'] == 'currency_loss';
  static bool _isOpen(Map<String, dynamic> u) =>
      _isLoss(u) && (u['status'] as String? ?? 'approved') != 'approved';
  static String _ymd(DateTime d) => d.toIso8601String().substring(0, 10);

  /// Registra le perdite non ancora a registro e ripulisce le proposte
  /// obsolete (istruttore tornato GO o perdita già validata). Un solo
  /// salvataggio per file. Ritorna true se ha scritto qualcosa.
  Future<bool> sync({DateTime? now}) async {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final users = _db.users.toList();
    final updates = _db.updates.toList();
    // Prima esecuzione assoluta (nessuna voce automatica mai creata).
    final backfill =
        !updates.any((u) => _isLoss(u) && u['description'] == autoLossDescription);
    var usersDirty = false, updatesDirty = false;

    for (final instr in _users.getInstructors()) {
      bool mine(Map<String, dynamic> u) => u['instructor_id'] == instr.id;
      final hasOpen = updates.any((u) => mine(u) && _isOpen(u));
      if (_grades.isGo(instr, now: n) || instr.currencyLostAt != null) {
        if (hasOpen) {
          updates.removeWhere((u) => mine(u) && _isOpen(u));
          updatesDirty = true;
        }
        continue;
      }
      if (hasOpen) continue;

      final ev = _grades.currencyEvents(instr.id);
      final r = lossDate(
        teach: ev.teach,
        prof: ev.prof,
        user: instr,
        today: today,
        lastOjt: _grades.lastOjtDate(instr.id),
      );
      DateTime date;
      bool validated;
      if (r.exact) {
        date = r.date!;
        validated = backfill && !date.isAfter(lossBackfillCutoff);
      } else if (backfill) {
        // Già NO-GO all'import: data stimata, mai oltre l'import, validata.
        date = r.date == null || r.date!.isAfter(lossBackfillCutoff)
            ? lossBackfillCutoff
            : r.date!;
        validated = true;
      } else if (r.date != null) {
        date = r.date!;
        validated = false;
      } else {
        continue; // nuovo istruttore senza alcun dato: nessuna perdita da registrare
      }

      updates.add({
        'id': GradeService.newUpdateId(updates),
        'instructor_id': instr.id,
        'type': 'currency_loss',
        'course_id': null,
        'hours': 0.0,
        'date': _ymd(date),
        'description': autoLossDescription,
        'created_at': n.toIso8601String(),
        'status': validated ? 'approved' : 'pending',
      });
      updatesDirty = true;
      if (validated) {
        final i = users.indexWhere((u) => u['id'] == instr.id);
        if (i >= 0) {
          users[i] = {
            ...users[i],
            'currency_lost_at': _ymd(date),
            'updated_at': n.toIso8601String(),
          };
          usersDirty = true;
        }
      }
    }

    // Utenti per primi: se il secondo salvataggio fallisce la perdita validata
    // resta valida e il rilevamento non la duplica.
    if (usersDirty) await _db.saveUsers(users);
    if (updatesDirty) await _db.saveUpdates(updates);
    return usersDirty || updatesDirty;
  }

  /// L'admin valida la perdita proposta: diventa quella ufficiale.
  Future<void> validate(InstructorUpdate u) async {
    await _users.setCurrencyLostAt(u.instructorId, u.date);
    await _grades.approveUpdate(u.id, u.instructorId);
  }

  Future<void> reject(InstructorUpdate u) =>
      _grades.setUpdateStatus(u.id, u.instructorId, 'rejected');
}
