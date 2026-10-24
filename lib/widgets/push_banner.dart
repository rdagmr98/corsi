import 'package:flutter/material.dart';
import '../config/gh_config.dart';
import '../services/notification_service.dart';
import '../services/web_notification_service.dart';
import '../theme.dart';

/// Invita ad attivare le notifiche ad app chiusa finché questo browser non è
/// sottoscritto: il permesso va chiesto da un tocco (iPhone e Chrome bloccano
/// la richiesta automatica al login) e può essere già concesso da un'altra app
/// sulla stessa origine `rdagmr98.github.io` senza alcuna sottoscrizione qui.
class PushBanner extends StatefulWidget {
  const PushBanner({super.key, required this.userId});
  final String userId;

  @override
  State<PushBanner> createState() => _PushBannerState();
}

class _PushBannerState extends State<PushBanner> {
  bool _hidden = false;
  bool _busy = false;

  Future<void> _enable() async {
    setState(() => _busy = true);
    await NotificationService().registerPushSubscription(widget.userId);
    if (!mounted) return;
    setState(() => _busy = false);
    final err = WebNotificationService.lastError;
    if (WebNotificationService.pushActive.value || err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err == null
            ? 'Notifiche attivate'
            : 'Notifiche non attivate: $err'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: WebNotificationService.pushActive,
        builder: (context, active, _) => _banner(active),
      );

  Widget _banner(bool active) {
    final permission = WebNotificationService.permission;
    final install = WebNotificationService.needsHomeScreen;
    if (_hidden ||
        active ||
        !GhConfig.pushEnabled ||
        (permission == 'unsupported' && !install)) {
      return const SizedBox.shrink();
    }
    final denied = permission == 'denied';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(
        color: kPrimary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kPrimary.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          Icon(
            denied || install
                ? Icons.notifications_off_outlined
                : Icons.notifications_active_outlined,
            color: kPrimary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              install
                  ? "Per le notifiche su iPhone: Condividi → Aggiungi alla schermata Home, poi apri l'app da lì"
                  : denied
                      ? 'Notifiche bloccate: riattivale dalle impostazioni del sito nel browser'
                      : permission == 'granted'
                          ? 'Notifiche non ancora attive su questo dispositivo'
                          : 'Consenti le notifiche per ricevere lezioni e avvisi anche ad app chiusa',
              style: const TextStyle(color: kText, fontSize: 13),
            ),
          ),
          if (!denied && !install)
            _busy
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : TextButton(
                    onPressed: _enable,
                    child:
                        Text(permission == 'granted' ? 'Attiva' : 'Consenti'),
                  ),
          IconButton(
            tooltip: 'Nascondi',
            icon: const Icon(Icons.close, size: 18, color: kTextDim),
            onPressed: () => setState(() => _hidden = true),
          ),
        ],
      ),
    );
  }
}
