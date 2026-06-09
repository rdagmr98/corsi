import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/user_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/course_service.dart';
import '../../services/gh_db_service.dart';
import '../../services/reference_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';

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
  late final TabController _tabs = TabController(length: 2, vsync: this);

  String? _selectedCourseId;
  final _searchCtrl = TextEditingController();
  String _search = '';

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

  Set<String> _courseInstructors() {
    if (_selectedCourseId == null) return {};
    final c = _courseService.getAllCourses()
        .where((c) => c.id == _selectedCourseId)
        .firstOrNull;
    return c?.instructorIds.toSet() ?? {};
  }

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

    return Column(children: [
      // ── Toolbar ──────────────────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        child: Row(children: [
          Text('Tabella AMC', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
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
          const SizedBox(width: 8),
          IconButton(
              icon: const Icon(Icons.refresh, color: kTextDim),
              onPressed: _reload),
        ]),
      ),
      // Legenda
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
        child: Row(children: [
          _dot(kAccent), const SizedBox(width: 4),
          const Text('Nel corso selezionato + abilitato AMC',
              style: TextStyle(color: kTextDim, fontSize: 11)),
          const SizedBox(width: 16),
          _dot(kPrimary), const SizedBox(width: 4),
          const Text('Solo abilitato AMC',
              style: TextStyle(color: kTextDim, fontSize: 11)),
        ]),
      ),
      const SizedBox(height: 8),
      // Search
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
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
      const SizedBox(height: 8),
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
                subNames: subNames, courseUids: courseUids),
            _buildGrid(theory: false, uidToUser: uidToUser,
                subNames: subNames, courseUids: courseUids),
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
        final uids    = grid[code] ?? [];
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                  // Nome sottomodulo
                  SizedBox(
                    width: 260,
                    child: Text(
                      subName.isNotEmpty ? subName : '—',
                      style: TextStyle(
                          color: subName.isNotEmpty ? kTextDim : kBorder,
                          fontSize: 11),
                    ),
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
                  // Totale
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text('${uids.length}',
                        style: const TextStyle(color: kTextDim,
                            fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }

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

  Widget _dot(Color color) => Container(
    width: 10, height: 10,
    decoration: BoxDecoration(
        color: color.withOpacity(0.5),
        shape: BoxShape.circle,
        border: Border.all(color: color)),
  );
}
