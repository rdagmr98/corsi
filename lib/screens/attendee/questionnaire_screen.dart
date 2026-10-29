import 'package:flutter/material.dart';
import '../../models/course_models.dart';
import '../../services/questionnaire_service.dart';
import '../../theme.dart';

/// Compilazione MTOE-F-2-7 (mobile). Torna true se inviato.
class QuestionnaireScreen extends StatefulWidget {
  final Course course;
  final int module;
  final String userId;

  const QuestionnaireScreen({
    super.key,
    required this.course,
    required this.module,
    required this.userId,
  });

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  final _choice = List<int?>.filled(qItems.length, null);
  final _services = List<int?>.filled(qServices.length, null);
  final _sugg = TextEditingController();
  bool _anonymous = true;
  bool _sending = false;

  int get _answered => _choice.where((c) => c != null).length;

  @override
  void dispose() {
    _sugg.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await QuestionnaireService().submit(
        courseId: widget.course.id,
        module: widget.module,
        userId: widget.userId,
        anonymous: _anonymous,
        answers: [
          for (var i = 0; i < qItems.length; i++) qItems[i].opts[_choice[i]!].$2
        ],
        services: _services,
        suggestions: _sugg.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Questionario inviato, grazie.')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is StateError ? e.message : 'Invio non riuscito: $e')));
    }
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(t,
            style: const TextStyle(
                color: kWarning, fontWeight: FontWeight.w600, fontSize: 13)),
      );

  Widget _item(int i) {
    final it = qItems[i];
    return Card(
      color: kCard,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${i + 1}. ${it.q}',
                style: const TextStyle(color: kText, fontSize: 14)),
            RadioGroup<int>(
              groupValue: _choice[i],
              onChanged: (v) => setState(() => _choice[i] = v),
              child: Column(children: [
                for (var j = 0; j < it.opts.length; j++)
                  RadioListTile<int>(
                    value: j,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: kWarning,
                    title: Text(it.opts[j].$1,
                        style: const TextStyle(color: kText, fontSize: 13)),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final complete = _answered == qItems.length;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('Qualità percepita',
            style: TextStyle(color: kText, fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Text(widget.course.title,
              style: const TextStyle(color: kTextDim, fontSize: 12)),
          Text(QuestionnaireService.moduleLabel(widget.course, widget.module),
              style: const TextStyle(
                  color: kText, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _anonymous,
            onChanged: (v) => setState(() => _anonymous = v),
            activeThumbColor: kWarning,
            contentPadding: EdgeInsets.zero,
            title: const Text('Compila in forma anonima',
                style: TextStyle(color: kText, fontSize: 14)),
            subtitle: Text(
                _anonymous
                    ? 'Le risposte non riportano il tuo nome'
                    : 'Le risposte riporteranno il tuo nome',
                style: const TextStyle(color: kTextDim, fontSize: 12)),
          ),
          for (var i = 0; i < qItems.length; i++) ...[
            if (qSections[i + 1] != null) _section(qSections[i + 1]!),
            _item(i),
          ],
          _section('VALUTAZIONE SOGGETTIVA DEI SERVIZI FORNITI DALLA SCUOLA'),
          for (var s = 0; s < qServices.length; s++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(qServices[s],
                      style: const TextStyle(color: kText, fontSize: 13)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (var v = 0; v < qServiceScale.length; v++)
                      ChoiceChip(
                        label: Text(qServiceScale[v],
                            style: const TextStyle(fontSize: 11)),
                        selected: _services[s] == v,
                        onSelected: (on) =>
                            setState(() => _services[s] = on ? v : null),
                      ),
                  ]),
                ],
              ),
            ),
          _section('SUGGERIMENTI'),
          TextField(
            controller: _sugg,
            maxLines: 5,
            minLines: 3,
            style: const TextStyle(color: kText, fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'Facoltativo',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: complete && !_sending ? _send : null,
            child: Text(_sending
                ? 'Invio…'
                : complete
                    ? 'Invia questionario'
                    : 'Rispondi a tutte le voci ($_answered/${qItems.length})'),
          ),
        ],
      ),
    );
  }
}
