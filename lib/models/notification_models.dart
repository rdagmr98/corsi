import 'package:flutter/material.dart';

class AppNotification {
  final int id;
  final String userId;
  final String type;
  final String message;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.metadata,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: j['id'] as int,
    userId: j['user_id'] as String,
    type: j['type'] as String,
    message: j['message'] as String,
    isRead: j['is_read'] as bool? ?? false,
    createdAt: DateTime.parse(j['created_at'] as String),
    metadata: (j['metadata'] as Map?)?.cast<String, dynamic>(),
  );

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    userId: userId,
    type: type,
    message: message,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt,
    metadata: metadata,
  );

  IconData get icon {
    if (type.contains('LESSON_SCHEDULED')) return Icons.event_available;
    if (type.contains('LESSON_CHANGED')) return Icons.edit_calendar;
    if (type.contains('LESSON_VALIDATED')) return Icons.task_alt;
    if (type.contains('LESSON_REMINDER')) return Icons.alarm;
    if (type.contains('UPDATE_SUBMITTED')) return Icons.pending_actions;
    if (type.contains('UPDATE_APPROVED')) return Icons.check_circle;
    return Icons.notifications;
  }
}
