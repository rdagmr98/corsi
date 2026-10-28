// node push/reminders.test.mjs — quali promemoria partono e quando.
import assert from "node:assert/strict";
import { promemoria } from "./reminders.mjs";

const slot = (slot, start, end) => ({ slot, start, end });
const types = [{ id: "b1", schedule: {
  mondayThursday: [slot(1, "09:00", "10:00"), slot(2, "10:10", "11:10"), slot(3, "11:20", "12:20"), slot(4, "12:30", "13:30"), slot(5, "14:20", "15:20"), slot(6, "15:30", "16:30")],
  friday: [slot(1, "08:20", "09:20"), slot(2, "09:30", "10:30"), slot(3, "10:50", "11:50")] } }];
const courses = new Map([["c1", { id: "c1", course_type_id: "b1", title: "3° BTC" }], ["c2", { id: "c2", course_type_id: "b1", title: "VFI" }]]);
const L = (date, time_slot, extra = {}) => ({ course_id: "c1", date, time_slot, submodule_code: "53.1", topic: "Surveillance", type: "teoria", instructor_id: "a", confirmed: false, aula: 3, ...extra });
const lessons = [
  // giovedì 29/10: 53.1 slot 1-4 in due corsi, dopo pranzo ancora 53.1, slot 6 pratica con secondo istruttore
  ...[1, 2, 3, 4, 5].flatMap((s) => [L("2026-10-29", s), L("2026-10-29", s, { course_id: "c2" })]),
  L("2026-10-29", 6, { submodule_code: "7.3", topic: "7.3", type: "pratica", instructor_id_2: "b" }),
  // venerdì 30/10 slot 2; lezione già validata e corso archiviato/assente ignorati
  L("2026-10-30", 2), L("2026-10-30", 3, { confirmed: true }), L("2026-10-30", 1, { course_id: "x" }),
];
const at = (d, h, m) => Object.fromEntries(promemoria(lessons, courses, types, new Date(2026, 9, d, h, m)));

// giorno prima, 17:55 di mercoledì
assert.deepEqual(at(28, 17, 55), {
  a: { title: "Lezioni di domani", tag: "domani-2026-10-29", body: "09:00-13:30 53.1 Surveillance · 3° BTC, VFI · aula 3\n14:20-15:20 53.1 Surveillance · 3° BTC, VFI · aula 3\n15:30-16:30 7.3 (pratica) · 3° BTC" },
  b: { title: "Lezioni di domani", tag: "domani-2026-10-29", body: "15:30-16:30 7.3 (pratica) · 3° BTC" },
});
// inizio lezione: 10 min prima, anche col cron in ritardo
assert.equal(at(29, 8, 50).a.body, "53.1 Surveillance · 3° BTC, VFI · aula 3 (fino alle 13:30)");
assert.deepEqual(Object.keys(at(29, 9, 25)), ["a"]);
// lezione che continua: nessun nuovo push
assert.deepEqual(at(29, 10, 0), {});
// dopo pranzo e cambio materia: nuovo inizio
assert.equal(at(29, 14, 10).a.title, "Lezione alle 14:20");
assert.deepEqual(Object.keys(at(29, 15, 20)).sort(), ["a", "b"]);
// venerdì: orari del venerdì, validate/archiviate escluse
assert.deepEqual(at(30, 8, 10), {});
assert.equal(at(30, 9, 20).a.title, "Lezione alle 09:30");
assert.deepEqual(at(29, 17, 55).a.body, "09:30-10:30 53.1 Surveillance · 3° BTC · aula 3");
// fuori orario: niente
assert.deepEqual(at(29, 7, 0), {});
console.log("reminders ok");
