import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../theme.dart';
import '../../widgets/change_password_dialog.dart';
import 'attendee_schedule_screen.dart';
import 'attendee_grades_screen.dart';
import 'attendee_attendance_screen.dart';

class AttendeeShell extends ConsumerStatefulWidget {
  const AttendeeShell({super.key});

  @override
  ConsumerState<AttendeeShell> createState() => _AttendeeShellState();
}

class _AttendeeShellState extends ConsumerState<AttendeeShell> {
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
            const Text('Frequentatore', style: TextStyle(color: kWarning, fontSize: 11)),
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
        0 => AttendeeScheduleScreen(userId: userId),
        1 => AttendeeAttendanceScreen(userId: userId),
        2 => AttendeeGradesScreen(userId: userId),
        _ => const SizedBox(),
      },
      bottomNavigationBar: NavigationBar(
        backgroundColor: kSurface,
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        indicatorColor: kWarning.withOpacity(0.15),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_today, color: kTextDim),
            selectedIcon: Icon(Icons.calendar_today, color: kWarning),
            label: 'Calendario',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined, color: kTextDim),
            selectedIcon: Icon(Icons.fact_check_outlined, color: kWarning),
            label: 'Presenze',
          ),
          NavigationDestination(
            icon: Icon(Icons.grade_outlined, color: kTextDim),
            selectedIcon: Icon(Icons.grade_outlined, color: kWarning),
            label: 'Voti',
          ),
        ],
      ),
    );
  }
}
