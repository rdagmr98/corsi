// Promemoria lezioni ad app chiusa: lo esegue l'Action .github/workflows/reminders.yml di corsi-data, lanciata all'orario giusto da clock.mjs.
// Dalle 17 in poi: a ogni istruttore le sue lezioni di domani. Prima delle 17: 30 e 10 min prima, a chi inizia un blocco di ore consecutive nel prossimo slot.
// Uso: node push/reminders.mjs <cartella checkout corsi-data>   (env TZ=Europe/Rome, VAPID_PUBLIC, VAPID_PRIVATE, DRY=true per non inviare)
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { invia } from "./notify.mjs";

const ymd = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
const min = (hhmm) => { const [h, m] = hhmm.split(":"); return h * 60 + +m; };

/** Lezioni del giorno raggruppate per istruttore in blocchi continui: Map uid → [{start, end, slot, slotEnd, label, corsi, aule}].
 *  stessaMateria=false unisce anche ore consecutive di materie diverse (il promemoria d'inizio parte solo per la prima ora). */
export function blocchi(lessons, courses, types, day, stessaMateria = true) {
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
      const e = slots.get(ts.start) || { start: ts.start, end: ts.end, slot: ts.slot, labels: new Set(), corsi: new Set(), aule: new Set() };
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
      // slot successivo (pausa di 10 min) = stesso blocco; pranzo o ora libera = nuovo inizio
      if (last && (!stessaMateria || last.ultima === label) && min(e.start) - min(last.end) <= 30) {
        if (last.ultima !== label) last.label += ` / ${label}`;
        last.ultima = label; last.end = e.end; last.slotEnd = e.slot; e.corsi.forEach((x) => last.corsi.add(x)); e.aule.forEach((x) => last.aule.add(x));
      } else bl.push({ start: e.start, end: e.end, slot: e.slot, slotEnd: e.slot, label, ultima: label, corsi: e.corsi, aule: e.aule });
    }
    out.set(uid, bl);
  }
  return out;
}

const ore = (b) => (b.slot === b.slotEnd ? `${b.slot}ª ora` : `${b.slot}ª-${b.slotEnd}ª ora`);
const dettagli = (b) => `${b.label} · ${[...b.corsi].join(", ")}${b.aule.size ? ` · aula ${[...b.aule].join("/")}` : ""}`;

/** Orari "HH:MM" di inizio slot del giorno, unione di tutti i tipi corso (venerdì ha i suoi). Usato anche da clock.mjs. */
export const inizi = (types, day) => [...new Set(types.flatMap((t) => (day.getDay() === 5 ? t.schedule?.friday : t.schedule?.mondayThursday) || []).map((s) => s.start))];

/** Map uid → payload push da mandare adesso. */
export function promemoria(lessons, courses, types, now) {
  const domani = now.getHours() >= 17, day = new Date(now);
  if (domani) day.setDate(day.getDate() + 1);
  const out = new Map();
  if (domani) {
    for (const [uid, bl] of blocchi(lessons, courses, types, day)) out.set(uid, { title: "Lezioni di domani", body: bl.map((b) => `${ore(b)} ${b.start}-${b.end} ${dettagli(b)}`).join("\n"), tag: `domani-${ymd(day)}` });
    return out;
  }
  // ponytail: primo slot non ancora iniziato (tolleranza 5 min) entro 35 min; la sveglia lancia a -30 e a -10, al massimo qualche minuto in ritardo
  const nowMin = now.getHours() * 60 + now.getMinutes();
  const target = inizi(types, day).filter((s) => min(s) - nowMin >= -5).sort((a, b) => min(a) - min(b))[0];
  if (!target || min(target) - nowMin > 35) return out;
  const anticipo = min(target) - nowMin > 20 ? 30 : 10;
  for (const [uid, bl] of blocchi(lessons, courses, types, day, false)) {
    const b = bl.find((x) => x.start === target);
    if (b) out.set(uid, { title: `${ore(b)} alle ${target}`, body: `${b.start}-${b.end} ${dettagli(b)}`, tag: `lezione-${ymd(day)}-${target}-${anticipo}` });
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
