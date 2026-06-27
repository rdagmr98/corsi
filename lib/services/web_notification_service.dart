// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:js_interop';

@JS('avesShowNotification')
external void _jsShowNotification(String title, String body);

class WebNotificationService {
  static Future<bool> requestPermission() async {
    if (!_isSupported()) return false;
    final permission = await html.Notification.requestPermission();
    return permission == 'granted';
  }

  static void showNotification(String title, String body) {
    if (!_isSupported()) return;
    if (html.Notification.permission != 'granted') return;
    try {
      _jsShowNotification(title, body);
    } catch (_) {}
  }

  static bool _isSupported() {
    try {
      return html.Notification.supported;
    } catch (_) {
      return false;
    }
  }
}
