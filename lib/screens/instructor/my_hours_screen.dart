import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../services/course_service.dart';
import '../../services/grade_service.dart';
import '../../services/notification_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';

class InstructorHoursScreen extends ConsumerStatefulWidget {
  final String userId;
  const InstructorHoursScreen({super.key, required this.userId});

  @override
  ConsumerState<InstructorHoursScreen> createState() => _InstructorHoursScreenState();
}

class _InstructorHoursScreenState extends ConsumerState<InstructorHoursScreen> {
  final _gradeService   = GradeService();
  final _userService    = UserService();
  final _courseService  = CourseService();
  final _notifService   = NotificationService();

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
                OutlinedButton.icon(
                  onPressed: () => _showAddUpdateDialog(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Aggiungi'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kPrimary,
                    side: const BorderSide(color: kPrimary),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: u.isPending
                      ? BorderSide(color: kWarning.withOpacity(0.4))
                      : BorderSide.none,
                ),
                child: ListTile(
                  leading: Icon(
                    u.isTeaching ? Icons.school : Icons.update,
                    color: u.isTeaching ? kPrimary : kAccent,
                    size: 20,
                  ),
                  title: Text(u.description, style: const TextStyle(color: kText, fontSize: 13)),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(u.date),
                      style: const TextStyle(color: kTextDim, fontSize: 11)),
                  trailing: u.isPending
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: kWarning.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('In attesa',
                              style: TextStyle(color: kWarning, fontSize: 10, fontWeight: FontWeight.bold)),
                        )
                      : Text(
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

  Future<void> _showAddUpdateDialog() async {
    String type = 'professional';
    final descCtrl = TextEditingController();
    final hoursCtrl = TextEditingController();
    DateTime date = DateTime.now();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: kCard,
          title: const Text('Aggiungi aggiornamento', style: TextStyle(color: kText)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tipo', style: TextStyle(color: kTextDim, fontSize: 12)),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                value: type,
                dropdownColor: kSurface,
                style: const TextStyle(color: kText, fontSize: 13),
                items: const [
                  DropdownMenuItem(value: 'professional', child: Text('Aggiornamento professionale')),
                  DropdownMenuItem(value: 'teaching', child: Text('Insegnamento esterno')),
                ],
                onChanged: (v) => setDialog(() => type = v!),
              ),
              const SizedBox(height: 12),
              const Text('Descrizione', style: TextStyle(color: kTextDim, fontSize: 12)),
              const SizedBox(height: 4),
              TextField(
                controller: descCtrl,
                style: const TextStyle(color: kText, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Es. Corso sicurezza volo',
                  hintStyle: TextStyle(color: kTextDim),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Ore', style: TextStyle(color: kTextDim, fontSize: 12)),
              const SizedBox(height: 4),
              TextField(
                controller: hoursCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: kText, fontSize: 13),
                decoration: const InputDecoration(hintText: '0', hintStyle: TextStyle(color: kTextDim)),
              ),
              const SizedBox(height: 12),
              const Text('Data', style: TextStyle(color: kTextDim, fontSize: 12)),
              const SizedBox(height: 4),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setDialog(() => date = picked);
                },
                child: Text(
                  DateFormat('dd/MM/yyyy').format(date),
                  style: const TextStyle(color: kPrimary, fontSize: 13),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla', style: TextStyle(color: kTextDim)),
            ),
            ElevatedButton(
              onPressed: () async {
                final desc = descCtrl.text.trim();
                final hours = double.tryParse(hoursCtrl.text.replaceAll(',', '.')) ?? 0;
                if (desc.isEmpty || hours <= 0) return;
                Navigator.pop(ctx);
                await _gradeService.addPendingUpdate(
                  instructorId: widget.userId,
                  type: type,
                  hours: hours,
                  description: desc,
                  date: date,
                );
                final me = _userService.findById(widget.userId);
                await _notifService.notifyUpdateSubmitted(
                  instructorName: me?.fullName ?? widget.userId,
                  updateDescription: desc,
                );
                _reload();
              },
              child: const Text('Invia'),
            ),
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
