# Corsi SMAM — Flutter Web App

App: `rdagmr98.github.io/corsi/` | Repo app: `rdagmr98/corsi` | Repo dati: `rdagmr98/corsi-data`

## Release workflow
```
flutter build web --release --base-href "/corsi/"
git add lib/...
git commit -m "..."
git push origin main      ← autorizzato, farlo sempre senza chiedere
```
GitHub Actions (`.github/workflows/deploy.yml`) deploya automaticamente su push a main.

## Architettura
- Flutter web, 4 ruoli: `admin_master` (desktop), `course_director` (desktop), `instructor` (mobile), `attendee` (mobile)
- `GhDbService`: singleton, cache in-memoria, 8 JSON su GitHub API. `reloadAll()` ricarica tutto.
- `ReferenceService`: `getCourseType(id)`, `getEffectiveCourseType(typeId, extensionTypeId)` — mergia moduli base + MIL
- `AttendanceService.computePerModuleStats()`: contatore per modulo di `confirmed`, `absent`, `recovered`, `unrecovered`. Denominatore 10% = `confirmed`.
- PII cifrata AES-CBC: cognome/nome come `ENC:...`

## Struttura tipi corso (reference.json)
- `b1`: M1-M12,M15-M17 + M18, 2044h. Il modulo 11 è stato sdoppiato: number 11 = label "11A" (T114/P30), number 18 = label "11B" (T6/P5). Ordine moduli: 1-10, 11, 18, 12, 15, 16, 17.
- `b2`: M1,2,3,4,5,6,7,8,9,10,13,14, 1755h (M13 practicalHours allineato a 174 = somma sottomoduli; se il programma ufficiale dice 179 va corretto un sottomodulo)
- `b1mil`: **SOLO** M50,M51,M53,M54, 138h (da aggiungere a b1, non sostituisce)
- `b2mil`: **SOLO** M50,M51,M53,M54,M55, 130h (da aggiungere a b2, non sostituisce)
- I moduli possono avere `label` (es. "11A"): nell'app si mostra via `ModuleInfo.displayCode` o `ReferenceService.moduleLabel(int)` — MAI `'M${number}'` direttamente.

## Corsi attivi nel DB
- BTC2 (`d3d468d5`): completato. 1031 assenze + 172 recuperi importati via Python il 2026-06-08.
- BTC3 (`06b19534`): attivo, 8 frequentatori, ~71% completato (M11,13,17 rimanenti). Director: Materni Alessandro (`5f51ae8a`).

## File chiave
| File | Cosa fa |
|------|---------|
| `lib/models/course_models.dart` | Course (con `extensionTypeId`) |
| `lib/models/schedule_models.dart` | ScheduledLesson, AttendanceRecord |
| `lib/models/reference_models.dart` | CourseTypeInfo, ModuleInfo, SubmoduleInfo |
| `lib/services/gh_db_service.dart` | GitHub API, cache, read/write JSON |
| `lib/services/reference_service.dart` | getCourseType, getEffectiveCourseType |
| `lib/services/schedule_service.dart` | generateRemainingSchedule, getLessonsForCourse |
| `lib/services/attendance_service.dart` | computePerModuleStats, saveRecovery |
| `lib/screens/director/schedule_tab.dart` | calendario + _addLesson + genera lezioni |
| `lib/screens/director/attendance_tab.dart` | presenze per corso (director) |
| `lib/screens/master/courses_tab.dart` | lista corsi admin + pulsante +MIL |
| `lib/screens/master/course_detail_screen.dart` | dettaglio corso admin (lezioni/presenze/voti) |
| `lib/screens/attendee/attendee_attendance_screen.dart` | presenze frequentatore + filtri |
| `lib/screens/instructor/my_hours_screen.dart` | valuta GO/NO GO istruttore |

## Recuperi (recovery records)
- ID sintetico: `recovery:{courseId8}:{attendeeId8}:YYYY-MM-DD:m{modulo}`
- `present: true`, `justification: 'recupero'`, `recoveredModule: int`
- Non corrispondono a nessuna lezione reale in schedules.json

---

## STATO SESSIONE — aggiornato 2026-06-12

### Ultime modifiche (2026-06-12)
1. **Split M11 → 11A/11B (b1, corsi-data)**: reference.json — modulo 11 = "11A" Turbine (T114/P30, sottomoduli 11A.*), nuovo modulo 18 = "11B" Piston (T6/P5, sottomoduli 11B.*). 82 lezioni in schedules.json migrate a module_number 18. Campo `label` su ModuleInfo + `displayCode` + `ReferenceService.moduleLabel(int)` (cache statica invalidata in `GhDbService.init()`). Etichette applicate in TUTTI gli schermi (director/instructor/attendee/master) e nel PDF export.
2. **b2 M13**: practicalHours 179→174 (allineato alla somma sottomoduli, il generatore pianifica per sottomodulo). Anomalie note lasciate: 13.19 "Oxygen systems" duplicato T0/P0, 13.17 P19 non multiplo di 5. Verificati tutti e 4 i tipi corso: zero discrepanze modulo/sottomoduli.
3. **Voti rework (grades_tab director)**: inserimento da tastiera (TextField autofocus, virgola o punto, validazione 0-30 live, Enter salva) al posto dello Slider; tap su cella con voti → dialog lista voti con chip Accertamento (kPrimary) / Esame (kWarning), modifica e cancella (con conferma) per il direttore, pulsante "Aggiungi voto". `Grade.copyWith`, `GradeService.updateGrade/deleteGrade`. Dopo scritture basta `setState` (cache ottimistica).
4. **Admin parity (course_detail_screen)**: etichette moduli (displayCode/moduleLabel), cap ore "done/total h" nel riepilogo, tab Voti con celle cliccabili → dialog dettaglio voti in sola lettura (stessi chip del dir), soglie colori corrette a 22.5/30 (prima erano 75/60 su scala 100, sbagliate).
5. **_addLesson fix (schedule_tab)**: lista moduli limitata a quelli con sottomoduli ancora da pianificare, dropdown sottomodulo con ore residue per voce, selSub nullable (niente preselezione sbagliata), dropdown `isExpanded` (niente overflow).
6. **Data nel dialog voti (grades_tab)**: `GradeService.addGrade` accetta `date`, dialog con date picker (default oggi), usata anche in modifica via `copyWith(date:)`.
7. **% completamento corso (admin)**: card "Completamento corso" in cima al riepilogo di course_detail_screen — % ore confermate (cappate) su totale piano, barra + "X / Y ore confermate".
8. **Onboarding qualifiche istruttore (AMC, da ANNESSO MTOE-P-3-1.docx)**:
   - `amcRules` in reference.json (corsi-data commit 86524a6): 28 qualifiche `{id,label,group}` + mappe theory (210 codici) / practice (69 codici) → lista qualifiche ammesse. Estratto dal docx con correzione font-trick: codici resi in Times New Roman col valore "3.2" sono in realtà "3.1" (sostituzione substring 3.2→3.1, vale anche per 13.2x, 53.2); codici Calibri letterali. Griglie amc.json verificate = docx, zero correzioni necessarie.
   - App: `AmcQualification` (reference_models), `AppUser.qualifications` (List<String>?, null = mai compilate), `ReferenceService.amcQualifications()/teachableSubmodules()/amcRuleCodes()`, `GhDbService.saveAmc`, nuovo `AmcService.applyQualifications(userId, quals)` — aggiunge/rimuove l'istruttore SOLO sui codici coperti dalle regole, le aggiunte manuali su altri codici restano intatte.
   - users_tab: se ruolo = Istruttore il dialog mostra "Qualifiche istruttore (AMC)" — chip raggruppati (Laurea, B1.1, B1.2, B1.3, B1.4, B2, Altro) + conteggio live sottomoduli teoria/pratica; al salvataggio aggiorna `qualifications` e applica le griglie. Guard per istruttori storici: se `qualifications == null` e chips non toccati, le griglie NON vengono toccate.
9. **Archiviazione → eliminazione frequentatori (courses_tab)**: dopo l'archiviazione (PDF già scaricato) vengono eliminati gli account dei frequentatori del corso, esclusi quelli iscritti ad altri corsi non archiviati. `UserService.deleteUsers` (bulk, 1 sola PUT). Avviso nel dialog di conferma + snackbar con conteggio.
10. **% completamento dir = admin (overview_tab)**: header e "Ore svolte" del direttore ora usano la stessa formula dell'admin — ore confermate cappate al monte ore di ogni modulo, denominatore = Σ totalHours dei moduli (prima: somma non cappata su totalTheory+totalPractical → % diverse).
11. **_addLesson: cap a livello modulo (schedule_tab)**: i moduli il cui totale ore pianificate (confermate o no) ha raggiunto il monte ore NON compaiono più nel dialog manuale — stesso criterio di skip del generatore (che resta invariato). Prima i sottomoduli 0/0 tenevano il modulo selezionabile all'infinito.
12. **Recupero con suggerimenti (schedule_tab `_addRecovery`)**: il dialog calcola via `computePerModuleStats` le ore di assenza non recuperate per frequentatore/modulo; preseleziona il modulo con più ore da recuperare e i relativi frequentatori, badge "Xh" kWarning nel dropdown moduli, chip frequentatori con "· Xh" e bordo kWarning, ri-suggerisce al cambio modulo. Tutto resta modificabile a mano.
13. **Currency da lezioni confermate (grade_service)**: `getTeachingHoursRollingYear` = `getConfirmedLessonHoursRollingYear` (1h per lezione a calendario con confirmed=true, time_slot>0, ultimi 365gg) + `getManualTeachingHoursRollingYear` (updates.json). Nuovo `getConfirmedLessonHoursByCourse`. Si aggiornano automaticamente: GO/NO GO in currency_tab, badge istruttori in schedule_tab, my_hours_screen. In my_hours_screen: riga dettaglio "Xh da lezioni confermate · Yh da registrazioni manuali" + sezione "Lezioni confermate per corso"; in currency_tab `_teachingByYear` (istogramma per anno) include anche le lezioni confermate.
14. **Chip "Accertamento" senza a-capo**: width 86→92 + FittedBox(scaleDown, maxLines 1) nei dialog voti di grades_tab (director) e course_detail_screen (admin); il chip attendee era già auto-dimensionato.

### Sessione precedente (2026-06-11)
1. **`ScheduleService.normalizeSubCode` (statico)**: normalizzazione unica dei codici sottomodulo — toglie suffisso pratica 'P'/'p' minuscola (bug: schedules.json ha codici tipo '12.2p') e collassa codici a 3 componenti ('12.7.1'→'12.7'). Usato in: generatore, lookup AMC, `_lessonCell`, `my_schedule_screen`, `attendee_attendance_screen` (le vecchie normCode locali gestivano solo 'P' maiuscola → contatori sdoppiati tipo 67/50).
2. **Cap ore al piano ufficiale**: tutti i contatori X/Y (schedule_tab `_lessonCell` con marker "(rec.)", my_schedule_screen, attendee_attendance_screen, overview_tab header % e righe modulo) non superano mai il monte ore del programma — le ore extra sono recuperi.
3. **Performance salvataggi — `GhDbService` write queue**: `saveSchedules/Records/Grades/Updates` ora aggiornano la cache in modo ottimistico e accodano la PUT in background con coalescing per file (N salvataggi rapidi → 1-2 PUT). `pendingSaves`/`saveError` (ValueNotifier statici) + spinner/icona errore accanto al refresh in schedule_tab. `reloadAll()` fa `flushPending()` prima di `init()`. 409 → `_refreshSha` via directory listing (non clobbera la cache ottimistica). users/courses/reference/amc restano sincroni.
4. **Suggerimento istruttori qualificati**: `qualifiedInstructorIds(subCode, type)` su griglie AMC theoryGrid/practiceGrid; dropdown istruttore in `_addLesson` e `_editLessonInstructor` filtrato per materia+tipo, ordinato GO prima (badge verde GO / rosso NO GO, criterio identico a currency_tab: override || (6h ins. + 35h agg. + DAA valida)). Fallback a tutti se griglia vuota.
5. **Validazione del direttore**: pulsante "Valida ora" in `_editLessonInstructor` (conferma la singola ora al posto dell'istruttore, confirmed_by = direttore) + `confirmLessons` bulk in ScheduleService + pulsante "Valida N" nell'intestazione di ogni giorno del calendario (conferma tutte le ore non confermate con istruttore assegnato del giorno).
6. **"Salva e continua"** in `_addLesson`: salva la lezione e riapre il dialog sullo slot libero successivo (`_nextFreeSlot`: salta weekend, festività escluse, slot occupati, ven >3) con stesso modulo/sottomodulo/tipo/istruttore preimpostati.
7. **Percentuali presenze/assenze ovunque**: "Pres. X% · Ass. Y%" (pres = (confirmed−absent)/confirmed, ass = absent/confirmed) in attendance_tab (card frequentatore + righe modulo), course_detail_screen (presenze admin), attendee_attendance_screen (stat "Assenza" nel riepilogo + righe modulo).

### TODO pendenti
*(nessuno al momento)*

### Note importanti
- Se RASPATA o altri sembrano ancora rossi: è cache stale → fare refresh nell'app (pull-to-refresh)
- La cache si aggiorna SOLO con `reloadDb()`. Dati importati via Python non sono visibili finché non si ricarica.
- BTC2 ha tutti i dati corretti nel DB (0 assenze nette per Montini/RASPATA), solo problema di cache.
