import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/reference_models.dart';
import '../services/course_service.dart';
import '../services/grade_service.dart';
import '../services/reference_service.dart';
import '../theme.dart';

/// Ore di lezione confermate di un istruttore: un blocco espandibile per
/// corso, dentro un blocco espandibile per modulo. Le ore degli ultimi 365
/// giorni sono quelle che contano per la currency; le più vecchie restano
/// in elenco, attenuate.
class InstructorLessonsByCourse extends StatelessWidget {
  final String instructorId;
  const InstructorLessonsByCourse({super.key, required this.instructorId});

  @override
  Widget build(BuildContext context) {
    final byCourse = GradeService().getConfirmedLessonsByCourse(instructorId);
    if (byCourse.isEmpty) {
      return const Text('Nessuna lezione confermata',
          style: TextStyle(color: kTextDim, fontSize: 12));
    }
    final cutoff = DateTime.now().subtract(const Duration(days: 365));
    final courses = CourseService();
    final refs = ReferenceService();
    final fmt = DateFormat('dd/MM/yyyy');
    final entries = byCourse.entries.toList()
      ..sort((a, b) => b.value.first.date.compareTo(a.value.first.date));

    Widget row(({DateTime date, int module, String code, String topic, String type}) l) {
      final dim = !l.date.isAfter(cutoff);
      return Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(children: [
          SizedBox(
            width: 80,
            child: Text(fmt.format(l.date),
                softWrap: false,
                style: TextStyle(color: dim ? kTextDim : kText, fontSize: 11)),
          ),
          SizedBox(
            width: 58,
            child: Text(l.type == 'pratica' ? 'Pratica' : 'Teoria',
                style: TextStyle(color: l.type == 'pratica' ? kAccent : kPrimary, fontSize: 10)),
          ),
          Expanded(
            child: Text(
              l.topic.isEmpty || l.topic == l.code ? l.code : '${l.code}  ${l.topic}',
              style: TextStyle(color: dim ? kTextDim : kText, fontSize: 11),
            ),
          ),
        ]),
      );
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Column(
        children: entries.map((e) {
          final course = courses.findById(e.key);
          final type = course == null
              ? null
              : refs.getEffectiveCourseType(course.courseTypeId, course.extensionTypeId, course.mamlCombinationId);
          final moduleNames = {for (final m in type?.modules ?? <ModuleInfo>[]) m.number: m.name};
          final recent = e.value.where((l) => l.date.isAfter(cutoff)).length;
          final older = e.value.length - recent;
          final byModule = <int, List<({DateTime date, int module, String code, String topic, String type})>>{};
          for (final l in e.value) {
            byModule.putIfAbsent(l.module, () => []).add(l);
          }
          final modules = byModule.keys.toList()..sort();
          return Card(
            color: kCard,
            margin: const EdgeInsets.only(bottom: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              leading: const Icon(Icons.menu_book, color: kPrimary, size: 20),
              title: Text(course?.title ?? 'Corso', style: const TextStyle(color: kText, fontSize: 13)),
              subtitle: Text(
                older == 0
                    ? 'Ultimi 365 giorni'
                    : 'Ultimi 365 giorni · ${older}h precedenti in grigio',
                style: const TextStyle(color: kTextDim, fontSize: 11),
              ),
              trailing: Text('${recent}h', style: const TextStyle(color: kText, fontWeight: FontWeight.bold)),
              childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              children: [
                for (final m in modules)
                  ExpansionTile(
                    dense: true,
                    tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: moduleColor(m), shape: BoxShape.circle),
                    ),
                    title: Text(
                      m == 0 ? 'Altro' : 'M${refs.moduleLabel(m)}  ${moduleNames[m] ?? ''}',
                      style: const TextStyle(color: kText, fontSize: 12),
                    ),
                    trailing: Text(
                      '${byModule[m]!.where((l) => l.date.isAfter(cutoff)).length}h',
                      style: const TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: byModule[m]!.map(row).toList(),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
