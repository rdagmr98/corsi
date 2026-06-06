import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../theme.dart';
import '../../widgets/change_password_dialog.dart';
import 'schedule_tab.dart';
import 'grades_tab.dart';
import 'attendance_tab.dart';
import 'overview_tab.dart';

class DirectorShell extends ConsumerStatefulWidget {
  const DirectorShell({super.key});

  @override
  ConsumerState<DirectorShell> createState() => _DirectorShellState();
}

class _DirectorShellState extends ConsumerState<DirectorShell> {
  int _tab = 0;

  static const _tabs = [
    (Icons.dashboard, 'Riepilogo'),
    (Icons.calendar_month, 'Pianificazione'),
    (Icons.people_outline, 'Presenze'),
    (Icons.grade, 'Voti'),
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
                const Icon(Icons.manage_accounts, color: kAccent, size: 28),
                const SizedBox(height: 4),
                Text('Direttore', style: const TextStyle(color: kAccent, fontSize: 10, fontWeight: FontWeight.bold)),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.lock_reset, color: kTextDim),
                    tooltip: 'Cambia password',
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const ChangePasswordDialog(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: kTextDim),
                    tooltip: 'Esci',
                    onPressed: () async {
                      await ref.read(authProvider).signOut();
                      if (mounted) context.go('/login');
                    },
                  ),
                ],
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
              0 => DirectorOverviewTab(userId: user?.id ?? ''),
              1 => DirectorScheduleTab(userId: user?.id ?? ''),
              2 => DirectorAttendanceTab(userId: user?.id ?? ''),
              3 => DirectorGradesTab(userId: user?.id ?? ''),
              _ => const SizedBox(),
            },
          ),
        ],
      ),
    );
  }
}
