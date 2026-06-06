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
  final _refService    = ReferenceService();
  final _userService   = UserService();
  final _courseService = CourseService();
  final _db            = GhDbService();
  late final TabController _tabs = TabController(length: 2, vsync: this);

  String? _selectedCourseId;
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text.trim().toLowerCase()));
    // seleziona il primo corso attivo
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

  // ── Dati da amc.json ───────────────────────────────────────────────────────
  Map<String, List<String>> _grid(bool theory) {
    final key = theory ? 'theoryGrid' : 'practiceGrid';
    final raw = _db.amcData[key] as Map<String, dynamic>? ?? {};
    return raw.map((k, v) => MapEntry(k, List<String>.from(v as List)));
  }

  Map<String, AppUser> _uidToUser() {
    return {for (final u in _userService.getInstructors()) u.id: u};
  }

  // ── Mappa codice sottomodulo → nome da reference.json ─────────────────────
  Map<String, String> _submoduleNames() {
    final map = <String, String>{};
    for (final ct in _refService.getCourseTypes()) {
      for (final m in ct.modules) {
        for (final s in m.submodules) {
          map[s.code] = s.name;
        }
      }
    }
    return map;
  }

  // ── Set di UID istruttori nel corso selezionato ───────────────────────────
  Set<String> _courseInstructors() {
    if (_selectedCourseId == null) return {};
    final c = _courseService.getAllCourses()
        .where((c) => c.id == _selectedCourseId)
        .firstOrNull;
    return c?.instructorIds.toSet() ?? {};
  }

  // ── Ordina codici sottomodulo numericamente ────────────────────────────────
  List<String> _sortedCodes(Map<String, List<String>> grid) {
    final keys = grid.keys.toList();
    keys.sort((a, b) {
      final pa = a.split('.').map(int.tryParse).toList();
      final pb = b.split('.').map(int.tryParse).toList();
      for (var i = 0; i < pa.length && i < pb.length; i++) {
        final ca = pa[i] ?? 0, cb = pb[i] ?? 0;
        if (ca != cb) return ca.compareTo(cb);
      }
      return pa.length.compareTo(pb.length);
    });
    return keys;
  }

  @override
  Widget build(BuildContext context) {
    final allCourses  = _courseService.getAllCourses();
    final uidToUser   = _uidToUser();
    final subNames    = _submoduleNames();
    final courseUids  = _courseInstructors();

    return Column(children: [
      // ── Toolbar ─────────────────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        child: Row(children: [
          Text('Tabella AMC', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          // Filtro corso
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
          _legendDot(kPrimary), const SizedBox(width: 4),
          const Text('Abilitato AMC', style: TextStyle(color: kTextDim, fontSize: 11)),
          const SizedBox(width: 16),
          _legendDot(kAccent), const SizedBox(width: 4),
          const Text('Abilitato AMC + nel corso selezionato',
              style: TextStyle(color: kTextDim, fontSize: 11)),
          const SizedBox(width: 16),
          _legendDot(kBorder), const SizedBox(width: 4),
          const Text('Nel corso ma non abilitato AMC (da verificare)',
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
                    onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); },
                  )
                : null,
          ),
        ),
      ),
      const SizedBox(height: 8),
      // Tabs
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
    final grid   = _grid(theory);
    var   codes  = _sortedCodes(grid);

    // Applica filtro ricerca
    if (_search.isNotEmpty) {
      codes = codes.where((c) {
        final name = subNames[c]?.toLowerCase() ?? '';
        return c.toLowerCase().contains(_search) || name.contains(_search);
      }).toList();
    }

    // Se è selezionato un corso, filtra solo i sottomoduli dove almeno un
    // istruttore del corso è abilitato (o tutti se nessun corso selezionato)
    final filteredCodes = _selectedCourseId != null
        ? codes.where((c) =>
            grid[c]!.any((uid) => courseUids.contains(uid))).toList()
        : codes;

    if (filteredCodes.isEmpty) {
      return Center(
        child: Text(
          _search.isNotEmpty
              ? 'Nessun sottomodulo trovato per "$_search"'
              : 'Nessun dato AMC',
          style: const TextStyle(color: kTextDim),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      itemCount: filteredCodes.length,
      itemBuilder: (_, i) {
        final code    = filteredCodes[i];
        final uids    = grid[code] ?? [];
        final subName = subNames[code] ?? '';

        // Istruttori abilitati AMC nel corso selezionato
        final inCourse = uids.where((uid) => courseUids.contains(uid)).toList();
        // Istruttori abilitati AMC ma non nel corso
        final notInCourse = _selectedCourseId != null
            ? uids.where((uid) => !courseUids.contains(uid)).toList()
            : uids;

        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: kBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Codice
              SizedBox(
                width: 52,
                child: Text(code,
                    style: const TextStyle(
                        color: kText,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
              // Nome sottomodulo
              SizedBox(
                width: 280,
                child: Text(subName,
                    style: const TextStyle(color: kTextDim, fontSize: 11)),
              ),
              const SizedBox(width: 8),
              // Istruttori
              Expanded(
                child: Wrap(
                  spacing: 4, runSpacing: 4,
                  children: [
                    // Nel corso + abilitati AMC → verde
                    ...inCourse.map((uid) {
                      final u = uidToUser[uid];
                      return _instrChip(
                          u?.cognome ?? uid, kAccent, filled: true);
                    }),
                    // Solo abilitati AMC → blu
                    ...notInCourse.map((uid) {
                      final u = uidToUser[uid];
                      return _instrChip(u?.cognome ?? uid, kPrimary);
                    }),
                  ],
                ),
              ),
              // Totale abilitati
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('${uids.length}',
                    style: const TextStyle(
                        color: kTextDim,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _instrChip(String name, Color color, {bool filled = false}) => Container(
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

  Widget _legendDot(Color color) => Container(
    width: 10, height: 10,
    decoration: BoxDecoration(color: color.withOpacity(0.5),
        shape: BoxShape.circle,
        border: Border.all(color: color)),
  );
}
