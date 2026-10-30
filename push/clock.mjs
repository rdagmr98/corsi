// Sveglia dei promemoria: la esegue .github/workflows/promemoria.yml di questo repo (pubblico, minuti gratis anche per job lunghi).
// Il cron di GitHub arriva con ~6 h di ritardo (29-30/10), quindi il job dorme fino all'orario esatto, lancia reminders.yml su corsi-data
// (repository_dispatch, l'unico con i secret VAPID) e a fine finestra rilancia se stesso: la catena non dipende dal cron, che serve solo a riavviarla.
// Uso: node push/clock.mjs   (env TZ=Europe/Rome, GH_TOKEN = PAT del sito con scrittura su corsi-data, GITHUB_TOKEN = rilancio, DA = inizio finestra passato dal run precedente, DRY=true: un lancio subito a vuoto)
import { pathToFileURL } from "node:url";
import { inizi } from "./reminders.mjs";

const API = "https://api.github.com/repos/rdagmr98";
// ponytail: un job dura al massimo 6 h, quindi prende solo gli orari entro 345 min; i successivi li prende il run dopo
const FINESTRA = 345 * 60e3;
const hm = (s) => +s.slice(0, 2) * 60 + +s.slice(3);
const dorme = (ms) => new Promise((ok) => setTimeout(ok, Math.max(0, ms)));

/** Tutti gli orari di oggi: 30 e 10 min prima di ogni inizio slot (lun-ven) e 17:55 (dom-gio) per le lezioni di domani. */
function diOggi(types, now) {
  const d = now.getDay();
  const min = [...(d >= 1 && d <= 5 ? inizi(types, now).flatMap((s) => [hm(s) - 30, hm(s) - 10]) : []), ...(d <= 4 ? [17 * 60 + 55] : [])];
  return [...new Set(min)].sort((a, b) => a - b).map((m) => { const t = new Date(now); t.setHours(0, m, 0, 0); return t; });
}

/** Orari di questo run. da = fine finestra del run precedente: un orario caduto nel passaggio di consegne parte subito, con qualche secondo di ritardo. */
export function orari(types, now, da) {
  return diOggi(types, now).filter((t) => (da ? t >= da : t > now) && t - now < FINESTRA);
}

/** Dom-gio la catena resta viva; il venerdì si ferma dopo l'ultimo orario e la riavvia il cron di domenica. */
export function serveCatena(types, now) {
  const d = now.getDay();
  return d <= 4 || (d === 5 && diOggi(types, now).some((t) => t > now));
}

/** 3 tentativi su errori di rete o 5xx: un errore passeggero non deve spezzare la catena. */
async function gh(path, init, token = process.env.GH_TOKEN) {
  for (let i = 1; ; i++) {
    try {
      const r = await fetch(API + path, { ...init, headers: { Authorization: `Bearer ${token}`, Accept: "application/vnd.github.raw+json" } });
      if (r.status < 500 || i === 3) return r;
    } catch (e) {
      if (i === 3) return { ok: false, status: String(e) };
    }
    await dorme(30e3);
  }
}

async function main() {
  const now = new Date(), dry = process.env.DRY === "true";
  const r = await gh("/corsi-data/contents/db/reference.json");
  if (!r.ok) throw new Error(`reference.json: HTTP ${r.status}`);
  const types = (await r.json()).courseTypes || [];
  const lista = dry ? [now] : orari(types, now, process.env.DA ? new Date(process.env.DA) : undefined);
  console.log(`orari: ${lista.map((t) => t.toTimeString().slice(0, 5)).join(" ") || "nessuno"}`);
  for (const t of lista) {
    await dorme(t - Date.now());
    const d = await gh("/corsi-data/dispatches", { method: "POST", body: JSON.stringify({ event_type: "reminders", client_payload: { dry } }) });
    console.log(`${t.toTimeString().slice(0, 5)} → HTTP ${d.status}`);
    if (!d.ok) process.exitCode = 1;
  }
  if (dry) return;
  if (!serveCatena(types, new Date())) return console.log("catena ferma fino a domenica");
  const fine = new Date(now.getTime() + FINESTRA);
  await dorme(fine - Date.now());
  const c = await gh("/corsi/actions/workflows/promemoria.yml/dispatches", { method: "POST", body: JSON.stringify({ ref: "main", inputs: { dry: "false", da: fine.toISOString() } }) }, process.env.GITHUB_TOKEN);
  console.log(`rilancio → HTTP ${c.status}`);
  if (!c.ok) process.exitCode = 1;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) await main();
