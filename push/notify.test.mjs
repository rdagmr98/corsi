// node push/notify.test.mjs — quali notifiche diventano push.
import assert from "node:assert/strict";
import { nuove, payload } from "./notify.mjs";

const now = Date.parse("2026-10-22T10:00:00");
const n = (id, user_id, extra = {}) => ({ id, user_id, type: "X", message: "m" + id, is_read: false, created_at: "2026-10-22T09:59:00.000", ...extra });
const before = [n(1, "a"), n(2, "b")];
const got = (after) => Object.fromEntries(nuove(before, after, now));

// nuove non lette, raggruppate per utente
assert.deepEqual(got([...before, n(3, "a"), n(4, "a"), n(5, "c")]), { a: ["m3", "m4"], c: ["m5"] });
// lettura/cancellazione: nessun push
assert.deepEqual(got([{ ...before[0], is_read: true }]), {});
// già letta o vecchia (cache datata che la riscrive): nessun push
assert.deepEqual(got([...before, n(6, "a", { is_read: true }), n(7, "a", { created_at: "2026-10-20T08:00:00.000" })]), {});
assert.equal(payload(["x"]).body, "x");
assert.equal(payload(["x", "y"]).body, "Hai 2 nuove notifiche:\nx\ny");
console.log("notify ok");
