import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/grade_models.dart';
import '../theme.dart';

enum GradeScoreFilter { all, pass, fail, range }

/// Filtri condivisi tab voti (admin + direttore).
class GradeFilters {
  DateTime? dateFrom;
  DateTime? dateTo;
  final Set<int> modules = {}; // vuoto = tutti
  GradeScoreFilter scoreFilter = GradeScoreFilter.all;
  double? scoreMin;
  double? scoreMax;

  bool get isActive =>
      dateFrom != null ||
      dateTo != null ||
      modules.isNotEmpty ||
      scoreFilter != GradeScoreFilter.all;

  void clear() {
    dateFrom = null;
    dateTo = null;
    modules.clear();
    scoreFilter = GradeScoreFilter.all;
    scoreMin = null;
    scoreMax = null;
  }

  bool matches(Grade g) {
    if (modules.isNotEmpty && !modules.contains(g.moduleNumber)) return false;
    if (dateFrom != null) {
      final d = DateTime(g.date.year, g.date.month, g.date.day);
      final from = DateTime(dateFrom!.year, dateFrom!.month, dateFrom!.day);
      if (d.isBefore(from)) return false;
    }
    if (dateTo != null) {
      final d = DateTime(g.date.year, g.date.month, g.date.day);
      final to = DateTime(dateTo!.year, dateTo!.month, dateTo!.day);
      if (d.isAfter(to)) return false;
    }
    switch (scoreFilter) {
      case GradeScoreFilter.all:
        return true;
      case GradeScoreFilter.pass:
        return g.isPassing;
      case GradeScoreFilter.fail:
        return !g.isPassing;
      case GradeScoreFilter.range:
        if (scoreMin != null && g.score < scoreMin!) return false;
        if (scoreMax != null && g.score > scoreMax!) return false;
        return true;
    }
  }

  List<Grade> apply(Iterable<Grade> grades) =>
      grades.where(matches).toList();
}

/// Barra filtri compatta sopra la tabella voti.
class GradeFiltersBar extends StatelessWidget {
  final GradeFilters filters;
  final List modules; // ModuleInfo
  final VoidCallback onChanged;

  const GradeFiltersBar({
    super.key,
    required this.filters,
    required this.modules,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yy');
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Filtri:',
              style: TextStyle(color: kTextDim, fontSize: 12)),
          _chipBtn(
            label: filters.dateFrom == null
                ? 'Da data'
                : 'Da ${fmt.format(filters.dateFrom!)}',
            selected: filters.dateFrom != null,
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: filters.dateFrom ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
              );
              if (d != null) {
                filters.dateFrom = d;
                onChanged();
              }
            },
          ),
          _chipBtn(
            label: filters.dateTo == null
                ? 'A data'
                : 'A ${fmt.format(filters.dateTo!)}',
            selected: filters.dateTo != null,
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: filters.dateTo ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
              );
              if (d != null) {
                filters.dateTo = d;
                onChanged();
              }
            },
          ),
          _chipBtn(
            label: filters.modules.isEmpty
                ? 'Moduli'
                : 'Moduli (${filters.modules.length})',
            selected: filters.modules.isNotEmpty,
            onTap: () => _pickModules(context),
          ),
          DropdownButton<GradeScoreFilter>(
            value: filters.scoreFilter,
            dropdownColor: kSurface,
            underline: const SizedBox(),
            style: const TextStyle(color: kText, fontSize: 12),
            items: const [
              DropdownMenuItem(
                  value: GradeScoreFilter.all, child: Text('Tutti i voti')),
              DropdownMenuItem(
                  value: GradeScoreFilter.pass, child: Text('Solo sufficienti')),
              DropdownMenuItem(
                  value: GradeScoreFilter.fail,
                  child: Text('Solo insufficienti')),
              DropdownMenuItem(
                  value: GradeScoreFilter.range, child: Text('Intervallo…')),
            ],
            onChanged: (v) async {
              if (v == null) return;
              if (v == GradeScoreFilter.range) {
                final ok = await _pickRange(context);
                if (!ok) return;
              } else {
                filters.scoreMin = null;
                filters.scoreMax = null;
              }
              filters.scoreFilter = v;
              onChanged();
            },
          ),
          if (filters.isActive)
            TextButton(
              onPressed: () {
                filters.clear();
                onChanged();
              },
              child: const Text('Azzera', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _chipBtn({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? kPrimary.withOpacity(0.15) : kSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? kPrimary : kBorder),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? kPrimary : kTextDim, fontSize: 12)),
        ),
      );

  Future<void> _pickModules(BuildContext context) async {
    final sel = Set<int>.from(filters.modules);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: kCard,
          title: const Text('Filtra moduli', style: TextStyle(color: kText)),
          content: SizedBox(
            width: 320,
            height: 360,
            child: ListView(
              children: modules
                  .map((m) => CheckboxListTile(
                        dense: true,
                        value: sel.contains(m.number as int),
                        title: Text('M${m.displayCode} — ${m.name}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: kText, fontSize: 12)),
                        onChanged: (v) => setDlg(() {
                          final n = m.number as int;
                          if (v == true) {
                            sel.add(n);
                          } else {
                            sel.remove(n);
                          }
                        }),
                      ))
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                sel.clear();
                setDlg(() {});
              },
              child: const Text('Tutti', style: TextStyle(color: kTextDim)),
            ),
            ElevatedButton(
              onPressed: () {
                filters.modules
                  ..clear()
                  ..addAll(sel);
                Navigator.pop(ctx);
                onChanged();
              },
              child: const Text('Applica'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _pickRange(BuildContext context) async {
    final minCtrl =
        TextEditingController(text: filters.scoreMin?.toStringAsFixed(1) ?? '0');
    final maxCtrl = TextEditingController(
        text: filters.scoreMax?.toStringAsFixed(1) ?? '30');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Intervallo voti', style: TextStyle(color: kText)),
        content: Row(children: [
          Expanded(
            child: TextField(
              controller: minCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: kText),
              decoration: const InputDecoration(labelText: 'Min', isDense: true),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: maxCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: kText),
              decoration: const InputDecoration(labelText: 'Max', isDense: true),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla', style: TextStyle(color: kTextDim)),
          ),
          ElevatedButton(
            onPressed: () {
              filters.scoreMin =
                  double.tryParse(minCtrl.text.replaceAll(',', '.'));
              filters.scoreMax =
                  double.tryParse(maxCtrl.text.replaceAll(',', '.'));
              Navigator.pop(ctx, true);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return ok == true;
  }
}
