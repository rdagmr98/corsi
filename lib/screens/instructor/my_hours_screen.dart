import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../services/course_service.dart';
import '../../services/grade_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';

class InstructorHoursScreen extends ConsumerStatefulWidget {
  final String userId;
  const InstructorHoursScreen({super.key, required this.userId});

  @override
  ConsumerState<InstructorHoursScreen> createState() => _InstructorHoursScreenState();
}

class _InstructorHoursScreenState extends ConsumerState<InstructorHoursScreen> {
  final _gradeService  = GradeService();
  final _userService   = UserService();
  final _courseService = CourseService();

  @override
  void initState() {
    super.initState();
  }

  Future<void> _reload() async {
    await ref.read(authProvider).reloadDb();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lessonH = _gradeService.getConfirmedLessonHoursRollingYear(widget.userId);
    final manualH = _gradeService.getManualTeachingHoursRollingYear(widget.userId);
    final teachH  = lessonH + manualH;
    final lessonsByCourse = _gradeService.getConfirmedLessonHoursByCourse(widget.userId);
    final profH   = _gradeService.getProfessionalUpdateHoursLast2Years(widget.userId);
    final updates = _gradeService.getUpdatesForInstructor(widget.userId);
    final me      = _userService.findById(widget.userId);
    final daaExpiry = me?.daaExpiry;
    final teachOk = teachH >= 6;
    final profOk  = profH >= 35;
    final daaOk   = daaExpiry == null || daaExpiry.isAfter(DateTime.now());

    return RefreshIndicator(
      onRefresh: _reload,
      color: kPrimary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _currencyCard(
              'Ore insegnamento (ultimi 365 giorni)',
              teachH,
              6,
              teachOk,
              Icons.school,
              detail:
                  '${lessonH.toStringAsFixed(0)}h da lezioni confermate · ${manualH.toStringAsFixed(0)}h da registrazioni manuali',
            ),
            const SizedBox(height: 12),
            _currencyCard(
              'Aggiornamento professionale (ultimi 2 anni)',
              profH,
              35,
              profOk,
              Icons.update,
            ),
            if (daaExpiry != null) ...[
              const SizedBox(height: 12),
              _daaCard(daaExpiry, daaOk),
            ],
            if (lessonsByCourse.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Row(
                children: [
                  Text('Lezioni confermate per corso',
                      style: TextStyle(color: kText, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              ...lessonsByCourse.entries.map((e) {
                final course = _courseService.findById(e.key);
                return Card(
                  color: kCard,
                  margin: const EdgeInsets.only(bottom: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  child: ListTile(
                    leading: const Icon(Icons.menu_book, color: kPrimary, size: 20),
                    title: Text(course?.title ?? 'Corso',
                        style: const TextStyle(color: kText, fontSize: 13)),
                    subtitle: const Text('Ore validate ai fini currency',
                        style: TextStyle(color: kTextDim, fontSize: 11)),
                    trailing: Text(
                      '${e.value.toStringAsFixed(0)}h',
                      style: const TextStyle(color: kText, fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              }),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Storico registrazioni', style: TextStyle(color: kText, fontWeight: FontWeight.w600)),
                const SizedBox(),
              ],
            ),
            const SizedBox(height: 8),
            if (updates.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nessun record', style: TextStyle(color: kTextDim)),
              )
            else
              ...updates.reversed.map((u) => Card(
                color: kCard,
                margin: const EdgeInsets.only(bottom: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: ListTile(
                  leading: Icon(
                    u.isTeaching ? Icons.school : Icons.update,
                    color: u.isTeaching ? kPrimary : kAccent,
                    size: 20,
                  ),
                  title: Text(u.description, style: const TextStyle(color: kText, fontSize: 13)),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(u.date),
                      style: const TextStyle(color: kTextDim, fontSize: 11)),
                  trailing: Text(
                    '${u.hours}h',
                    style: const TextStyle(color: kText, fontWeight: FontWeight.bold),
                  ),
                ),
              )),
          ],
        ),
      ),
    );
  }

  Widget _daaCard(DateTime expiry, bool ok) {
    final color = ok ? kAccent : kError;
    return Card(
      color: kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.verified_user, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Aggiornamento biennale DAAA (M10)',
                  style: TextStyle(color: kText, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                'Scade: ${DateFormat('dd/MM/yyyy').format(expiry)}',
                style: TextStyle(color: color, fontSize: 12),
              ),
            ],
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              ok ? 'GO' : 'SCADUTA',
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _currencyCard(String label, double current, double required, bool ok, IconData icon,
      {String? detail}) {
    final color = ok ? kAccent : kError;
    final pct = (current / required).clamp(0.0, 1.0);
    return Card(
      color: kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label, style: const TextStyle(color: kText, fontSize: 13)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    ok ? 'GO' : 'NO GO',
                    style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${current.toStringAsFixed(1)}h',
                  style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Text(
                  ' / ${required.toStringAsFixed(0)}h',
                  style: const TextStyle(color: kTextDim, fontSize: 16),
                ),
              ],
            ),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(detail, style: const TextStyle(color: kTextDim, fontSize: 11)),
            ],
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: pct,
              backgroundColor: kSurface,
              color: color,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
          ],
        ),
      ),
    );
  }
}
