// Cloudflare Worker — proxy GitHub API per l'app Corsi.
//
// Scopo: tenere il token GitHub LATO SERVER (Worker secret) invece di
// includerlo nel bundle web (dove sarebbe estraibile). Il client chiama
// questo Worker; il Worker aggiunge l'Authorization e inoltra a GitHub.
//
// ──────────────────────────────────────────────────────────────────────────
// DEPLOY (una tantum)
// ──────────────────────────────────────────────────────────────────────────
// 1. Crea un token GitHub fine-grained con accesso SOLO al repo
//    rdagmr98/corsi-data, permessi: Contents = Read and write.
// 2. Installa wrangler:  npm i -g wrangler  &&  wrangler login
// 3. Dalla cartella proxy/:
//      wrangler deploy
//    (il file wrangler.toml accanto a questo definisce name = "corsi-proxy")
// 4. Salva il token come secret del Worker:
//      wrangler secret put GH_TOKEN        → incolla il token
//    (opzionale, consigliato) chiave applicativa anti-abuso:
//      wrangler secret put APP_KEY         → incolla una stringa casuale
// 5. Annota l'URL del Worker, es: https://corsi-proxy.<account>.workers.dev
// 6. Nel workflow di build (.github/workflows/deploy.yml) aggiungi i dart-define:
//      --dart-define=PROXY_URL=https://corsi-proxy.<account>.workers.dev
//      --dart-define=APP_KEY=<stessa stringa del secret APP_KEY>   (se usata)
//    e RIMUOVI il --dart-define=READ_PAT (non serve più al client).
// 7. Revoca il vecchio PAT read-only esposto nel bundle.
//
// ──────────────────────────────────────────────────────────────────────────
// WEB PUSH (notifiche reali sul telefono/PC ad app chiusa) — rotta POST /push/send
// ──────────────────────────────────────────────────────────────────────────
// Indipendente dal proxy GitHub: NON richiede GH_TOKEN e NON richiede PROXY_URL
// (l'app può continuare a parlare con GitHub direttamente e usare questo Worker
// solo per il push, via dart-define PUSH_URL).
// a. Dalla cartella proxy/:   npm install
// b. Genera le chiavi VAPID:  npx web-push generate-vapid-keys
// c. Salva i secret:
//      wrangler secret put VAPID_PUBLIC_KEY    → chiave pubblica
//      wrangler secret put VAPID_PRIVATE_KEY   → chiave privata
//      wrangler secret put VAPID_SUBJECT       → es. mailto:tuamail@esempio.it
//      wrangler secret put APP_KEY             → stringa casuale (obbligatoria per il push)
// d. wrangler deploy
// e. Nel workflow (GitHub → Settings → Secrets → Actions) crea i secret
//    PUSH_URL (URL del Worker), APP_KEY (stessa stringa), VAPID_PUBLIC_KEY:
//    deploy.yml li passa già come --dart-define alla build.
// f. Sul telefono: installa l'app come PWA (iOS 16.4+: Condividi → Aggiungi a
//    Home), apri, accetta le notifiche dal pannello. Su PC: Chrome/Edge devono
//    restare attivi in background per ricevere il push a browser chiuso.
// Corpo richiesta: { subscriptions:[{endpoint,keys:{p256dh,auth}}], payload:{title,body,tag} }
// Risposta: { sent:n, gone:[endpoint scaduti da potare] }
// ──────────────────────────────────────────────────────────────────────────

import { buildPushPayload } from '@block65/webcrypto-web-push';

const GH_API = 'https://api.github.com';

// Tetto di sicurezza per richiesta (un corso ha poche decine di persone).
const MAX_SUBSCRIPTIONS = 200;

// Invia il payload a ogni sottoscrizione; 404/410 = sottoscrizione scaduta.
async function sendPush(env, subscriptions, payload) {
  const vapid = {
    subject: env.VAPID_SUBJECT,
    publicKey: env.VAPID_PUBLIC_KEY,
    privateKey: env.VAPID_PRIVATE_KEY,
  };
  const data = JSON.stringify({
    title: String(payload.title || 'Corsi SMAM').slice(0, 120),
    body: String(payload.body || '').slice(0, 500),
    tag: payload.tag ? String(payload.tag).slice(0, 60) : undefined,
  });
  let sent = 0;
  const gone = [];
  await Promise.all(
    subscriptions.slice(0, MAX_SUBSCRIPTIONS).map(async (sub) => {
      try {
        const req = await buildPushPayload(
          { data, options: { ttl: 86400, urgency: 'high' } },
          sub,
          vapid,
        );
        const res = await fetch(sub.endpoint, req);
        if (res.ok) sent++;
        else if (res.status === 404 || res.status === 410) gone.push(sub.endpoint);
      } catch (_) {
        // sottoscrizione malformata o servizio push irraggiungibile: si ignora
      }
    }),
  );
  return { sent, gone };
}

// Solo questi prefissi di path sono inoltrabili: il repo dati dell'app.
const ALLOWED_PREFIXES = [
  '/repos/rdagmr98/corsi-data/contents/',
  '/repos/rdagmr98/corsi-data/git/',
];

// Origini autorizzate a usare il proxy (CORS).
const ALLOWED_ORIGINS = [
  'https://rdagmr98.github.io',
  'http://localhost:8080', // flutter run -d chrome
  'http://127.0.0.1:8080',
];

function corsHeaders(origin) {
  const allow = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    'Access-Control-Allow-Origin': allow,
    'Access-Control-Allow-Methods': 'GET, PUT, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Accept, X-GitHub-Api-Version, X-App-Key',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin',
  };
}

export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin') || '';
    const cors = corsHeaders(origin);

    // Preflight CORS
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: cors });
    }

    const url = new URL(request.url);
    const path = url.pathname;

    // Web Push: prima dell'allowlist GitHub, non usa GH_TOKEN. APP_KEY obbligatoria.
    if (path === '/push/send') {
      if (request.method !== 'POST') {
        return new Response('Method not allowed', { status: 405, headers: cors });
      }
      if (!env.APP_KEY || request.headers.get('X-App-Key') !== env.APP_KEY) {
        return new Response('Unauthorized', { status: 401, headers: cors });
      }
      if (!env.VAPID_PUBLIC_KEY || !env.VAPID_PRIVATE_KEY || !env.VAPID_SUBJECT) {
        return new Response('Push non configurato (mancano le chiavi VAPID).', {
          status: 500,
          headers: cors,
        });
      }
      let req;
      try {
        req = await request.json();
      } catch (_) {
        return new Response('JSON non valido', { status: 400, headers: cors });
      }
      const subs = Array.isArray(req.subscriptions)
        ? req.subscriptions.filter((s) => s && s.endpoint && s.keys)
        : [];
      if (!subs.length || !req.payload) {
        return new Response(JSON.stringify({ sent: 0, gone: [] }), {
          headers: { ...cors, 'Content-Type': 'application/json' },
        });
      }
      const result = await sendPush(env, subs, req.payload);
      return new Response(JSON.stringify(result), {
        headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    // Allowlist del repo dati
    if (!ALLOWED_PREFIXES.some((p) => path.startsWith(p))) {
      return new Response('Forbidden path', { status: 403, headers: cors });
    }

    // Chiave applicativa opzionale (se impostata come secret APP_KEY)
    if (env.APP_KEY && request.headers.get('X-App-Key') !== env.APP_KEY) {
      return new Response('Unauthorized', { status: 401, headers: cors });
    }

    if (!env.GH_TOKEN) {
      return new Response('Proxy non configurato (manca GH_TOKEN).', {
        status: 500,
        headers: cors,
      });
    }

    // Inoltro a GitHub con il token lato server
    const target = GH_API + path + url.search;
    const fwdHeaders = {
      Authorization: `Bearer ${env.GH_TOKEN}`,
      Accept: request.headers.get('Accept') || 'application/vnd.github+json',
      'X-GitHub-Api-Version':
        request.headers.get('X-GitHub-Api-Version') || '2022-11-28',
      'User-Agent': 'corsi-proxy',
    };
    const method = request.method;
    let body;
    if (method !== 'GET' && method !== 'HEAD') {
      body = await request.text();
      fwdHeaders['Content-Type'] =
        request.headers.get('Content-Type') || 'application/json';
    }

    const ghRes = await fetch(target, { method, headers: fwdHeaders, body });

    // Rinvia la risposta di GitHub aggiungendo gli header CORS
    const outHeaders = new Headers(cors);
    const ct = ghRes.headers.get('Content-Type');
    if (ct) outHeaders.set('Content-Type', ct);
    return new Response(ghRes.body, { status: ghRes.status, headers: outHeaders });
  },
};
