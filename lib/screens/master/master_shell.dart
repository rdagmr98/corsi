import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../theme.dart';
import 'courses_tab.dart';
import 'users_tab.dart';
import 'currency_tab.dart';
import 'amc_tab.dart';

class MasterShell extends ConsumerStatefulWidget {
  const MasterShell({super.key});

  @override
  ConsumerState<MasterShell> createState() => _MasterShellState();
}

class _MasterShellState extends ConsumerState<MasterShell> {
  int _tab = 0;

  static const _tabs = [
    (Icons.school, 'Corsi'),
    (Icons.people, 'Utenti'),
    (Icons.verified_user, 'Idoneità Istruttori'),
    (Icons.table_chart, 'Tabella AMC'),
  ];

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).currentUser;
    return Scaffold(
      backgroundColor: kBg,
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: kSurface,
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            labelType: NavigationRailLabelType.all,
            selectedIconTheme: const IconThemeData(color: kPrimary),
            selectedLabelTextStyle: const TextStyle(color: kPrimary, fontSize: 11),
            unselectedIconTheme: const IconThemeData(color: kTextDim),
            unselectedLabelTextStyle: const TextStyle(color: kTextDim, fontSize: 11),
            leading: Column(
              children: [
                const SizedBox(height: 16),
                const Icon(Icons.school_outlined, color: kPrimary, size: 28),
                const SizedBox(height: 4),
                Text(
                  'Admin',
                  style: const TextStyle(color: kPrimary, fontSize: 10, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  user?.fullName ?? '',
                  style: const TextStyle(color: kTextDim, fontSize: 9),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
              ],
            ),
            trailing: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: IconButton(
                icon: const Icon(Icons.logout, color: kTextDim),
                tooltip: 'Esci',
                onPressed: () async {
                  await ref.read(authProvider).signOut();
                  if (mounted) context.go('/login');
                },
              ),
            ),
            destinations: _tabs
                .map((t) => NavigationRailDestination(
                      icon: Icon(t.$1),
                      label: Text(t.$2),
                    ))
                .toList(),
          ),
          const VerticalDivider(width: 1, color: kBorder),
          Expanded(
            child: switch (_tab) {
              0 => const CoursesTab(),
              1 => const UsersTab(),
              2 => const CurrencyTab(),
              3 => const AmcTab(),
              _ => const SizedBox(),
            },
          ),
        ],
      ),
    );
  }
}
