import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/user_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/amc_docx_export.dart';
import '../../services/amc_service.dart';
import '../../services/course_service.dart';
import '../../services/gh_db_service.dart';
import '../../services/grade_service.dart';
import '../../services/reference_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';
import '../../utils/snackbar.dart';

class AmcTab extends ConsumerStatefulWidget {
  const AmcTab({super.key});
  @override
  ConsumerState<AmcTab> createState() => _AmcTabState();
}

class _AmcTabState extends ConsumerState<AmcTab>
    with SingleTickerProviderStateMixin {
  final _userService        = UserService();
  final _courseService      = CourseService();
  final _db                 = GhDbService();
  final _referenceService   = ReferenceService();
  final _gradeService       = GradeService();
  late final TabController _tabs = TabController(length: 2, vsync: this);

  String? _selectedCourseId;
  final _searchCtrl = TextEditingController();
  String _search = '';
  bool _onlyGo = true; // false = tutti gli istruttori, true = solo i GO

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
        () => setState(() => _search = _searchCtrl.text.trim().toLowerCase()));
    final active = _courseService.getAllCourses().where((c) => c.isActive).toList();
    if (active.isNotEmpty) _selectedCourseId = active.first.id;
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    await ref.read(authProvider).reloadDb();
    setState(() {});
  }

  // ── Dati AMC ──────────────────────────────────────────────────────────────
  Map<String, List<String>> _grid(bool theory) {
    final key = theory ? 'theoryGrid' : 'practiceGrid';
    final raw = _db.amcData[key] as Map<String, dynamic>? ?? {};
    return raw.map((k, v) => MapEntry(k, List<String>.from(v as List)));
  }

  Map<String, String> _submoduleNames() {
    final fromAmc = Map<String, String>.from(_db.amcData['submoduleNames'] as Map? ?? {});
    if (fromAmc.isNotEmpty) return fromAmc;
    // Build from reference.json as fallback
    final result = <String, String>{};
    for (final ct in _referenceService.getCourseTypes()) {
      for (final m in ct.modules) {
        for (final s in m.submodules) {
          result[s.code] = s.name;
        }
      }
    }
    return result;
  }

  Map<String, AppUser> _uidToUser() =>
      {for (final u in _userService.getAllUsers()) u.id: u};

  // Gli istruttori sono assegnati a tutti i corsi.
  Set<String> _courseInstructors() =>
      _selectedCourseId == null
          ? {}
          : {for (final u in _userService.getInstructors()) u.id};

  // ── Sorting numerico corretto: 1.1 < 1.2 < ... < 3.1 < 3.11 < 11A.1 < 11B.1 < 12.1 ──
  int _compareCode(String a, String b) {
    final pa = _parseCode(a);
    final pb = _parseCode(b);
    if (pa[0] != pb[0]) return (pa[0] as int).compareTo(pb[0] as int);
    final la = pa[1] as String, lb = pb[1] as String;
    if (la != lb) return la.compareTo(lb);
    return (pa[2] as int).compareTo(pb[2] as int);
  }

  List _parseCode(String code) {
    final parts = code.split('.');
    final m = RegExp(r'^(\d+)([A-Za-z]?)$').firstMatch(parts[0]);
    return [
      m != null ? (int.tryParse(m.group(1)!) ?? 0) : 0,
      m?.group(2)?.toUpperCase() ?? '',
      parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    ];
  }

  List<String> _sortedCodes(Map<String, List<String>> grid) {
    return grid.keys.toList()..sort(_compareCode);
  }

  @override
  Widget build(BuildContext context) {
    final allCourses = _courseService.getAllCourses();
    final uidToUser  = _uidToUser();
    final subNames   = _submoduleNames();
    final courseUids = _courseInstructors();
    final now        = DateTime.now();
    final goUids     = <String>{
      for (final u in uidToUser.values) if (_gradeService.isGo(u, now: now)) u.id
    };
    final goUidsM10  = <String>{
      for (final u in uidToUser.values)
        if (_gradeService.isGo(u, now: now, moduleNumber: 10)) u.id
    };

    return Column(children: [
      // ── Toolbar: titolo, ricerca, filtri ─────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        child: Row(children: [
          Text('Tabella AMC', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 24),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: kText, fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Cerca sottomodulo (codice o nome)…',
                prefixIcon: const Icon(Icons.search, size: 18, color: kTextDim),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16, color: kTextDim),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _goToggle(),
          const SizedBox(width: 12),
          DropdownButton<String?>(
            value: _selectedCourseId,
            dropdownColor: kSurface,
            style: const TextStyle(color: kText, fontSize: 12),
            hint: const Text('Tutti i corsi',
                style: TextStyle(color: kTextDim, fontSize: 12)),
            underline: const SizedBox(),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Tutti i corsi',
                    style: TextStyle(color: kTextDim, fontSize: 12)),
              ),
              ...allCourses.map((c) => DropdownMenuItem<String?>(
                    value: c.id,
                    child: Text(c.title,
                        style: const TextStyle(color: kText, fontSize: 12)),
                  )),
            ],
            onChanged: (v) => setState(() => _selectedCourseId = v),
          ),
          IconButton(
              tooltip: 'Ricarica',
              icon: const Icon(Icons.refresh, color: kTextDim),
              onPressed: _reload),
        ]),
      ),
      // ── Legenda e azioni (pulsanti con etichetta: restano leggibili anche
      // se il glifo dell'icona manca dalla cache) ─────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
        child: Row(children: [
          _dot(kAccent), const SizedBox(width: 4),
          const Text('Nel corso selezionato + abilitato AMC',
              style: TextStyle(color: kTextDim, fontSize: 11)),
          const SizedBox(width: 16),
          _dot(kPrimary), const SizedBox(width: 4),
          const Text('Solo abilitato AMC',
              style: TextStyle(color: kTextDim, fontSize: 11)),
          const Spacer(),
          _action(Icons.rule, 'Criteri', 'Titoli e licenze richiesti per sottomodulo',
              _editRules),
          _action(Icons.description_outlined, 'Stampa criteri',
              'Word, tabelle criteri dell\'ANNESSO MTOE-P-3-1',
              () => AmcDocxExport.download(_referenceService.amcRuleMap(true),
                  _referenceService.amcRuleMap(false))),
          _action(Icons.groups_outlined, 'Stampa elenco personale',
              'Word, elenco personale T1/T2 dell\'annesso con gli istruttori '
                  'mostrati (${_onlyGo ? 'solo GO' : 'tutti'})',
              () => _printPersonnel(uidToUser, goUids, goUidsM10)),
        ]),
      ),
      TabBar(
        controller: _tabs,
        labelColor: kPrimary,
        unselectedLabelColor: kTextDim,
        indicatorColor: kPrimary,
        tabs: const [
          Tab(text: 'TEORIA'),
          Tab(text: 'PRATICA'),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: [
            _buildGrid(theory: true,  uidToUser: uidToUser,
                subNames: subNames, courseUids: courseUids,
                goUids: goUids, goUidsM10: goUidsM10),
            _buildGrid(theory: false, uidToUser: uidToUser,
                subNames: subNames, courseUids: courseUids,
                goUids: goUids, goUidsM10: goUidsM10),
          ],
        ),
      ),
    ]);
  }

  Widget _buildGrid({
    required bool theory,
    required Map<String, AppUser> uidToUser,
    required Map<String, String> subNames,
    required Set<String> courseUids,
    required Set<String> goUids,
    required Set<String> goUidsM10,
  }) {
    final grid = _grid(theory);
    var codes = _sortedCodes(grid);

    if (_search.isNotEmpty) {
      codes = codes.where((c) {
        final name = subNames[c]?.toLowerCase() ?? '';
        return c.toLowerCase().contains(_search) || name.contains(_search);
      }).toList();
    }

    if (codes.isEmpty) {
      return Center(
        child: Text(
          _search.isNotEmpty
              ? 'Nessun sottomodulo per "$_search"'
              : 'Nessun dato AMC',
          style: const TextStyle(color: kTextDim),
        ),
      );
    }

    // Pre-computa coppie (code, showHeader) prima del ListView per evitare
    // bug di ordinamento dovuti al rendering lazy di ListView.builder.
    String moduleKey(String code) {
      final m = RegExp(r'^(\d+[A-Za-z]?)').firstMatch(code);
      return m?.group(1) ?? code;
    }

    final items = <({String code, bool showHeader, String modKey})>[];
    {
      String? lastMod;
      for (final c in codes) {
        final mk = moduleKey(c);
        items.add((code: c, showHeader: mk != lastMod, modKey: mk));
        lastMod = mk;
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item    = items[i];
        final code    = item.code;
        final allUids = grid[code] ?? [];
        final uids    = _shown(code, allUids, goUids, goUidsM10);
        final subName = subNames[code] ?? '';

        final showHeader = item.showHeader;

        final inCourse    = uids.where((uid) => courseUids.contains(uid)).toList();
        final notInCourse = _selectedCourseId != null
            ? uids.where((uid) => !courseUids.contains(uid)).toList()
            : uids;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  'Modulo ${item.modKey}',
                  style: const TextStyle(color: kTextDim, fontSize: 11,
                      fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
            Container(
              margin: const EdgeInsets.only(bottom: 3),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: kBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // Codice
                  SizedBox(
                    width: 54,
                    child: Text(code,
                        style: const TextStyle(color: kText, fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                  // Nome sottomodulo (una riga, intero nel tooltip)
                  SizedBox(
                    width: 300,
                    child: Tooltip(
                      message: subName,
                      child: Text(
                        subName.isNotEmpty ? subName : '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: subName.isNotEmpty ? kTextDim : kBorder,
                            fontSize: 11),
                      ),
                    ),
                  ),
                  // Totale, accanto al nome invece che isolato sul bordo
                  SizedBox(
                    width: 32,
                    child: Text('${uids.length}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: uids.isEmpty ? kBorder : kTextDim,
                            fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  // Istruttori
                  Expanded(
                    child: Wrap(
                      spacing: 4, runSpacing: 4,
                      children: [
                        ...inCourse.map((uid) => _chip(
                            uidToUser[uid]?.cognome ?? uid, kAccent,
                            filled: true)),
                        ...notInCourse.map((uid) => _chip(
                            uidToUser[uid]?.cognome ?? uid, kPrimary)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Istruttori della riga secondo il filtro «Solo GO» (modulo 10: GO M10).
  List<String> _shown(String code, List<String> uids, Set<String> goUids,
      Set<String> goUidsM10) {
    if (!_onlyGo) return uids;
    final go = code.startsWith('10.') ? goUidsM10 : goUids;
    return uids.where(go.contains).toList();
  }

  Future<void> _printPersonnel(Map<String, AppUser> users, Set<String> goUids,
      Set<String> goUidsM10) async {
    Map<String, List<String>> shown(bool theory) {
      final grid = _grid(theory);
      return {
        for (final c in _sortedCodes(grid))
          c: _shown(c, grid[c]!, goUids, goUidsM10)
      };
    }

    // titolo degli istruttori = sigle dell'annesso (TI - ETP - EM), se compilato
    String label(AppUser u) {
      final t = u.titolo?.trim() ?? '';
      return '${u.cognome} ${u.nome}${t.isEmpty ? '' : ' ($t)'}';
    }

    try {
      await AmcDocxExport.downloadPersonnel(shown(true), shown(false),
          {for (final u in users.values) u.id: label(u)});
    } catch (e) {
      showAppError('Stampa elenco personale non riuscita: $e');
    }
  }

  Widget _action(IconData icon, String label, String tip, VoidCallback onTap) =>
      Tooltip(
        message: tip,
        child: TextButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      );

  Widget _chip(String name, Color color, {bool filled = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: filled ? color.withOpacity(0.2) : color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withOpacity(0.5)),
    ),
    child: Text(name,
        style: TextStyle(color: color, fontSize: 10,
            fontWeight: filled ? FontWeight.bold : FontWeight.normal)),
  );

  // ── Editor criteri (reference.amcRules): sottomodulo × titolo/licenza ──
  Future<void> _editRules() async {
    final quals = _referenceService.amcQualifications();
    final rules = {
      for (final t in [true, false])
        t: _referenceService
            .amcRuleMap(t)
            .map((k, v) => MapEntry(k, v.toSet())),
    };
    final names = _submoduleNames();
    var theory = true;
    const cw = 26.0, rh = 22.0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final r = rules[theory]!;
        final codes = r.keys.toList();
        final cols = theory
            ? quals
            : quals
                .where((q) => AmcDocxExport.practiceCols.contains(q.id))
                .toList();
        // Intestazione gruppi (Laurea, B1.1, ... B2, Altro)
        final groups = <(String, int)>[];
        for (final q in cols) {
          final g = q.group.replaceFirst('Categoria ', '');
          if (groups.isNotEmpty && groups.last.$1 == g) {
            groups.last = (g, groups.last.$2 + 1);
          } else {
            groups.add((g, 1));
          }
        }
        const lead = 56.0 + 220.0;
        return AlertDialog(
          title: Row(children: [
            const Flexible(
              child: Text('Criteri AMC: titoli e licenze per sottomodulo',
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 16),
            for (final t in [true, false]) ...[
              ChoiceChip(
                label: Text(t ? 'Teoria' : 'Pratica'),
                selected: theory == t,
                onSelected: (_) => setD(() => theory = t),
              ),
              const SizedBox(width: 6),
            ],
          ]),
          content: SizedBox(
            width: lead + quals.length * cw + 24,
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const SizedBox(width: lead),
                for (final g in groups)
                  Container(
                    width: g.$2 * cw,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                        border: Border(
                            left: BorderSide(color: kBorder),
                            bottom: BorderSide(color: kBorder))),
                    child: Text(g.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kTextDim, fontSize: 10)),
                  ),
              ]),
              Row(children: [
                const SizedBox(width: lead),
                for (final q in cols)
                  SizedBox(
                    width: cw,
                    height: 92,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Tooltip(
                        message: '${q.group} · ${q.label}',
                        child: Text(q.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: kText, fontSize: 10)),
                      ),
                    ),
                  ),
              ]),
              const Divider(height: 1, color: kBorder),
              Expanded(
                child: ListView.builder(
                  itemCount: codes.length,
                  itemExtent: rh,
                  itemBuilder: (_, i) {
                    final code = codes[i];
                    final set = r[code]!;
                    return Row(children: [
                      SizedBox(
                        width: 56,
                        child: Text(code,
                            style: const TextStyle(
                                color: kText,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                      SizedBox(
                        width: 220,
                        child: Text(names[code] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: kTextDim, fontSize: 10)),
                      ),
                      for (final q in cols)
                        InkWell(
                          onTap: () => setD(() =>
                              set.contains(q.id) ? set.remove(q.id) : set.add(q.id)),
                          child: Container(
                            width: cw,
                            height: rh,
                            decoration: BoxDecoration(
                              color: set.contains(q.id) ? kPrimary : null,
                              border: Border.all(color: kBorder, width: 0.5),
                            ),
                          ),
                        ),
                    ]);
                  },
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annulla')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salva e ricalcola griglie')),
          ],
        );
      }),
    );
    if (ok != true) return;

    List<String> ordered(Set<String> s) =>
        [for (final q in quals) if (s.contains(q.id)) q.id];
    try {
      await _referenceService.saveAmcRules(
        rules[true]!.map((k, v) => MapEntry(k, ordered(v))),
        rules[false]!.map((k, v) => MapEntry(k, ordered(v))),
      );
      await AmcService().reapplyAll();
      showAppInfo('Criteri salvati, griglie AMC ricalcolate');
    } catch (e) {
      showAppError('Salvataggio criteri non riuscito: $e');
    }
    if (mounted) setState(() {});
  }

  Widget _dot(Color color) => Container(
    width: 10, height: 10,
    decoration: BoxDecoration(
        color: color.withOpacity(0.5),
        shape: BoxShape.circle,
        border: Border.all(color: color)),
  );

  Widget _goToggle() => InkWell(
    borderRadius: BorderRadius.circular(6),
    onTap: () => setState(() => _onlyGo = !_onlyGo),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _onlyGo ? kAccent.withOpacity(0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _onlyGo ? kAccent : kBorder),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_onlyGo ? Icons.check_circle : Icons.filter_alt_outlined,
            size: 14, color: _onlyGo ? kAccent : kTextDim),
        const SizedBox(width: 5),
        Text(_onlyGo ? 'Solo GO' : 'Tutti',
            style: TextStyle(
                fontSize: 11,
                color: _onlyGo ? kAccent : kTextDim,
                fontWeight: _onlyGo ? FontWeight.bold : FontWeight.normal)),
      ]),
    ),
  );
}
