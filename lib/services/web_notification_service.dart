// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

/// Notifiche di sistema del browser: permesso, sottoscrizione Web Push e
/// visualizzazione. Il service worker dedicato (`web/push/sw.js`, scope `push/`)
/// riceve i push anche ad app chiusa; quello di Flutter non viene toccato.
class WebNotificationService {
  static const String _icon = 'icons/Icon-192.png';

  static bool get supported {
    try {
      return html.Notification.supported;
    } catch (_) {
      return false;
    }
  }

  /// 'granted' | 'denied' | 'default' | 'unsupported'.
  static String get permission =>
      supported ? (html.Notification.permission ?? 'default') : 'unsupported';

  static Future<bool> requestPermission() async {
    if (!supported) return false;
    if (permission == 'granted') return true;
    if (permission == 'denied') return false;
    return await html.Notification.requestPermission() == 'granted';
  }

  /// Registra (una sola volta) il service worker push e attende che sia attivo.
  static Future<html.ServiceWorkerRegistration?> _registration() async {
    final container = html.window.navigator.serviceWorker;
    if (container == null) return null;
    final reg = await container.register('push/sw.js', {'scope': 'push/'});
    // ponytail: polling breve, `ready` risolverebbe il SW di Flutter (scope padre).
    for (var i = 0; i < 50 && reg.active == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return reg.active == null ? null : reg;
  }

  static String _b64u(ByteBuffer? b) => b == null
      ? ''
      : base64Url.encode(Uint8List.view(b)).replaceAll('=', '');

  /// Sottoscrive il browser al push e restituisce `{endpoint, keys:{p256dh,auth}}`
  /// (null se non supportato, permesso negato o errore).
  static Future<Map<String, dynamic>?> subscribe(String vapidPublicKey) async {
    try {
      if (!supported || permission != 'granted') return null;
      final reg = await _registration();
      final pm = reg?.pushManager;
      if (pm == null) return null;
      // subscribe() restituisce la sottoscrizione esistente se c'è già (da spec).
      final sub = await pm.subscribe({
        'userVisibleOnly': true,
        'applicationServerKey': base64Url.decode(base64.normalize(vapidPublicKey)),
      });
      final endpoint = sub.endpoint;
      final p256dh = _b64u(sub.getKey('p256dh'));
      final auth = _b64u(sub.getKey('auth'));
      if (endpoint == null || p256dh.isEmpty || auth.isEmpty) return null;
      return {
        'endpoint': endpoint,
        'keys': {'p256dh': p256dh, 'auth': auth},
      };
    } catch (_) {
      return null;
    }
  }

  /// Mostra una notifica locale (app aperta). Tag uguale = sostituisce la precedente.
  static Future<void> showNotification(String title, String body, {String? tag}) async {
    if (permission != 'granted') return;
    try {
      final reg = await _registration();
      if (reg != null) {
        await reg.showNotification(title, {
          'body': body,
          'icon': _icon,
          if (tag != null) 'tag': tag,
        });
        return;
      }
    } catch (_) {}
    try {
      html.Notification(title, body: body, icon: _icon, tag: tag);
    } catch (_) {}
  }
}
