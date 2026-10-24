// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Notifiche di sistema del browser: permesso, sottoscrizione Web Push e
/// visualizzazione. Il service worker dedicato (`web/push/sw.js`, scope `push/`)
/// riceve i push anche ad app chiusa; quello di Flutter non viene toccato.
class WebNotificationService {
  static const String _icon = 'icons/Icon-192.png';

  /// Questo browser è sottoscritto al push; null finché il controllo
  /// all'avvio non è finito (l'invito ad attivarlo resta nascosto, niente lampeggio).
  static final pushActive = ValueNotifier<bool?>(null);

  /// Motivo dell'ultima sottoscrizione fallita, da mostrare all'utente.
  static String? lastError;

  /// iPhone/iPad da Safari: il push esiste solo con l'app nella schermata Home.
  static bool get needsHomeScreen =>
      permission == 'unsupported' &&
      RegExp('iPhone|iPad').hasMatch(html.window.navigator.userAgent);

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
    try {
      return await html.Notification.requestPermission() == 'granted';
    } catch (_) {
      return false; // Safari rifiuta la richiesta fuori da un tocco
    }
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

  static String _b64u(ByteBuffer? b) =>
      b == null ? '' : base64Url.encode(Uint8List.view(b)).replaceAll('=', '');

  /// Sottoscrive il browser al push e restituisce `{endpoint, keys:{p256dh,auth}}`
  /// (null se non supportato, permesso negato o errore).
  static Future<Map<String, dynamic>?> subscribe(String vapidPublicKey) async {
    try {
      lastError = null;
      if (!supported || permission != 'granted') return null;
      final pm = (await _registration())?.pushManager;
      if (pm == null) {
        lastError = 'service worker push non attivo';
        return null;
      }
      // subscribe() restituisce la sottoscrizione esistente se c'è già (da spec).
      final sub = await pm.subscribe({
        'userVisibleOnly': true,
        // stringa base64url (ammessa dalla spec): un Uint8List nella mappa di
        // dart:html arriva al browser come array di numeri -> InvalidCharacterError
        'applicationServerKey': vapidPublicKey,
      });
      final endpoint = sub.endpoint;
      final p256dh = _b64u(sub.getKey('p256dh'));
      final auth = _b64u(sub.getKey('auth'));
      if (endpoint == null || p256dh.isEmpty || auth.isEmpty) {
        lastError = 'sottoscrizione incompleta';
        return null;
      }
      return {
        'endpoint': endpoint,
        'keys': {'p256dh': p256dh, 'auth': auth},
      };
    } catch (e) {
      lastError = '$e';
      return null;
    }
  }

  /// Mostra una notifica locale (app aperta). Tag uguale = sostituisce la precedente.
  static Future<void> showNotification(String title, String body,
      {String? tag}) async {
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
