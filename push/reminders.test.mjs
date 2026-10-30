// node push/reminders.test.mjs — quali promemoria partono e quando.
import assert from "node:assert/strict";
import { promemoria } from "./reminders.mjs";
import { orari } from "./clock.mjs";

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

// giorno prima, 17:55 di mercoledì: ora e orario, blocchi per materia
assert.deepEqual(at(28, 17, 55), {
  a: { title: "Lezioni di domani", tag: "domani-2026-10-29", body: "1ª-4ª ora 09:00-13:30 53.1 Surveillance · 3° BTC, VFI · aula 3\n5ª ora 14:20-15:20 53.1 Surveillance · 3° BTC, VFI · aula 3\n6ª ora 15:30-16:30 7.3 (pratica) · 3° BTC" },
  b: { title: "Lezioni di domani", tag: "domani-2026-10-29", body: "6ª ora 15:30-16:30 7.3 (pratica) · 3° BTC" },
});
// inizio lezione: 30 e 10 min prima (tag distinti), tollerati pochi minuti di ritardo
assert.deepEqual(at(29, 8, 30).a, { title: "1ª-4ª ora alle 09:00", body: "09:00-13:30 53.1 Surveillance · 3° BTC, VFI · aula 3", tag: "lezione-2026-10-29-09:00-30" });
assert.equal(at(29, 8, 50).a.tag, "lezione-2026-10-29-09:00-10");
assert.deepEqual(Object.keys(at(29, 9, 3)), ["a"]);
// ore consecutive: solo la prima, anche se cambia materia
assert.deepEqual(at(29, 10, 0), {});
assert.deepEqual(at(29, 13, 50).a, { title: "5ª-6ª ora alle 14:20", body: "14:20-16:30 53.1 Surveillance / 7.3 (pratica) · 3° BTC, VFI · aula 3", tag: "lezione-2026-10-29-14:20-30" });
assert.deepEqual(Object.keys(at(29, 15, 20)), ["b"]);
// venerdì: orari del venerdì, validate/archiviate escluse
assert.deepEqual(at(30, 8, 10), {});
assert.equal(at(30, 9, 20).a.title, "2ª ora alle 09:30");
assert.deepEqual(at(29, 17, 55).a.body, "2ª ora 09:30-10:30 53.1 Surveillance · 3° BTC · aula 3");
// fuori orario: niente
assert.deepEqual(at(29, 7, 0), {});
// sveglia: 30 e 10 min prima di ogni slot + 17:55, solo orari futuri entro la durata massima del job
const hhmm = (d, h, m) => orari(types, new Date(2026, 9, d, h, m)).map((t) => t.toTimeString().slice(0, 5));
assert.deepEqual(hhmm(29, 6, 7), ["08:30", "08:50", "09:40", "10:00", "10:50", "11:10"]);
assert.deepEqual(hhmm(29, 11, 10), ["12:00", "12:20", "13:50", "14:10", "15:00", "15:20"]);
assert.deepEqual(hhmm(29, 15, 23), ["17:55"]);
assert.deepEqual(hhmm(30, 6, 7), ["07:50", "08:10", "09:00", "09:20", "10:20", "10:40"]);
assert.deepEqual(hhmm(31, 6, 7), []);
assert.deepEqual(hhmm(25, 15, 23), ["17:55"]);
console.log("reminders ok");
