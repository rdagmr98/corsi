import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../theme.dart';
import '../../widgets/change_password_dialog.dart';
import '../../widgets/notification_panel_widget.dart';
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

  void _openNotifications(BuildContext context, String userId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, __) => NotificationPanelWidget(userId: userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.currentUser;
    final userId = user?.id ?? '';
    final unreadCount = auth.unreadCount;

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
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: kTextDim),
                tooltip: 'Notifiche',
                onPressed: () => _openNotifications(context, userId),
              ),
              if (unreadCount > 0)
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    width: 16, height: 16,
                    decoration: const BoxDecoration(color: kError, shape: BoxShape.circle),
                    child: Center(child: Text('$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 9))),
                  ),
                ),
            ],
          ),
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
