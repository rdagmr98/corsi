// Sveglia dei promemoria: la esegue .github/workflows/promemoria.yml di questo repo (pubblico, minuti gratis anche per job lunghi).
// Il cron di GitHub arriva in ritardo o salta (29/10: nessun run al mattino), quindi il job parte ore prima, dorme fino
// all'orario esatto e lancia reminders.yml su corsi-data (repository_dispatch), l'unico con i secret VAPID.
// Uso: node push/clock.mjs   (env TZ=Europe/Rome, GH_TOKEN = PAT del sito con scrittura su corsi-data, DRY=true: un lancio subito a vuoto)
import { pathToFileURL } from "node:url";
import { inizi } from "./reminders.mjs";

const API = "https://api.github.com/repos/rdagmr98/corsi-data";
// ponytail: un job dura al massimo 6 h, quindi prende solo gli orari entro 345 min; i successivi li prende il run dopo
const FINESTRA = 345 * 60e3;
const hm = (s) => +s.slice(0, 2) * 60 + +s.slice(3);

/** Orari di oggi ancora da lanciare: 30 e 10 min prima di ogni inizio slot (lun-ven) e 17:55 (dom-gio) per le lezioni di domani. */
export function orari(types, now) {
  const d = now.getDay();
  const min = [...(d >= 1 && d <= 5 ? inizi(types, now).flatMap((s) => [hm(s) - 30, hm(s) - 10]) : []), ...(d <= 4 ? [17 * 60 + 55] : [])];
  return [...new Set(min)].sort((a, b) => a - b)
    .map((m) => { const t = new Date(now); t.setHours(0, m, 0, 0); return t; })
    .filter((t) => t > now && t - now < FINESTRA);
}

async function main() {
  const gh = (path, init) => fetch(API + path, { ...init, headers: { Authorization: `Bearer ${process.env.GH_TOKEN}`, Accept: "application/vnd.github.raw+json" } });
  const r = await gh("/contents/db/reference.json");
  if (!r.ok) throw new Error(`reference.json: HTTP ${r.status}`);
  const dry = process.env.DRY === "true";
  const lista = dry ? [new Date()] : orari((await r.json()).courseTypes || [], new Date());
  console.log(`orari: ${lista.map((t) => t.toTimeString().slice(0, 5)).join(" ") || "nessuno"}`);
  for (const t of lista) {
    await new Promise((ok) => setTimeout(ok, Math.max(0, t - Date.now())));
    const d = await gh("/dispatches", { method: "POST", body: JSON.stringify({ event_type: "reminders", client_payload: { dry } }) });
    console.log(`${t.toTimeString().slice(0, 5)} → HTTP ${d.status}`);
    if (!d.ok) process.exitCode = 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) await main();
