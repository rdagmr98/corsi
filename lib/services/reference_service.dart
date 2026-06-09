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
}
