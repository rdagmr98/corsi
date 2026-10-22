// Invio Web Push: lo esegue l'Action .github/workflows/push.yml di corsi-data a ogni commit "nuove notifiche".
// Confronta db/notifications.json prima/dopo il commit e manda le non lette nuove ai dispositivi in db/push_subscriptions.json.
// Uso: node push/notify.mjs <cartella checkout corsi-data>   (env VAPID_PUBLIC, VAPID_PRIVATE)
// Sta qui e non nel repo dati: il PAT pubblico del sito scrive su corsi-data e non deve poter cambiare codice che vede i secret.
import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";

// ponytail: created_at è ora locale senza fuso; finestra larga solo contro notifiche vecchie riscritte da una cache datata
const FRESH_MS = 12 * 3600e3;

/** Map user_id → [messaggi] delle notifiche non lette comparse con il commit. */
export function nuove(before, after, now = Date.now()) {
  const old = new Set(before.map((n) => n.id)), out = new Map();
  for (const n of after) {
    if (old.has(n.id) || n.is_read || !(now - Date.parse(n.created_at) < FRESH_MS)) continue;
    out.set(n.user_id, [...(out.get(n.user_id) || []), n.message]);
  }
  return out;
}

export const payload = (l) => ({ title: "Corsi SMAM", body: l.length === 1 ? l[0] : `Hai ${l.length} nuove notifiche:\n${l.join("\n")}` });

async function main(dir) {
  const show = (rev, f) => { try { return JSON.parse(execFileSync("git", ["-C", dir, "show", `${rev}:${f}`], { maxBuffer: 1 << 28 })); } catch { return []; } };
  // ponytail: HEAD~1 = commit precedente; ogni scrittura del sito (Contents API) è un push con un solo commit
  const out = nuove(show("HEAD~1", "db/notifications.json"), show("HEAD", "db/notifications.json"));
  const subs = show("HEAD", "db/push_subscriptions.json");
  const { default: wp } = await import("web-push");
  wp.setVapidDetails("https://rdagmr98.github.io/corsi/", process.env.VAPID_PUBLIC, process.env.VAPID_PRIVATE);
  const jobs = [...out].flatMap(([id, l]) => subs.filter((s) => s.user_id === id).map((s) =>
    wp.sendNotification({ endpoint: s.endpoint, keys: s.keys }, JSON.stringify(payload(l)), { TTL: 86400, urgency: "high" })));
  const r = await Promise.allSettled(jobs);
  // solo conteggi nel log: niente nomi né endpoint
  console.log(`destinatari ${out.size}, invii ${r.filter((x) => x.status === "fulfilled").length}/${r.length}`);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) await main(process.argv[2] || ".");
