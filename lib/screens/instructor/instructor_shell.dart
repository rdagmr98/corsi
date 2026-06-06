import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../theme.dart';
import '../../widgets/change_password_dialog.dart';
import 'today_screen.dart';
import 'my_schedule_screen.dart';
import 'my_hours_screen.dart';

class InstructorShell extends ConsumerStatefulWidget {
  const InstructorShell({super.key});

  @override
  ConsumerState<InstructorShell> createState() => _InstructorShellState();
}

class _InstructorShellState extends ConsumerState<InstructorShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).currentUser;
    final userId = user?.id ?? '';

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Istruttore', style: TextStyle(color: kAccent, fontSize: 11)),
            Text(user?.fullName ?? '', style: const TextStyle(color: kText, fontSize: 15)),
          ],
        ),
        actions: [
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
            onPressed: () async {
              await ref.read(authProvider).signOut();
              if (mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: switch (_tab) {
        0 => InstructorTodayScreen(userId: userId),
        1 => InstructorScheduleScreen(userId: userId),
        2 => InstructorHoursScreen(userId: userId),
        _ => const SizedBox(),
      },
      bottomNavigationBar: NavigationBar(
        backgroundColor: kSurface,
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        indicatorColor: kPrimary.withOpacity(0.15),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today, color: kTextDim),
            selectedIcon: Icon(Icons.today, color: kPrimary),
            label: 'Oggi',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month, color: kTextDim),
            selectedIcon: Icon(Icons.calendar_month, color: kPrimary),
            label: 'Calendario',
          ),
          NavigationDestination(
            icon: Icon(Icons.timer_outlined, color: kTextDim),
            selectedIcon: Icon(Icons.timer_outlined, color: kPrimary),
            label: 'Le mie ore',
          ),
        ],
      ),
    );
  }
}
