import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/user_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/amc_docx_export.dart';
import '../../services/amc_service.dart';
import '../../services/conferimento_docx_export.dart';
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
  final _db                 = GhDbService();
  final _referenceService   = ReferenceService();
  final _gradeService       = GradeService();
  late final TabController _tabs = TabController(length: 2, vsync: this);

  final _searchCtrl = TextEditingController();
  String _search = '';
  bool _onlyGo = true; // false = tutti gli istruttori, true = solo i GO

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
        () => setState(() => _search = _searchCtrl.text.trim().toLowerCase()));
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

  List<String> _sortedCodes(Map<String, List<String>> grid) {
    return grid.keys.toList()..sort(ConferimentoDocxExport.compareCode);
  }

  @override
  Widget build(BuildContext context) {
    final uidToUser  = _uidToUser();
    final subNames   = _submoduleNames();
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
          IconButton(
              tooltip: 'Ricarica',
              icon: const Icon(Icons.refresh, color: kTextDim),
              onPressed: _reload),
        ]),
      ),
      // ── Azioni (pulsanti con etichetta: restano leggibili anche se il
      // glifo dell'icona manca dalla cache) ──────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
        child: Row(children: [
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
          _action(Icons.workspace_premium_outlined, 'Stampa conferimenti',
              'Word, conferimento dell\'abilitazione all\'insegnamento: uno o più istruttori in un file',
              _printConferimenti),
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
                subNames: subNames,
                goUids: goUids, goUidsM10: goUidsM10),
            _buildGrid(theory: false, uidToUser: uidToUser,
                subNames: subNames,
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
                        for (final uid in uids)
                          _chip(uidToUser[uid]?.cognome ?? uid),
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

  /// Scrive una chiave di amc.json lasciando intatte le altre.
  Future<void> _saveAmcKey(String key, Object value) =>
      _db.saveAmc(Map<String, dynamic>.from(_db.amcData)..[key] = value);

  /// Gruppi firma del conferimento (TM propone, AM conferisce): righe libere.
  Future<(String, String)?> _editFirme(String tm, String am) {
    final tmCtrl = TextEditingController(text: tm);
    final amCtrl = TextEditingController(text: am);
    Widget field(String label, TextEditingController c, String hint) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: kTextDim, fontSize: 12)),
            const SizedBox(height: 4),
            TextField(
              controller: c,
              minLines: 2,
              maxLines: 4,
              style: const TextStyle(color: kText, fontSize: 13),
              decoration: InputDecoration(isDense: true, hintText: hint),
            ),
          ],
        );
    return showDialog<(String, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gruppi firma del conferimento'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            field('Propone: Training Manager', tmCtrl,
                'IL TRAINING MANAGER\nGrado Nome COGNOME'),
            const SizedBox(height: 14),
            field('Conferisce: Accountable Manager (Comandante)', amCtrl,
                'IL COMANDANTE\nGrado Nome COGNOME'),
            const SizedBox(height: 8),
            const Text('Una voce per riga: carica, poi grado e nome.',
                style: TextStyle(color: kTextDim, fontSize: 11)),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla')),
          ElevatedButton(
              onPressed: () =>
                  Navigator.pop(ctx, (tmCtrl.text.trim(), amCtrl.text.trim())),
              child: const Text('Salva')),
        ],
      ),
    );
  }

  /// Materie assegnate dall'AM: sottoinsieme di quelle insegnabili (griglia AMC).
  Future<(Set<String>, Set<String>)?> _editAssegnate(
    String who,
    List<String> teachT,
    List<String> teachP,
    Set<String> selT,
    Set<String> selP,
    Map<String, String> subNames,
  ) {
    final t = {...selT}, p = {...selP};
    return showDialog<(Set<String>, Set<String>)>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        List<Widget> section(String title, List<String> codes, Set<String> sel) {
          final bool? all = sel.isEmpty
              ? false
              : (sel.length == codes.length ? true : null);
          return [
            CheckboxListTile(
              tristate: true,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: all,
              title: Text('$title  ${sel.length}/${codes.length}',
                  style: const TextStyle(
                      color: kText, fontSize: 13, fontWeight: FontWeight.w600)),
              onChanged: codes.isEmpty
                  ? null
                  : (_) => setDlg(
                      () => all == true ? sel.clear() : sel.addAll(codes)),
            ),
            if (codes.isEmpty)
              const Padding(
                padding: EdgeInsets.only(left: 24, bottom: 8),
                child: Text('Nessun sottomodulo insegnabile',
                    style: TextStyle(color: kTextDim, fontSize: 12)),
              ),
            for (final c in codes)
              CheckboxListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 24),
                controlAffinity: ListTileControlAffinity.leading,
                value: sel.contains(c),
                title: Text(
                  subNames[c] != null ? '$c  ${subNames[c]}' : c,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kText, fontSize: 12),
                ),
                onChanged: (v) =>
                    setDlg(() => v == true ? sel.add(c) : sel.remove(c)),
              ),
          ];
        }

        return AlertDialog(
          title: Text('Materie assegnate · $who',
              overflow: TextOverflow.ellipsis),
          content: SizedBox(
            width: 560,
            height: 520,
            child: ListView(children: [
              const Text(
                  "L'Accountable Manager assegna le materie tra quelle che "
                  "l'istruttore può insegnare (griglia AMC).",
                  style: TextStyle(color: kTextDim, fontSize: 11)),
              ...section('Teoria', teachT, t),
              const Divider(color: kBorder),
              ...section('Pratica', teachP, p),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annulla')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, (t, p)),
                child: const Text('Conferma')),
          ],
        );
      }),
    );
  }

  Future<void> _printConferimenti() async {
    final theoryGrid = _grid(true);
    final practiceGrid = _grid(false);
    final subNames = _submoduleNames();
    final firme = _db.amcData['conferimento_firme'] as Map? ?? const {};
    var firmaTm = (firme['tm'] as String?) ?? '';
    var firmaAm = (firme['am'] as String?) ?? '';
    final registro = _db.amcData['conferimenti'] as Map? ?? const {};

    final teachT = <String, List<String>>{};
    final teachP = <String, List<String>>{};
    for (final u in _userService.getAllUsers()) {
      teachT[u.id] = ConferimentoData.teachable(theoryGrid, u.id);
      teachP[u.id] = ConferimentoData.teachable(practiceGrid, u.id);
    }
    int nTeach(String uid) =>
        (teachT[uid]?.length ?? 0) + (teachP[uid]?.length ?? 0);
    // Direttori solo se nelle griglie: chi è anche istruttore ha un account dedicato.
    final instructors = _userService
        .getAllUsers()
        .where((u) =>
            u.userRole == UserRole.instructor ||
            (u.userRole == UserRole.courseDirector && nTeach(u.id) > 0))
        .toList()
      ..sort((a, b) {
        final c = a.cognome.toLowerCase().compareTo(b.cognome.toLowerCase());
        return c != 0 ? c : a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
      });

    // Ultimo conferimento registrato, ristretto a ciò che oggi è insegnabile;
    // mai conferito = tutte le materie insegnabili.
    Set<String> initial(String uid, String key, List<String> teach) {
      final prev = (registro[uid] as Map?)?[key] as List?;
      return prev == null
          ? teach.toSet()
          : prev.whereType<String>().where(teach.contains).toSet();
    }

    final assT = {
      for (final u in instructors) u.id: initial(u.id, 'teoria', teachT[u.id]!)
    };
    final assP = {
      for (final u in instructors) u.id: initial(u.id, 'pratica', teachP[u.id]!)
    };

    final searchCtrl = TextEditingController();
    final selected = <String>{};
    var decorrenza = DateTime.now();

    final chosen = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final q = searchCtrl.text.trim().toLowerCase();
          final visible = q.isEmpty
              ? instructors
              : instructors
                  .where((u) =>
                      '${u.cognome} ${u.nome} ${u.grado ?? ''} ${u.mamlNumber ?? ''}'
                          .toLowerCase()
                          .contains(q))
                  .toList();
          final visSel = visible.where((u) => selected.contains(u.id)).length;
          final bool? allState = visible.isEmpty || visSel == 0
              ? false
              : (visSel == visible.length ? true : null);
          final firmeMancanti = firmaTm.isEmpty || firmaAm.isEmpty;

          return AlertDialog(
            title: const Text('Stampa conferimenti'),
            content: SizedBox(
              width: 600,
              height: 540,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Text('Decorrenza',
                        style: TextStyle(color: kTextDim, fontSize: 12)),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.event, size: 16),
                      label: Text(DateFormat('dd/MM/yyyy').format(decorrenza)),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: decorrenza,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2040),
                        );
                        if (d != null) setDlg(() => decorrenza = d);
                      },
                    ),
                    const Spacer(),
                    Tooltip(
                      message: firmeMancanti
                          ? 'Gruppi firma non impostati: il modulo esce con le sole cariche'
                          : 'Propone:\n$firmaTm\n\nConferisce:\n$firmaAm',
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.draw_outlined,
                            size: 16,
                            color: firmeMancanti ? kWarning : null),
                        label: Text('Gruppi firma',
                            style: TextStyle(
                                color: firmeMancanti ? kWarning : null)),
                        onPressed: () async {
                          final r = await _editFirme(firmaTm, firmaAm);
                          if (r == null) return;
                          setDlg(() {
                            firmaTm = r.$1;
                            firmaAm = r.$2;
                          });
                          try {
                            await _saveAmcKey('conferimento_firme',
                                {'tm': firmaTm, 'am': firmaAm});
                          } catch (e) {
                            showAppError('Gruppi firma non salvati: $e');
                          }
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchCtrl,
                    style: const TextStyle(color: kText, fontSize: 13),
                    onChanged: (_) => setDlg(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Cerca istruttore…',
                      prefixIcon:
                          const Icon(Icons.search, size: 18, color: kTextDim),
                      suffixIcon: searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear,
                                  size: 16, color: kTextDim),
                              onPressed: () {
                                searchCtrl.clear();
                                setDlg(() {});
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  CheckboxListTile(
                    tristate: true,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: allState,
                    title: Row(
                      children: [
                        const Flexible(
                          child: Text(
                            'Seleziona tutti',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: kText,
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${selected.length}/${instructors.length}',
                          style: const TextStyle(color: kTextDim, fontSize: 11),
                        ),
                      ],
                    ),
                    onChanged: visible.isEmpty
                        ? null
                        : (_) => setDlg(() {
                              if (allState == true) {
                                for (final u in visible) {
                                  selected.remove(u.id);
                                }
                              } else {
                                for (final u in visible) {
                                  selected.add(u.id);
                                }
                              }
                            }),
                  ),
                  const Divider(height: 1, color: kBorder),
                  Expanded(
                    child: visible.isEmpty
                        ? const Center(
                            child: Text('Nessun istruttore',
                                style: TextStyle(color: kTextDim)),
                          )
                        : ListView.builder(
                            itemCount: visible.length,
                            itemBuilder: (_, i) {
                              final u = visible[i];
                              final grado = (u.grado ?? '').trim();
                              final maml = (u.mamlNumber ?? '').trim();
                              final nAss =
                                  assT[u.id]!.length + assP[u.id]!.length;
                              final who = '${u.cognome} ${u.nome}'.trim();
                              return CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: selected.contains(u.id),
                                secondary: IconButton(
                                  tooltip: 'Materie assegnate',
                                  icon: const Icon(Icons.tune,
                                      size: 18, color: kTextDim),
                                  onPressed: () async {
                                    final r = await _editAssegnate(
                                        who,
                                        teachT[u.id]!,
                                        teachP[u.id]!,
                                        assT[u.id]!,
                                        assP[u.id]!,
                                        subNames);
                                    if (r == null) return;
                                    setDlg(() {
                                      assT[u.id] = r.$1;
                                      assP[u.id] = r.$2;
                                    });
                                  },
                                ),
                                title: Text(
                                  who,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: kText,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                ),
                                subtitle: Text.rich(
                                  TextSpan(
                                    style: const TextStyle(
                                        color: kTextDim, fontSize: 11),
                                    children: [
                                      TextSpan(
                                        text: grado.isNotEmpty
                                            ? grado
                                            : 'grado mancante',
                                        style: grado.isEmpty
                                            ? const TextStyle(color: kWarning)
                                            : null,
                                      ),
                                      const TextSpan(text: ' · '),
                                      TextSpan(
                                        text: maml.isNotEmpty
                                            ? 'MAML $maml'
                                            : 'MAML mancante',
                                        style: maml.isEmpty
                                            ? const TextStyle(color: kWarning)
                                            : null,
                                      ),
                                      const TextSpan(text: ' · '),
                                      TextSpan(
                                        text:
                                            '$nAss/${nTeach(u.id)} sottomoduli assegnati',
                                        style: nAss == 0
                                            ? const TextStyle(color: kWarning)
                                            : null,
                                      ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onChanged: (v) => setDlg(() {
                                  v == true
                                      ? selected.add(u.id)
                                      : selected.remove(u.id);
                                }),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annulla'),
              ),
              ElevatedButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, selected.toList()),
                child: Text('Stampa (${selected.length})'),
              ),
            ],
          );
        },
      ),
    );
    searchCtrl.dispose();
    if (chosen == null || chosen.isEmpty) return;

    List<String> sorted(Set<String> s) =>
        s.toList()..sort(ConferimentoDocxExport.compareCode);
    final chosenSet = chosen.toSet();
    final items = [
      for (final u in instructors)
        if (chosenSet.contains(u.id))
          ConferimentoData.fromUser(u,
              theoryCodes: sorted(assT[u.id]!),
              practiceCodes: sorted(assP[u.id]!)),
    ];
    try {
      await ConferimentoDocxExport.download(items,
          decorrenza: DateFormat('dd/MM/yyyy').format(decorrenza),
          firmaTm: firmaTm,
          firmaAm: firmaAm);
    } catch (e) {
      showAppError('Stampa conferimenti non riuscita: $e');
      return;
    }
    // Registro: ultimo conferimento per istruttore (materie e decorrenza).
    final dec = DateFormat('yyyy-MM-dd').format(decorrenza);
    final reg = Map<String, dynamic>.from(
        _db.amcData['conferimenti'] as Map? ?? const {});
    for (final uid in chosenSet) {
      reg[uid] = {
        'teoria': sorted(assT[uid]!),
        'pratica': sorted(assP[uid]!),
        'decorrenza': dec,
      };
    }
    try {
      await _saveAmcKey('conferimenti', reg);
    } catch (e) {
      showAppError('Conferimenti stampati, registro non aggiornato: $e');
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

  Widget _chip(String name) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: kAccent.withOpacity(0.2),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: kAccent.withOpacity(0.5)),
    ),
    child: Text(name,
        style: const TextStyle(color: kAccent, fontSize: 10,
            fontWeight: FontWeight.bold)),
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
