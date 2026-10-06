import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/course_service.dart';
import '../services/grade_service.dart';
import '../theme.dart';

/// Ore di lezione confermate di un istruttore, un blocco espandibile per corso.
/// Le ore degli ultimi 365 giorni sono quelle che contano per la currency;
/// le lezioni più vecchie si vedono in fondo, attenuate.
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
    final fmt = DateFormat('dd/MM/yyyy');
    final entries = byCourse.entries.toList()
      ..sort((a, b) => b.value.first.date.compareTo(a.value.first.date));

    return Column(
      children: entries.map((e) {
        final recent = e.value.where((l) => l.date.isAfter(cutoff)).toList();
        final older = e.value.where((l) => !l.date.isAfter(cutoff)).toList();
        Widget row(({DateTime date, String code, String topic, String type}) l, bool dim) =>
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(children: [
                SizedBox(
                  width: 78,
                  child: Text(fmt.format(l.date),
                      style: TextStyle(color: dim ? kTextDim : kText, fontSize: 11)),
                ),
                SizedBox(
                  width: 54,
                  child: Text(l.type == 'pratica' ? 'Pratica' : 'Teoria',
                      style: TextStyle(
                          color: l.type == 'pratica' ? kAccent : kPrimary, fontSize: 10)),
                ),
                Expanded(
                  child: Text(
                    l.topic.isEmpty || l.topic == l.code ? l.code : '${l.code}  ${l.topic}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: dim ? kTextDim : kText, fontSize: 11),
                  ),
                ),
              ]),
            );
        return Card(
          color: kCard,
          margin: const EdgeInsets.only(bottom: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: const Icon(Icons.menu_book, color: kPrimary, size: 20),
              title: Text(courses.findById(e.key)?.title ?? 'Corso',
                  style: const TextStyle(color: kText, fontSize: 13)),
              subtitle: Text(
                older.isEmpty
                    ? 'Ultimi 365 giorni'
                    : 'Ultimi 365 giorni · ${older.length}h precedenti',
                style: const TextStyle(color: kTextDim, fontSize: 11),
              ),
              trailing: Text('${recent.length}h',
                  style: const TextStyle(color: kText, fontWeight: FontWeight.bold)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (recent.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text('Nessuna lezione negli ultimi 365 giorni',
                        style: TextStyle(color: kWarning, fontSize: 11)),
                  ),
                ...recent.map((l) => row(l, false)),
                if (older.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 4),
                    child: Text('Oltre 365 giorni (non contano per la currency)',
                        style: TextStyle(
                            color: kTextDim, fontSize: 10, fontStyle: FontStyle.italic)),
                  ),
                  ...older.map((l) => row(l, true)),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
