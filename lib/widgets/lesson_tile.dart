import 'package:flutter/material.dart';
import '../models/course_models.dart';
import '../models/reference_models.dart';
import '../models/schedule_models.dart';
import '../services/course_service.dart';
import '../services/reference_service.dart';
import '../services/schedule_service.dart';
import '../theme.dart';

/// Righe lezione (istruttore e frequentatore): orario in chiaro, argomento per esteso e
/// avanzamento "T n/tot h" del sottomodulo, come nel calendario del direttore.
class LessonDescriber {
  final _scheduleService = ScheduleService();
  final _refService = ReferenceService();
  final _courses = <String, Course?>{};
  final _types = <String, CourseTypeInfo?>{};
  final _courseColors = <String, Color>{};
  final _ordinals = <String, int>{};
  final _schedTotals = <String, int>{}; // corso|T/P|sottomodulo → ore calendarizzate
  final _plan = <String, int>{}; // corso|T/P|sottomodulo → monte ore del programma
  final _subNames = <String, String>{}; // corso|sottomodulo → nome
  final _taskNames = <String, String>{}; // corso|task → nome

  static String _norm(String code) => ScheduleService.normalizeSubCode(code);

  LessonDescriber(Iterable<ScheduledLesson> lessons) {
    final courseService = CourseService();
    final ids = lessons.map((l) => l.courseId).toSet().toList()..sort();
    const palette = [kPrimary, kAccent, kWarning, Colors.purple, Colors.teal];
    for (var i = 0; i < ids.length; i++) {
      final cid = ids[i];
      if (ids.length > 1) _courseColors[cid] = palette[i % palette.length];
      final c = _courses[cid] = courseService.findById(cid);
      // Tipo effettivo (base + estensione MIL/MAML), altrimenti i moduli
      // dell'estensione restano senza monte ore.
      final type = _types[cid] = c == null
          ? null
          : _refService.getEffectiveCourseType(c.courseTypeId, c.extensionTypeId, c.mamlCombinationId);
      final sorted = _scheduleService.getLessonsForCourse(cid).where((l) => l.timeSlot > 0).toList()
        ..sort((a, b) {
          final dc = a.date.compareTo(b.date);
          return dc != 0 ? dc : a.timeSlot.compareTo(b.timeSlot);
        });
      for (final l in sorted) {
        final k = '$cid|${l.isTheory ? 'T' : 'P'}|${_norm(l.submoduleCode)}';
        _ordinals[l.id] = _schedTotals[k] = (_schedTotals[k] ?? 0) + 1;
      }
      for (final m in type?.modules ?? <ModuleInfo>[]) {
        for (final s in m.submodules) {
          final nc = _norm(s.code);
          _subNames['$cid|$nc'] = s.name;
          _plan['$cid|T|$nc'] = (_plan['$cid|T|$nc'] ?? 0) + s.theoryHours;
          _plan['$cid|P|$nc'] = (_plan['$cid|P|$nc'] ?? 0) + s.practicalHours;
          for (final t in s.practicalTasks) {
            if (t.name.isNotEmpty) _taskNames['$cid|${t.id}'] = t.name;
          }
        }
      }
    }
  }

  Widget tile(ScheduledLesson l, {Widget? action}) {
    final cid = l.courseId;
    final nc = _norm(l.submoduleCode);
    final typeLabel = l.isTheory ? 'T' : 'P';
    final plan = _plan['$cid|$typeLabel|$nc'] ?? 0;
    // Senza monte ore nel programma il totale è quanto calendarizzato.
    final total = plan > 0 ? plan : (_schedTotals['$cid|$typeLabel|$nc'] ?? 0);
    final ord = _ordinals[l.id];
    // Ore oltre il piano = recuperi: il contatore non supera il piano.
    final hoursStr = ord == null
        ? typeLabel
        : '$typeLabel ${ord > total ? total : ord}/$total h${ord > total ? ' (rec.)' : ''}';
    final slotTime = _types[cid]
        ?.schedule
        .slotsForWeekday(l.date.weekday)
        .where((t) => t.slot == l.timeSlot)
        .firstOrNull;
    var topic = l.topic;
    if (RegExp(r'^\d').hasMatch(topic) && topic.contains('.')) {
      topic = _subNames['$cid|${_norm(topic)}'] ?? _subNames['$cid|$nc'] ?? topic;
    }
    final task = l.taskId == null ? '' : ' · Task ${_taskNames['$cid|${l.taskId}'] ?? l.taskId}';
    final courseColor = _courseColors[cid];

    return Card(
      color: kCard,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: courseColor?.withValues(alpha: 0.6) ?? kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Orario in chiaro: inizio in evidenza, fine sotto.
                SizedBox(
                  width: 50,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(slotTime?.start ?? '${l.timeSlot}ª ora',
                          style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w700)),
                      if (slotTime != null)
                        Text(slotTime.end, style: const TextStyle(color: kTextDim, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (courseColor != null)
                        Text(_courses[cid]?.title ?? '',
                            style: TextStyle(color: courseColor, fontWeight: FontWeight.bold, fontSize: 10),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      Text(topic,
                          style: const TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.w500),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: 5),
                              decoration: BoxDecoration(color: moduleColor(l.moduleNumber), shape: BoxShape.circle),
                            ),
                          ),
                          TextSpan(
                              text: 'M${_refService.moduleLabel(l.moduleNumber)} · '
                                  '${l.isTheory ? 'Teoria' : 'Pratica'} · $hoursStr$task'),
                        ]),
                        style: const TextStyle(color: kTextDim, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                l.confirmed
                    ? const Icon(Icons.check_circle, color: kAccent, size: 18)
                    : const Icon(Icons.schedule, color: kTextDim, size: 18),
              ],
            ),
            if (action != null) ...[const SizedBox(height: 10), action],
          ],
        ),
      ),
    );
  }
}
