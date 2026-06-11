import '../models/reference_models.dart';
import 'gh_db_service.dart';

class ReferenceService {
  final _db = GhDbService();

  Map<String, dynamic> get _ref => _db.referenceData;

  List<CourseTypeInfo> getCourseTypes() {
    final list = _ref['courseTypes'] as List? ?? [];
    return list
        .map((j) => CourseTypeInfo.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  CourseTypeInfo? getCourseType(String id) {
    try {
      return getCourseTypes().firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  // Returns a merged CourseTypeInfo combining base modules with optional extension modules (e.g. b1 + b1mil).
  CourseTypeInfo? getEffectiveCourseType(String typeId, [String? extensionTypeId]) {
    final base = getCourseType(typeId);
    if (extensionTypeId == null || base == null) return base;
    final ext = getCourseType(extensionTypeId);
    if (ext == null) return base;
    return CourseTypeInfo(
      id: '${base.id}+${ext.id}',
      code: base.code,
      name: base.name,
      category: base.category,
      maxAttendees: base.maxAttendees,
      schedule: base.schedule,
      modules: [...base.modules, ...ext.modules],
    );
  }

  // Etichetta di un modulo dato il numero interno (es. 11 → '11A', 18 → '11B').
  // Cache statica: la mappa numero→label è identica per tutti i tipi corso.
  static Map<int, String>? _labelCache;

  String moduleLabel(int number) {
    if (_labelCache == null) {
      final cache = <int, String>{};
      for (final ct in getCourseTypes()) {
        for (final m in ct.modules) {
          if (m.label != null) cache[m.number] = m.label!;
        }
      }
      _labelCache = cache;
    }
    return _labelCache![number] ?? '$number';
  }

  static void invalidateLabelCache() => _labelCache = null;

  GradingRules getGradingRules() {
    final j = _ref['grading'] as Map<String, dynamic>?;
    if (j == null) return const GradingRules(scale: 30, passThreshold: 0.75, passScore: 22.5, assessmentWeight: 1, examWeight: 2);
    return GradingRules.fromJson(j);
  }

  InstructorCurrencyRules getCurrencyRules() {
    final j = _ref['instructorCurrency'] as Map<String, dynamic>?;
    if (j == null) return const InstructorCurrencyRules(teachingHoursPerYear: 6, professionalUpdateHoursPer2Years: 35);
    return InstructorCurrencyRules.fromJson(j);
  }

  // ── Regole AMC (ANNESSO MTOE-P-3-1): qualifica → sottomoduli insegnabili ──
  Map<String, dynamic> get _amcRules =>
      _ref['amcRules'] as Map<String, dynamic>? ?? {};

  List<AmcQualification> amcQualifications() {
    final list = _amcRules['qualifications'] as List? ?? [];
    return list
        .map((j) => AmcQualification.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Map<String, List<String>> _ruleMap(bool theory) {
    final raw = _amcRules[theory ? 'theory' : 'practice']
            as Map<String, dynamic>? ??
        {};
    return raw.map((k, v) => MapEntry(k, List<String>.from(v as List)));
  }

  /// Codici sottomodulo insegnabili da chi possiede [quals]
  /// (basta una qualifica tra quelle ammesse per il sottomodulo).
  Set<String> teachableSubmodules(Iterable<String> quals,
      {required bool theory}) {
    final owned = quals.toSet();
    final rules = _ruleMap(theory);
    return {
      for (final e in rules.entries)
        if (e.value.any(owned.contains)) e.key,
    };
  }

  /// Tutti i codici coperti dalle regole AMC (gestiti in automatico).
  Set<String> amcRuleCodes({required bool theory}) =>
      _ruleMap(theory).keys.toSet();
}
