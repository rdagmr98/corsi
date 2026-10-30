import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/user_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/grade_service.dart';
import '../../services/notification_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';
import '../../widgets/instructor_lessons_by_course.dart';
import '../../widgets/mobile_ui.dart';

class InstructorHoursScreen extends ConsumerStatefulWidget {
  final String userId;
  const InstructorHoursScreen({super.key, required this.userId});

  @override
  ConsumerState<InstructorHoursScreen> createState() => _InstructorHoursScreenState();
}

class _InstructorHoursScreenState extends ConsumerState<InstructorHoursScreen> {
  final _gradeService   = GradeService();
  final _userService    = UserService();
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
    final hasLessons = _gradeService.getConfirmedLessonsByCourse(widget.userId).isNotEmpty;
    final profH  = _gradeService.getProfessionalUpdateHoursLast2Years(widget.userId);
    final updates = _gradeService.getUpdatesForInstructor(widget.userId);
    final me      = _userService.findById(widget.userId);
    final daaExpiry = me?.daaExpiry;
    final grace   = me == null ? (teach: false, prof: false) : _gradeService.ojtGrace(me);
    final teachOk = teachH >= 6 || grace.teach;
    final profOk  = profH >= 35 || grace.prof;
    final daaOk   = daaExpiry == null ||
        (me?.goOverride ?? false) ||
        daaExpiry.isAfter(DateTime.now());

    return RefreshIndicator(
      onRefresh: _reload,
      color: kPrimary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('Currency istruttore'),
            _currencyCard(
              'Ore insegnamento',
              'ultimi 365 giorni',
              teachH,
              6,
              teachOk,
              Icons.school,
            ),
            const SizedBox(height: 10),
            _currencyCard(
              'Aggiornamento professionale',
              'ultimi 2 anni',
              profH,
              35,
              profOk,
              Icons.update,
            ),
            if (daaExpiry != null) ...[
              const SizedBox(height: 10),
              _daaCard(daaExpiry, daaOk),
            ],
            if (me?.goOverride == true ||
                me?.currencyLostAt != null ||
                me?.ojtKind != null) ...[
              const SizedBox(height: 10),
              _serviceStatusCard(me!),
            ],
            if (hasLessons) ...[
              const SizedBox(height: 12),
              const SectionTitle('Ore per corso · tocca per il dettaglio'),
              InstructorLessonsByCourse(instructorId: widget.userId),
            ],
            const SizedBox(height: 12),
            SectionTitle(
              'Storico registrazioni',
              trailing: TextButton.icon(
                onPressed: () => _showAddUpdateDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Aggiungi'),
                style: TextButton.styleFrom(
                  foregroundColor: kPrimary,
                  backgroundColor: kPrimary.withValues(alpha: 0.12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (updates.isEmpty)
              const EmptyState(Icons.history, 'Nessun record')
            else
              ...updates.reversed.map((u) {
                final IconData icon;
                final Color iconColor;
                if (u.isCurrencyLoss) {
                  icon = Icons.event_busy;
                  iconColor = kError;
                } else if (u.isOjt) {
                  icon = Icons.how_to_reg;
                  iconColor = kWarning;
                } else if (u.isTeaching) {
                  icon = Icons.school;
                  iconColor = kPrimary;
                } else {
                  icon = Icons.update;
                  iconColor = kAccent;
                }
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: mobileCard(tint: u.isPending ? kWarning : null),
                  child: Row(
                    children: [
                      _iconBadge(icon, iconColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(u.description,
                                style: const TextStyle(color: kText, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(DateFormat('dd/MM/yyyy').format(u.date),
                                style: const TextStyle(color: kTextSoft, fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (u.isPending)
                        const Pill('In attesa', kWarning)
                      else if (!u.isCurrencyLoss && !u.isOjt)
                        Text(
                          '${u.hours}h',
                          style: const TextStyle(
                              color: kText, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                );
              }),
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

  Widget _iconBadge(IconData icon, Color color) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 20),
      );

  Widget _serviceStatusCard(AppUser me) {
    final ojt = me.ojtSummary;
    final color = me.goOverride ? kWarning : kError;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: mobileCard(tint: color),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconBadge(Icons.assignment_ind_outlined, color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Stato di servizio',
                    style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                if (me.currencyLostAt != null)
                  Text(
                    'Perdita currency: ${DateFormat('dd/MM/yyyy').format(me.currencyLostAt!)}',
                    style: const TextStyle(color: kError, fontSize: 13),
                  ),
                if (ojt != null) ...[
                  if (me.currencyLostAt != null) const SizedBox(height: 4),
                  Text(
                    '$ojt${me.goOverride ? ' (GO attivo)' : ''}',
                    style: const TextStyle(color: kWarning, fontSize: 13),
                  ),
                  if (me.ojtNote?.trim().isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(me.ojtNote!,
                          style: const TextStyle(color: kTextSoft, fontSize: 12)),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _daaCard(DateTime expiry, bool ok) {
    final color = ok ? kAccent : kError;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: mobileCard(tint: color),
      child: Row(children: [
        _iconBadge(Icons.verified_user, color),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Aggiornamento biennale DAAA (M10)',
                style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Scade: ${DateFormat('dd/MM/yyyy').format(expiry)}',
              style: TextStyle(color: color, fontSize: 13),
            ),
          ],
        )),
        const SizedBox(width: 8),
        Pill(ok ? 'GO' : 'SCADUTA', color, filled: true),
      ]),
    );
  }

  Widget _currencyCard(String label, String period, double current, double required,
      bool ok, IconData icon) {
    final color = ok ? kAccent : kError;
    final pct = (current / required).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: mobileCard(tint: color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBadge(icon, color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: kText, fontSize: 15, fontWeight: FontWeight.w600)),
                    Text(period, style: const TextStyle(color: kTextSoft, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Pill(ok ? 'GO' : 'NO GO', color, filled: true),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${current.toStringAsFixed(1)}h',
                style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w800),
              ),
              Text(
                ' / ${required.toStringAsFixed(0)}h',
                style: const TextStyle(color: kTextSoft, fontSize: 16),
              ),
              const Spacer(),
              Text('${(pct * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: kTextSoft, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: pct,
            backgroundColor: kSurface,
            color: color,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}
