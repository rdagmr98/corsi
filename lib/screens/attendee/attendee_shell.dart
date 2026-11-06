import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../services/course_service.dart';
import '../../services/questionnaire_service.dart';
import '../../theme.dart';
import '../../widgets/change_password_dialog.dart';
import '../../widgets/notification_panel_widget.dart';
import '../../widgets/push_banner.dart';
import 'attendee_home_screen.dart';

class AttendeeShell extends ConsumerStatefulWidget {
  const AttendeeShell({super.key});

  @override
  ConsumerState<AttendeeShell> createState() => _AttendeeShellState();
}

class _AttendeeShellState extends ConsumerState<AttendeeShell> {
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

  /// Questionari aperti e non compilati: una riga se è uno solo, altrimenti
  /// un unico banner che si apre al tap (con 8 righe la home finiva sotto).
  Widget _questionnaireBanners(String userId) {
    final courses = CourseService().getCoursesForAttendee(userId);
    final pending = QuestionnaireService()
        .pendingFor(userId, courses.map((c) => c.id))
        .toList();
    if (pending.isEmpty) return const SizedBox.shrink();
    final tiles = [
      for (final q in pending)
        ListTile(
          dense: true,
          leading: const Icon(Icons.rate_review_outlined, color: kWarning),
          title: const Text('Questionario di qualità percepita',
              style: TextStyle(color: kText, fontSize: 13)),
          subtitle: Text(
              QuestionnaireService.moduleLabel(
                  courses.firstWhere((c) => c.id == q.courseId), q.module),
              style: const TextStyle(color: kTextDim, fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, color: kTextDim),
          onTap: () => context.go('/attendee/questionario/${Uri.encodeComponent(q.courseId)}/${q.module}'),
        ),
    ];
    return Material(
      color: kWarning.withOpacity(0.12),
      child: tiles.length == 1
          ? tiles.first
          : ExpansionTile(
              dense: true,
              shape: const Border(),
              collapsedShape: const Border(),
              leading: const Icon(Icons.rate_review_outlined, color: kWarning),
              iconColor: kWarning,
              collapsedIconColor: kWarning,
              title: Text('${tiles.length} questionari di qualità percepita da compilare',
                  style: const TextStyle(color: kText, fontSize: 13)),
              children: [
                // Aperto non deve spingere la home fuori schermo.
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
                  child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: tiles),
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ModalRoute.isCurrentOf(context); // al ritorno dal questionario il banner sparisce
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
            const Text('Frequentatore',
                style: TextStyle(color: kWarning, fontSize: 11)),
            Text(user?.fullName ?? '',
                style: const TextStyle(color: kText, fontSize: 15)),
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
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                        color: kError, shape: BoxShape.circle),
                    child: Center(
                        child: Text('$unreadCount',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 9))),
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
      body: Column(
        children: [
          PushBanner(userId: userId),
          _questionnaireBanners(userId),
          Expanded(child: AttendeeHomeScreen(userId: userId)),
        ],
      ),
    );
  }
}
