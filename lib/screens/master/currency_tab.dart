import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/user_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/grade_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';

class CurrencyTab extends ConsumerStatefulWidget {
  const CurrencyTab({super.key});

  @override
  ConsumerState<CurrencyTab> createState() => _CurrencyTabState();
}

class _CurrencyTabState extends ConsumerState<CurrencyTab> {
  final _userService = UserService();
  final _gradeService = GradeService();
  List<AppUser> _instructors = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _instructors = _userService.getInstructors());

  Future<void> _reload() async {
    await ref.read(authProvider).reloadDb();
    _load();
  }

  Future<void> _addUpdate(AppUser instructor) async {
    final hoursCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String type = 'professional';
    DateTime date = DateTime.now();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: kCard,
          title: Text('Aggiornamento per ${instructor.fullName}',
              style: const TextStyle(color: kText)),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  dropdownColor: kSurface,
                  style: const TextStyle(color: kText),
                  decoration: const InputDecoration(labelText: 'Tipo', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'teaching', child: Text('Ore insegnamento')),
                    DropdownMenuItem(value: 'professional', child: Text('Aggiornamento professionale')),
                  ],
                  onChanged: (v) => setDlg(() => type = v ?? type),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hoursCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: kText),
                  decoration: const InputDecoration(labelText: 'Ore', isDense: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  style: const TextStyle(color: kText),
                  decoration: const InputDecoration(labelText: 'Descrizione', isDense: true),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(DateFormat('dd/MM/yyyy').format(date),
                        style: const TextStyle(color: kText)),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (d != null) setDlg(() => date = d);
                      },
                      child: const Text('Cambia'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla', style: TextStyle(color: kTextDim)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final hours = double.tryParse(hoursCtrl.text.trim()) ?? 0;
                if (hours <= 0) return;
                await _gradeService.addUpdate(
                  instructorId: instructor.id,
                  type: type,
                  hours: hours,
                  description: descCtrl.text.trim(),
                  date: date,
                );
                _reload();
              },
              child: const Text('Aggiungi'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(
            children: [
              Text('Idoneità Istruttori', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(icon: const Icon(Icons.refresh, color: kTextDim), onPressed: _reload),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Text(
            'Requisiti: ≥6h insegnamento/anno · ≥35h aggiornamento professionale/2 anni',
            style: const TextStyle(color: kTextDim, fontSize: 12),
          ),
        ),
        Expanded(
          child: _instructors.isEmpty
              ? const Center(child: Text('Nessun istruttore', style: TextStyle(color: kTextDim)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: _instructors.length,
                  itemBuilder: (_, i) {
                    final inst = _instructors[i];
                    final teachH = _gradeService.getTeachingHoursThisYear(inst.id);
                    final profH = _gradeService.getProfessionalUpdateHoursLast2Years(inst.id);
                    final teachOk = teachH >= 6;
                    final profOk = profH >= 35;
                    final color = (!teachOk || !profOk) ? kError : kAccent;

                    return Card(
                      color: kCard,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: color.withOpacity(0.3)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              (!teachOk || !profOk) ? Icons.warning_amber : Icons.verified_user,
                              color: color,
                              size: 28,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(inst.fullName, style: const TextStyle(color: kText, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      _pill('Insegnamento ${teachH.toStringAsFixed(1)}h/anno',
                                          teachOk ? kAccent : kError),
                                      const SizedBox(width: 8),
                                      _pill('Aggiornamento ${profH.toStringAsFixed(1)}h/2anni',
                                          profOk ? kAccent : kError),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: kPrimary),
                              tooltip: 'Aggiungi ore',
                              onPressed: () => _addUpdate(inst),
                            ),
                            IconButton(
                              icon: const Icon(Icons.history, color: kTextDim),
                              tooltip: 'Storico',
                              onPressed: () => _showHistory(inst),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(text, style: TextStyle(color: color, fontSize: 11)),
  );

  void _showHistory(AppUser instructor) {
    final updates = _gradeService.getUpdatesForInstructor(instructor.id);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: Text('Storico ${instructor.fullName}', style: const TextStyle(color: kText)),
        content: SizedBox(
          width: 500,
          height: 400,
          child: updates.isEmpty
              ? const Center(child: Text('Nessun record', style: TextStyle(color: kTextDim)))
              : ListView.builder(
                  itemCount: updates.length,
                  itemBuilder: (_, i) {
                    final u = updates[updates.length - 1 - i];
                    return ListTile(
                      leading: Icon(
                        u.isTeaching ? Icons.school : Icons.update,
                        color: u.isTeaching ? kPrimary : kAccent,
                        size: 20,
                      ),
                      title: Text(u.description, style: const TextStyle(color: kText, fontSize: 13)),
                      subtitle: Text(DateFormat('dd/MM/yyyy').format(u.date),
                          style: const TextStyle(color: kTextDim, fontSize: 11)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${u.hours}h',
                              style: const TextStyle(color: kText, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: kError, size: 18),
                            onPressed: () async {
                              await _gradeService.deleteUpdate(u.id);
                              Navigator.pop(ctx);
                              _reload();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }
}

