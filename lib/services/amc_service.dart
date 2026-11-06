import 'gh_db_service.dart';
import 'reference_service.dart';
import 'user_service.dart';

/// Applica le qualifiche degli istruttori alle griglie AMC (amc.json)
/// secondo le regole dell'ANNESSO MTOE-P-3-1 (reference.amcRules).
class AmcService {
  final _db = GhDbService();
  final _ref = ReferenceService();

  /// Aggiorna theoryGrid/practiceGrid per [userId] in base a [quals]:
  /// sui codici coperti dalle regole l'istruttore viene aggiunto se
  /// qualificato e rimosso se non lo è più; i codici fuori regola
  /// (aggiunte manuali) non vengono toccati.
  Future<void> applyQualifications(String userId, Set<String> quals) =>
      _apply({userId: quals});

  /// Dopo una modifica dei criteri: ricalcola le griglie di tutti gli
  /// istruttori con qualifiche compilate (con `null` restano intatti).
  Future<void> reapplyAll() => _apply({
        for (final u in UserService().getInstructors())
          if (u.qualifications != null) u.id: u.qualifications!.toSet(),
      });

  Future<void> _apply(Map<String, Set<String>> qualsByUser) async {
    final amc = Map<String, dynamic>.from(_db.amcData);
    var changed = false;

    for (final theory in [true, false]) {
      final gridKey = theory ? 'theoryGrid' : 'practiceGrid';
      final raw = amc[gridKey] as Map<String, dynamic>? ?? {};
      final grid = raw.map(
        (k, v) => MapEntry(k, List<String>.from(v as List? ?? [])),
      );
      for (final e in qualsByUser.entries) {
        final userId = e.key;
        final teachable = _ref.teachableSubmodules(e.value, theory: theory);
        for (final code in _ref.amcRuleCodes(theory: theory)) {
          final ids = grid[code] ?? <String>[];
          final has = ids.contains(userId);
          if (teachable.contains(code) && !has) {
            grid[code] = [...ids, userId];
            changed = true;
          } else if (!teachable.contains(code) && has) {
            grid[code] = ids.where((id) => id != userId).toList();
            changed = true;
          }
        }
      }
      amc[gridKey] = grid;
    }

    if (changed) await _db.saveAmc(amc);
  }
}
