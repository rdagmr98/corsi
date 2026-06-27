import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/notification_models.dart';
import '../providers/auth_provider.dart';
import '../services/notification_service.dart';
import '../theme.dart';

class NotificationPanelWidget extends ConsumerStatefulWidget {
  const NotificationPanelWidget({super.key, required this.userId});
  final String userId;

  @override
  ConsumerState<NotificationPanelWidget> createState() =>
      _NotificationPanelWidgetState();
}

class _NotificationPanelWidgetState
    extends ConsumerState<NotificationPanelWidget> {
  final _service = NotificationService();
  late List<AppNotification> _notifications;

  @override
  void initState() {
    super.initState();
    _notifications = _service.getNotifications(widget.userId);
  }

  Future<void> _markAsRead(int index) async {
    final item = _notifications[index];
    if (item.isRead) return;
    await _service.markAsRead(item.id);
    if (!mounted) return;
    setState(() => _notifications[index] = item.copyWith(isRead: true));
    ref.read(authProvider).decrementUnread();
  }

  Future<void> _markAllAsRead() async {
    final unread = _notifications.where((n) => !n.isRead).length;
    if (unread == 0) return;
    await _service.markAllAsRead(widget.userId);
    if (!mounted) return;
    setState(() {
      _notifications =
          _notifications.map((n) => n.copyWith(isRead: true)).toList();
    });
    final auth = ref.read(authProvider);
    for (var i = 0; i < unread; i++) {
      auth.decrementUnread();
    }
  }

  Future<void> _delete(int index) async {
    final item = _notifications[index];
    await _service.deleteNotification(item.id);
    if (!mounted) return;
    setState(() => _notifications.removeAt(index));
    if (!item.isRead) ref.read(authProvider).decrementUnread();
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Elimina tutte le notifiche',
            style: TextStyle(color: kText)),
        content: const Text('Vuoi eliminare tutte le notifiche?',
            style: TextStyle(color: kTextDim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla', style: TextStyle(color: kTextDim)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kError),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina tutte'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final unread = _notifications.where((n) => !n.isRead).length;
    await _service.deleteAll(widget.userId);
    if (!mounted) return;
    setState(() => _notifications = []);
    final auth = ref.read(authProvider);
    for (var i = 0; i < unread; i++) {
      auth.decrementUnread();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: kTextDim.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
              child: Row(
                children: [
                  const Text('Notifiche',
                      style: TextStyle(
                          color: kText,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(
                    onPressed: _markAllAsRead,
                    child: const Text('Segna lette',
                        style: TextStyle(color: kPrimary)),
                  ),
                  IconButton(
                    onPressed: _notifications.isEmpty ? null : _deleteAll,
                    icon: const Icon(Icons.delete_sweep_outlined, color: kError),
                    tooltip: 'Elimina tutte',
                  ),
                ],
              ),
            ),
            const Divider(color: kBorder, height: 1),
            Expanded(
              child: _notifications.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_none,
                              size: 48, color: kTextDim),
                          SizedBox(height: 12),
                          Text('Nessuna notifica',
                              style: TextStyle(color: kTextDim)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _notifications.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final item = _notifications[i];
                        return Dismissible(
                          key: ValueKey(item.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: kError,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.delete_outline,
                                color: Colors.white),
                          ),
                          onDismissed: (_) => _delete(i),
                          child: Card(
                            color: item.isRead
                                ? kCard
                                : kPrimary.withOpacity(0.18),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            child: ListTile(
                              onTap: () => _markAsRead(i),
                              leading: Icon(
                                item.icon,
                                color: item.isRead ? kTextDim : kPrimary,
                                size: 22,
                              ),
                              title: Text(
                                item.message,
                                style: TextStyle(
                                  color: kText,
                                  fontWeight: item.isRead
                                      ? FontWeight.w400
                                      : FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  DateFormat('dd/MM/yyyy HH:mm')
                                      .format(item.createdAt.toLocal()),
                                  style: const TextStyle(
                                      color: kTextDim, fontSize: 11),
                                ),
                              ),
                              trailing: Icon(
                                item.isRead
                                    ? Icons.done_all
                                    : Icons.fiber_new,
                                size: 16,
                                color: item.isRead ? kTextDim : kPrimary,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
