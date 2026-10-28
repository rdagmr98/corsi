// Promemoria lezioni ad app chiusa: lo esegue l'Action .github/workflows/reminders.yml di corsi-data (cron, ora di Roma).
// Dalle 17 in poi: a ogni istruttore le sue lezioni di domani. Prima delle 17: a chi ha una lezione che inizia nello slot più vicino a ora.
// Uso: node push/reminders.mjs <cartella checkout corsi-data>   (env TZ=Europe/Rome, VAPID_PUBLIC, VAPID_PRIVATE, DRY=true per non inviare)
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { invia } from "./notify.mjs";

const ymd = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
const min = (hhmm) => { const [h, m] = hhmm.split(":"); return h * 60 + +m; };

/** Lezioni del giorno raggruppate per istruttore in blocchi continui: Map uid → [{start, end, label, corsi, aule}]. */
export function blocchi(lessons, courses, types, day) {
  const date = ymd(day), per = new Map();
  for (const l of lessons) {
    const c = courses.get(l.course_id);
    if (!c || l.date !== date || l.confirmed || !(l.time_slot > 0)) continue;
    const s = types.find((t) => t.id === c.course_type_id)?.schedule;
    const ts = (day.getDay() === 5 ? s?.friday : s?.mondayThursday)?.find((x) => x.slot === l.time_slot);
    if (!ts) continue;
    const label = [l.submodule_code, l.topic !== l.submodule_code && l.topic].filter(Boolean).join(" ") + (l.type === "pratica" ? " (pratica)" : "");
    for (const uid of new Set([l.instructor_id, l.instructor_id_2].filter(Boolean))) {
      const slots = per.get(uid) || new Map();
      const e = slots.get(ts.start) || { start: ts.start, end: ts.end, labels: new Set(), corsi: new Set(), aule: new Set() };
      e.labels.add(label); e.corsi.add(c.title);
      if (l.aula && l.type !== "pratica") e.aule.add(l.aula);
      slots.set(ts.start, e); per.set(uid, slots);
    }
  }
  const out = new Map();
  for (const [uid, slots] of per) {
    const bl = [];
    for (const e of [...slots.values()].sort((a, b) => min(a.start) - min(b.start))) {
      const label = [...e.labels].join(" + "), last = bl.at(-1);
      // stessa materia nello slot successivo (pausa di 10 min) = stessa lezione; pranzo o ora libera = nuovo inizio
      if (last && last.label === label && min(e.start) - min(last.end) <= 30) {
        last.end = e.end; e.corsi.forEach((x) => last.corsi.add(x)); e.aule.forEach((x) => last.aule.add(x));
      } else bl.push({ start: e.start, end: e.end, label, corsi: e.corsi, aule: e.aule });
    }
    out.set(uid, bl);
  }
  return out;
}

const dettagli = (b) => `${b.label} · ${[...b.corsi].join(", ")}${b.aule.size ? ` · aula ${[...b.aule].join("/")}` : ""}`;

/** Map uid → payload push da mandare adesso. */
export function promemoria(lessons, courses, types, now) {
  const domani = now.getHours() >= 17, day = new Date(now);
  if (domani) day.setDate(day.getDate() + 1);
  const per = blocchi(lessons, courses, types, day), out = new Map();
  if (domani) {
    for (const [uid, bl] of per) out.set(uid, { title: "Lezioni di domani", body: bl.map((b) => `${b.start}-${b.end} ${dettagli(b)}`).join("\n"), tag: `domani-${ymd(day)}` });
    return out;
  }
  // ponytail: slot del giorno più vicino a ora (slot distanti ≥ 70 min), così ogni run copre un solo slot anche col cron in ritardo fino a ~35 min
  const nowMin = now.getHours() * 60 + now.getMinutes();
  const starts = [...new Set(types.flatMap((t) => (day.getDay() === 5 ? t.schedule?.friday : t.schedule?.mondayThursday) || []).map((s) => s.start))];
  const target = starts.sort((a, b) => Math.abs(min(a) - nowMin) - Math.abs(min(b) - nowMin))[0];
  if (!target || Math.abs(min(target) - nowMin) > 35) return out;
  for (const [uid, bl] of per) {
    const b = bl.filter((x) => x.start === target);
    if (b.length) out.set(uid, { title: `Lezione alle ${target}`, body: b.map((x) => `${dettagli(x)} (fino alle ${x.end})`).join("\n"), tag: `lezione-${ymd(day)}-${target}` });
  }
  return out;
}

async function main(dir) {
  const db = (f) => { try { return JSON.parse(readFileSync(join(dir, "db", f), "utf8")); } catch { return []; } };
  const courses = new Map(db("courses.json").filter((c) => c.status !== "archived").map((c) => [c.id, c]));
  const now = new Date();
  const msgs = promemoria(db("schedules.json"), courses, db("reference.json").courseTypes || [], now);
  console.log(`${now.toString()} → ${now.getHours() >= 17 ? "domani" : "inizio lezione"}, istruttori ${msgs.size}`);
  if (process.env.DRY === "true") return;
  // TTL: il promemoria di domani vale fino al mattino, quello di inizio lezione solo per la lezione
  await invia(db("push_subscriptions.json"), msgs, now.getHours() >= 17 ? 14 * 3600 : 3600);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) await main(process.argv[2] || ".");
