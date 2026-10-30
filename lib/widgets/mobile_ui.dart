import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/course_models.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import 'change_password_dialog.dart';
import 'notification_panel_widget.dart';
import 'push_banner.dart';

// Kit grafico delle viste mobile (istruttore e frequentatore).

const kInstructorAccent = kPrimary;
const kAttendeeAccent = kWarning;

BoxDecoration mobileCard({Color? tint}) => BoxDecoration(
      color: kCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: tint?.withValues(alpha: 0.45) ?? kLine),
    );

class MobileTab {
  const MobileTab(this.icon, this.label, this.builder);
  final IconData icon;
  final String label;
  final Widget Function(String userId) builder;
}

/// Scaffold comune: header con avatar, notifiche, menu account e barra tab.
class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({
    super.key,
    required this.role,
    required this.accent,
    required this.tabs,
    this.banners,
  });
  final String role;
  final Color accent;
  final List<MobileTab> tabs;

  /// Banner extra sotto l'header; `refresh` ricostruisce la shell.
  final List<Widget> Function(
      BuildContext context, String userId, VoidCallback refresh)? banners;

  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell> {
  int _tab = 0;

  void _openNotifications(String userId) {
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

  Future<void> _onMenu(String action) async {
    if (action == 'password') {
      showDialog(context: context, builder: (_) => const ChangePasswordDialog());
      return;
    }
    await ref.read(authProvider).signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.currentUser;
    final userId = user?.id ?? '';
    final unread = auth.unreadCount;
    final accent = widget.accent;
    final initials = [user?.nome ?? '', user?.cognome ?? '']
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => s[0])
        .join()
        .toUpperCase();

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 64,
        titleSpacing: 16,
        shape: const Border(bottom: BorderSide(color: kLine)),
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: accent.withValues(alpha: 0.18),
              child: Text(initials,
                  style: TextStyle(
                      color: accent, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.role.toUpperCase(),
                      style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2)),
                  Text(user?.fullName ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: kText, fontSize: 17, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Notifiche',
            onPressed: () => _openNotifications(userId),
            icon: Badge(
              isLabelVisible: unread > 0,
              backgroundColor: kError,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_outlined, color: kText),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Account',
            icon: const Icon(Icons.more_vert, color: kTextSoft),
            color: kCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: _onMenu,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'password',
                child: Row(children: [
                  Icon(Icons.lock_reset, color: kTextSoft, size: 20),
                  SizedBox(width: 12),
                  Text('Cambia password', style: TextStyle(color: kText)),
                ]),
              ),
              PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout, color: kError, size: 20),
                  SizedBox(width: 12),
                  Text('Esci', style: TextStyle(color: kError)),
                ]),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          PushBanner(userId: userId),
          ...?widget.banners?.call(context, userId, () {
            if (mounted) setState(() {});
          }),
          Expanded(child: widget.tabs[_tab].builder(userId)),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: kLine))),
        child: NavigationBar(
          backgroundColor: kSurface,
          surfaceTintColor: Colors.transparent,
          height: 66,
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          indicatorColor: accent.withValues(alpha: 0.18),
          destinations: [
            for (final t in widget.tabs)
              NavigationDestination(
                icon: Icon(t.icon, color: kTextSoft),
                selectedIcon: Icon(t.icon, color: accent),
                label: t.label,
              ),
          ],
        ),
      ),
    );
  }
}

/// Etichetta compatta colorata. Text.rich (non Row) così si restringe con
/// ellipsis dentro Wrap e non esplode se finisce in una Row non vincolata.
class Pill extends StatelessWidget {
  const Pill(this.text, this.color, {super.key, this.icon, this.filled = false});
  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? kBg : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text.rich(
        TextSpan(children: [
          if (icon != null)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(icon, size: 13, color: fg),
              ),
            ),
          TextSpan(text: text),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 0, 8),
        child: Row(children: [
          Expanded(
            child: Text(text.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: kTextSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Intestazione di giornata nei calendari: giorno, data e chip OGGI.
class DayHeader extends StatelessWidget {
  const DayHeader(this.date, {super.key, required this.accent});
  final DateTime date;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final past = !today && date.isBefore(now);
    final wd = DateFormat('EEEE', 'it').format(date);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Row(children: [
        Text('${wd[0].toUpperCase()}${wd.substring(1)}',
            style: TextStyle(
                color: past ? kTextSoft : kText,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(DateFormat('d MMMM', 'it').format(date),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kTextSoft, fontSize: 13)),
        ),
        if (today) Pill('OGGI', accent, filled: true),
      ]),
    );
  }
}

class NoteBanner extends StatelessWidget {
  const NoteBanner(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kWarning.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kWarning.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.sticky_note_2_outlined, color: kWarning, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: const TextStyle(color: kWarning, fontSize: 13)),
            ),
          ],
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.icon, this.text, {super.key, this.color = kTextSoft});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 36),
              ),
              const SizedBox(height: 14),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kTextSoft, fontSize: 14)),
            ],
          ),
        ),
      );
}

/// Selettore corso a chip scorrevoli (solo se il frequentatore ha più corsi).
class CourseSelector extends StatelessWidget {
  const CourseSelector({
    super.key,
    required this.courses,
    required this.selectedId,
    required this.onSelected,
    this.accent = kAttendeeAccent,
  });
  final List<Course> courses;
  final String? selectedId;
  final ValueChanged<Course> onSelected;
  final Color accent;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: courses.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final c = courses[i];
            final sel = c.id == selectedId;
            return ChoiceChip(
              label: Text(c.title),
              selected: sel,
              showCheckmark: false,
              onSelected: (_) => onSelected(c),
              selectedColor: accent.withValues(alpha: 0.2),
              backgroundColor: kCard,
              shape: const StadiumBorder(),
              side: BorderSide(color: sel ? accent : kLine),
              labelStyle: TextStyle(
                color: sel ? accent : kTextSoft,
                fontSize: 13,
                fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
              ),
            );
          },
        ),
      );
}

/// Card di una lezione: barra colore modulo, colonna orario, argomento e chip.
class LessonCard extends StatelessWidget {
  const LessonCard({
    super.key,
    required this.color,
    required this.slot,
    required this.isTheory,
    required this.module,
    required this.topic,
    this.start,
    this.end,
    this.task,
    this.overline,
    this.overlineColor,
    this.meta,
    this.confirmed = false,
    this.action,
  });
  final Color color;
  final int slot;
  final bool isTheory;
  final String module;
  final String topic;
  final String? start;
  final String? end;
  final String? task;
  final String? overline;
  final Color? overlineColor;
  final String? meta;
  final bool confirmed;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        clipBehavior: Clip.antiAlias,
        decoration: mobileCard(tint: confirmed ? kAccent : null),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: color),
              Container(
                width: 62,
                color: color.withValues(alpha: 0.08),
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (start != null)
                      Text(start!,
                          style: const TextStyle(
                              color: kText, fontSize: 15, fontWeight: FontWeight.w700)),
                    if (end != null)
                      Text(end!, style: const TextStyle(color: kTextSoft, fontSize: 12)),
                    if (start != null) const SizedBox(height: 4),
                    Text('$slotª ora',
                        style: TextStyle(
                            color: color, fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (overline != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(overline!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: overlineColor ?? kTextSoft,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(topic,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: kText,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    height: 1.3)),
                          ),
                          if (confirmed)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(Icons.check_circle, color: kAccent, size: 20),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Pill(isTheory ? 'Teoria' : 'Pratica',
                              isTheory ? kPrimary : kAccent),
                          Pill(module, color),
                          if (task != null) Pill('Task $task', kTextSoft),
                          if (meta != null) Pill(meta!, kTextSoft),
                        ],
                      ),
                      if (action != null) ...[const SizedBox(height: 12), action!],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
