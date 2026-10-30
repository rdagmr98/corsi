import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/course_models.dart';
import '../../models/reference_models.dart';
import '../../services/notification_service.dart';
import '../../services/questionnaire_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';

String _n2(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

Color _bandColor(double v) => switch (iqBand(v)) {
      'OTTIMO' => kAccent,
      'BUONO' => kWarning,
      _ => kError,
    };

/// Questionari qualità percepita (MTOE-F-2-7) per modulo: apertura/chiusura,
/// IQ MTOE-A-2-1 (b) e analisi delle risposte. Con periodo impostato (semestre)
/// conta solo i questionari compilati nel periodo e mostra solo quei moduli.
class QuestionnaireKpiCard extends StatefulWidget {
  final Course course;
  final List<ModuleInfo> modules;
  final DateTime? from;
  final DateTime? to;

  const QuestionnaireKpiCard({
    super.key,
    required this.course,
    required this.modules,
    this.from,
    this.to,
  });

  @override
  State<QuestionnaireKpiCard> createState() => _QuestionnaireKpiCardState();
}

class _QuestionnaireKpiCardState extends State<QuestionnaireKpiCard> {
  final _svc = QuestionnaireService();
  final _fmt = DateFormat('dd/MM/yyyy');
  int? _busy;

  bool get _period => widget.from != null || widget.to != null;

  bool _inPeriod(QResponse r) {
    final d = r.date, f = widget.from, t = widget.to;
    if (f != null && d.isBefore(DateTime(f.year, f.month, f.day))) return false;
    if (t != null && d.isAfter(DateTime(t.year, t.month, t.day))) return false;
    return true;
  }

  Future<void> _toggle(ModuleInfo m, bool open) async {
    setState(() => _busy = m.number);
    try {
      final c = widget.course;
      await _svc.setOpen(c, m.number, open: open);
      if (open) {
        // Avvisa solo chi non l'ha ancora compilato (anche alla riapertura).
        final done = _svc.session(c.id, m.number)?.submittedBy ?? const [];
        await NotificationService().createNotifications(
          c.attendeeIds.where((a) => !done.contains(a)).map((a) => (
                userId: a,
                type: 'QUESTIONNAIRE_OPEN',
                message: 'Questionario di qualità percepita aperto: '
                    '${QuestionnaireService.moduleLabel(c, m.number)} (${c.title})',
                metadata: {'course_id': c.id, 'module_number': m.number},
              )),
          dedupeUnread: true,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(open
              ? 'Questionario M${m.displayCode} aperto: notificati i frequentatori'
              : 'Questionario M${m.displayCode} chiuso')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Operazione non riuscita: $e')));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.course.attendeeIds.length;
    final rows = <(ModuleInfo, QSession?, List<QResponse>)>[];
    for (final m in widget.modules) {
      final s = _svc.session(widget.course.id, m.number);
      final rs = [...?s?.responses.where(_inPeriod)];
      if (!_period || rs.isNotEmpty) rows.add((m, s, rs));
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Qualità percepita (MTOE-F-2-7 → KPI MTOE-A-2-1 b)',
              style: TextStyle(
                  color: kText, fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            '${_period ? 'Periodo impostato: solo i questionari compilati nel periodo '
                '(per aprirne uno nuovo togli il periodo). ' : ''}'
            'Apri il questionario a fine modulo: i frequentatori ricevono una '
            'notifica e lo compilano una sola volta, anonimi o con il nome. '
            'Indice = totale/35; IQ = Σ indici / n. ≤1,80 NON ACCETTABILE, '
            '1,81–2,50 BUONO, >2,50 OTTIMO.',
            style: TextStyle(color: kTextDim, fontSize: 11, height: 1.35),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const Text('Nessun questionario compilato nel periodo',
                style: TextStyle(color: kTextDim, fontSize: 12)),
          for (final (m, s, rs) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                SizedBox(
                  width: 48,
                  child: Text('M${m.displayCode}',
                      style: const TextStyle(
                          color: kText,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ),
                Expanded(
                  child: Text(m.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kTextDim, fontSize: 12)),
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                      s == null ? '—' : (s.open ? 'Aperto' : 'Chiuso'),
                      style: TextStyle(
                          color: s?.open == true ? kAccent : kTextDim,
                          fontSize: 12)),
                ),
                SizedBox(
                  width: 60,
                  child: Text(s == null ? '' : '${rs.length}/$total',
                      style: const TextStyle(color: kText, fontSize: 12)),
                ),
                SizedBox(
                  width: 150,
                  child: rs.isEmpty
                      ? const SizedBox()
                      : Text('IQ ${_n2(iqOf(rs)!)} ${iqBand(iqOf(rs)!)}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: _bandColor(iqOf(rs)!),
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                ),
                SizedBox(
                  width: 40,
                  child: rs.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Analisi risposte',
                          icon: const Icon(Icons.analytics_outlined,
                              size: 18, color: kPrimary),
                          onPressed: () => _showAnalysis(m, rs),
                        ),
                ),
                SizedBox(
                  width: 80,
                  child: _busy == m.number
                      ? const Center(
                          child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)))
                      : TextButton(
                          onPressed: _busy != null
                              ? null
                              : () => _toggle(m, s?.open != true),
                          child: Text(s?.open == true ? 'Chiudi' : 'Apri'),
                        ),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  void _showAnalysis(ModuleInfo m, List<QResponse> rs) {
    final n = rs.length;
    final users = UserService();
    final means = [
      for (var i = 0; i < qItems.length; i++)
        rs.map((r) => r.answers[i]).reduce((a, b) => a + b) / n
    ];
    final weak = [
      for (var i = 0; i < qItems.length; i++)
        if (iqBand(means[i]) == 'NON ACCETTABILE') i
    ];
    final dates = rs.map((r) => r.date).toList()..sort();
    final named = rs.where((r) => r.attendeeId != null).length;
    final sugg = rs.where((r) => r.suggestions.isNotEmpty).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final iq = iqOf(rs)!;

    Widget h(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
          child: Text(t,
              style: const TextStyle(
                  color: kWarning, fontWeight: FontWeight.w600, fontSize: 13)),
        );
    Widget kv(String k, String v, [Color c = kText]) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 170,
                child: Text(k,
                    style: const TextStyle(color: kTextDim, fontSize: 12))),
            Expanded(
                child: Text(v,
                    style: TextStyle(
                        color: c, fontSize: 12, fontWeight: FontWeight.w500))),
          ]),
        );
    Widget bar(String label, int count) => Row(children: [
          Expanded(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: count == 0 ? kTextDim : kText, fontSize: 11))),
          SizedBox(
            width: 120,
            child: LinearProgressIndicator(
                value: count / n,
                minHeight: 6,
                backgroundColor: kBorder,
                color: kPrimary),
          ),
          SizedBox(
              width: 36,
              child: Text('$count',
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: kText, fontSize: 11))),
        ]);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('M${m.displayCode} ${m.name} · qualità percepita',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: kText, fontSize: 16)),
        content: SizedBox(
          width: 760,
          height: 560,
          child: ListView(children: [
            h('Dati per il KPI MTOE-A-2-1 (b)'),
            kv('Settore verificato',
                '${widget.course.title} · Modulo ${m.displayCode} ${m.name}'),
            kv('Questionari',
                '$n su ${widget.course.attendeeIds.length} frequentatori '
                    '($named nominativi, ${n - named} anonimi)'),
            if (_period)
              kv('Periodo',
                  '${widget.from == null ? '…' : _fmt.format(widget.from!)} → '
                      '${widget.to == null ? '…' : _fmt.format(widget.to!)}'),
            kv('Compilati',
                '${_fmt.format(dates.first)} → ${_fmt.format(dates.last)}'),
            kv('Somma indici', _n2(rs.fold(0.0, (a, r) => a + r.index))),
            kv('IQ', _n2(iq), _bandColor(iq)),
            kv('Valutazione', iqBand(iq), _bandColor(iq)),
            h('Voci critiche (media ≤ 1,80)'),
            if (weak.isEmpty)
              const Text('Nessuna',
                  style: TextStyle(color: kTextDim, fontSize: 12))
            else
              for (final i in weak)
                kv('${i + 1}. media ${_n2(means[i])}', _stem(i), kError),
            h('Risposte per voce'),
            for (var i = 0; i < qItems.length; i++) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 2),
                child: Row(children: [
                  Expanded(
                      child: Text('${i + 1}. ${_stem(i)}',
                          style: const TextStyle(color: kText, fontSize: 12))),
                  Text(_n2(means[i]),
                      style: TextStyle(
                          color: _bandColor(means[i]),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
              for (final (label, v) in qItems[i].opts)
                bar(label, rs.where((r) => r.answers[i] == v).length),
            ],
            h('Servizi (senza punteggio)'),
            for (var k = 0; k < qServices.length; k++) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Text(qServices[k],
                    style: const TextStyle(color: kText, fontSize: 12)),
              ),
              for (var v = 0; v < qServiceScale.length; v++)
                bar(qServiceScale[v],
                    rs.where((r) => r.services[k] == v).length),
              bar('Non risposto',
                  rs.where((r) => r.services[k] == null).length),
            ],
            h('Suggerimenti (${sugg.length})'),
            if (sugg.isEmpty)
              const Text('Nessun suggerimento',
                  style: TextStyle(color: kTextDim, fontSize: 12)),
            for (final r in sugg)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: kCard, borderRadius: BorderRadius.circular(6)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${r.attendeeId == null ? 'Anonimo' : users.findById(r.attendeeId!)?.fullName ?? 'Frequentatore'}'
                        ' · ${_fmt.format(r.date)}',
                        style: const TextStyle(color: kTextDim, fontSize: 11)),
                    const SizedBox(height: 4),
                    SelectableText(r.suggestions,
                        style: const TextStyle(color: kText, fontSize: 12)),
                  ],
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Chiudi')),
        ],
      ),
    );
  }

  /// Domanda breve: per le scale scuola il nome della voce, altrimenti la
  /// domanda (le voci con domanda ripetuta si distinguono dalle risposte).
  String _stem(int i) {
    final q = qItems[i].q;
    final repeated =
        qItems.where((it) => it.q == q).length > 1 && i < 28;
    return repeated ? '$q (${qItems[i].opts.first.$1})' : q;
  }
}
