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
  // For maml courses, pass mamlCombinationId to filter/override modules per the VFI table.
  CourseTypeInfo? getEffectiveCourseType(String typeId, [String? extensionTypeId, String? mamlCombinationId]) {
    final base = getCourseType(typeId);
    if (base == null) return null;
    CourseTypeInfo result = base;
    if (extensionTypeId != null) {
      final ext = getCourseType(extensionTypeId);
      if (ext != null) {
        result = CourseTypeInfo(
          id: '${base.id}+${ext.id}',
          code: base.code,
          name: base.name,
          category: base.category,
          maxAttendees: base.maxAttendees,
          schedule: base.schedule,
          modules: [...base.modules, ...ext.modules],
          vfiCombinations: base.vfiCombinations,
        );
      }
    }
    if (mamlCombinationId != null && result.vfiCombinations.isNotEmpty) {
      result = _applyMamlCombination(result, mamlCombinationId);
    }
    return result;
  }

  CourseTypeInfo _applyMamlCombination(CourseTypeInfo base, String comboId) {
    final combo = base.vfiCombinations.where((c) => c.id == comboId).firstOrNull;
    if (combo == null) return base;
    final hoursMap = {for (final mh in combo.moduleHours) mh.moduleNumber: mh};
    final filteredModules = base.modules
        .where((m) => hoursMap.containsKey(m.number))
        .map((m) {
          final h = hoursMap[m.number]!;
          return ModuleInfo(
            number: m.number,
            label: m.label,
            name: m.name,
            theoryHours: h.theoryHours,
            practicalHours: h.practicalHours,
            examQuestions: m.examQuestions,
            examMinutes: m.examMinutes,
            assessmentCount: m.assessmentCount,
            submodules: m.submodules,
          );
        })
        .toList();
    return CourseTypeInfo(
      id: '${base.id}+$comboId',
      code: base.code,
      name: base.name,
      category: base.category,
      maxAttendees: base.maxAttendees,
      schedule: base.schedule,
      modules: filteredModules,
      vfiCombinations: base.vfiCombinations,
    );
  }

  Future<void> saveCourseTypes(List<CourseTypeInfo> types) async {
    final updated = {..._ref, 'courseTypes': types.map((t) => t.toJson()).toList()};
    await _db.saveReference(updated);
    invalidateLabelCache();
  }

  // Prossimo id task pratica libero (univoco su tutto reference.json).
  int nextTaskId() {
    var maxId = 0;
    for (final ct in getCourseTypes()) {
      for (final m in ct.modules) {
        for (final s in m.submodules) {
          for (final t in s.practicalTasks) {
            if (t.id > maxId) maxId = t.id;
          }
        }
      }
    }
    return maxId + 1;
  }

  bool isCourseTypeInUse(String id) => _db.courses
      .any((c) => c['course_type_id'] == id || c['extension_type_id'] == id);

  // Task pratica dato il tipo corso effettivo e il taskId della lezione (può essere int
  // per i task base o String per i task MIL legacy: in quel caso non c'è corrispondenza
  // in reference.json e si torna null).
  PracticalTask? findTask(CourseTypeInfo? effectiveType, dynamic taskId) {
    if (effectiveType == null || taskId == null) return null;
    for (final m in effectiveType.modules) {
      for (final s in m.submodules) {
        for (final t in s.practicalTasks) {
          if (t.id == taskId) return t;
        }
      }
    }
    return null;
  }

  String? taskName(CourseTypeInfo? effectiveType, dynamic taskId) {
    final t = findTask(effectiveType, taskId);
    return (t != null && t.name.isNotEmpty) ? t.name : null;
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

  /// Dato un insieme di sottomoduli effettivamente insegnati (codici già
  /// normalizzati), restituisce il set minimo di qualifiche AMC che copre
  /// tutti i soggetti (greedy set cover).
  Set<String> reverseEngineerQuals(
      Set<String> taughtTheory, Set<String> taughtPractice) {
    final theoryMap = _ruleMap(true);
    final practiceMap = _ruleMap(false);

    // Soggetto (code, isTheory) → lista qualifiche che lo ammettono
    final requirements = <(String, bool), List<String>>{};
    for (final code in taughtTheory) {
      final qs = theoryMap[code];
      if (qs != null && qs.isNotEmpty) requirements[(code, true)] = qs;
    }
    for (final code in taughtPractice) {
      final qs = practiceMap[code];
      if (qs != null && qs.isNotEmpty) requirements[(code, false)] = qs;
    }
    if (requirements.isEmpty) return {};

    // qualCovers[qId] = soggetti coperti da quella qualifica
    final qualCovers = <String, Set<(String, bool)>>{};
    for (final entry in requirements.entries) {
      for (final qId in entry.value) {
        qualCovers.putIfAbsent(qId, () => {}).add(entry.key);
      }
    }

    // Greedy set cover
    final selected = <String>{};
    final uncovered = requirements.keys.toSet();
    while (uncovered.isNotEmpty) {
      String? best;
      int bestCount = 0;
      for (final entry in qualCovers.entries) {
        if (selected.contains(entry.key)) continue;
        final n = entry.value.intersection(uncovered).length;
        if (n > bestCount) {
          bestCount = n;
          best = entry.key;
        }
      }
      if (best == null) break;
      selected.add(best);
      uncovered.removeAll(qualCovers[best]!);
    }
    return selected;
  }
}
