class GhConfig {
  static const String owner = 'rdagmr98';
  static const String dataRepo = 'corsi-data';

  /// Token GitHub usato in modalità diretta (senza proxy).
  /// ATTENZIONE: in build web finisce nel bundle JS ed è estraibile.
  /// Per non esporlo, deployare il proxy e impostare PROXY_URL (vedi proxy/worker.js).
  static const String readPat = String.fromEnvironment(
    'READ_PAT',
    defaultValue: 'REPLACE_WITH_READ_ONLY_PAT',
  );

  /// URL del proxy serverless che custodisce il token lato server.
  /// Se valorizzato, le chiamate passano dal proxy e il client NON invia il PAT.
  /// Esempio build: --dart-define=PROXY_URL=https://corsi-proxy.<account>.workers.dev
  static const String proxyUrl = String.fromEnvironment('PROXY_URL', defaultValue: '');

  /// Chiave applicativa opzionale inviata al proxy (header X-App-Key) per
  /// scoraggiare l'uso del proxy da origini non previste. Rotabile lato Worker.
  static const String appKey = String.fromEnvironment('APP_KEY', defaultValue: '');

  /// Endpoint del Worker che firma e inoltra le notifiche push (POST /push/send).
  /// Distinto da PROXY_URL: attivarlo non sposta il traffico GitHub sul proxy.
  /// Esempio build: --dart-define=PUSH_URL=https://corsi-proxy.<account>.workers.dev
  static const String pushUrl = String.fromEnvironment('PUSH_URL', defaultValue: '');

  /// Chiave pubblica VAPID (base64url) usata dal browser per sottoscriversi al push.
  static const String vapidPublicKey = String.fromEnvironment('VAPID_PUBLIC_KEY', defaultValue: '');

  static bool get pushEnabled => pushUrl.isNotEmpty && vapidPublicKey.isNotEmpty;

  static const String passwordSalt = 'corsi_salt_2024';

  static bool get useProxy => proxyUrl.isNotEmpty;

  /// Radice API: il proxy quando configurato, altrimenti GitHub diretto.
  static String get apiRoot => useProxy ? proxyUrl : 'https://api.github.com';

  /// Header di autenticazione: con proxy si manda solo l'eventuale app key
  /// (il token resta lato server); senza proxy si manda il Bearer token.
  static Map<String, String> authHeaders() => useProxy
      ? (appKey.isNotEmpty ? {'X-App-Key': appKey} : const {})
      : {'Authorization': 'Bearer $readPat'};

  static bool get isConfigured => useProxy || readPat != 'REPLACE_WITH_READ_ONLY_PAT';
}
