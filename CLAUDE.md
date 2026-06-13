# Corsi SMAM — Flutter Web App

App: `rdagmr98.github.io/corsi/` | Repo app: `rdagmr98/corsi` | Repo dati: `rdagmr98/corsi-data`

## File di riferimento — CONSULTARE SEMPRE quando si toccano dati/regole

| Situazione | File da aprire |
|------------|----------------|
| Ore T/P di un modulo/sottomodulo sbagliate | `C:\Users\Gianmarco\Documents\programmi\b1.pdf` (o b2/b1mil/b2mil) |
| Assenze, recuperi, situazione frequentatori | `C:\Users\Gianmarco\Documents\Controlloistruttori.xlsx` → foglio `assenze 3btc` (R5-R12 = nette oltre soglia; R41-R48 = raw unrecovered) |
| Chi può insegnare un sottomodulo (AMC) | `C:\Users\Gianmarco\Documents\ANNESSO MTOE-P-3-1.docx` → tabelle T2 (teoria) e T3 (pratica). Font trick: "3.2" in Times New Roman = "3.1" reale |
| Currency istruttori reale | `Controlloistruttori.xlsx` → fogli `istruttori nell'anno`, `currency per modulo`, `currency 2 anni` |
| Pianificazione settimanale vs app | `C:\Users\Gianmarco\Documents\BTC\00_ProgSettimanale_TOTALE_V3.xlsx` |
| Voti graduatoria | `C:\Users\Gianmarco\Documents\voti graduatoria 3btc.xlsx` |
| Normativa presenze/recuperi | `C:\Users\Gianmarco\Documents\corso formatori\Direttiva_Norme_Svolgimento_Corsi_AVES_Ed._2022.pdf` |

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

## STATO SESSIONE — aggiornato 2026-06-13

### Ultime modifiche (2026-06-13) — sessione 5
1. **Fix record recuperi BTC3 (records.json, corsi-data commit 005160e)**: eliminati 63 record sintetici con recovered_module errato (erano in M3/M4 dove nessuno aveva assenze); i 63 record recupero da Excel ora hanno `recovered_module` = module_number della lezione di recupero.
2. **Soglia recuperi globale (attendance_service.dart, commit 0d342f5)**: `attendeesOverRecoveryLimit` ora usa soglia globale — assenze nette totali > 10% ore totali pianificate del corso (come formula Excel "nette oltre soglia"). Prima era per-modulo (molto più restrittivo). Con ~1680h pianificate (b1), soglia = 168h; GRECO max 81h nette = 4.8% → tutti OK.
3. **Task ID pratica (sessione precedente)**: aggiunto `task_id` su `ScheduledLesson`, dropdown task nel dialog _addLesson, badge "T{id}" nel calendario, visibile in tutti i ruoli. Auto-assegnazione nella generazione.

### Ultime modifiche (2026-06-13) — sessione 4
1. **Note slot vuoti (schedule_tab)**: tasto destro/long-press su cella vuota → dialog testo libero per aggiungere nota (es. "Solo 4 ore — visita medica"). Nota visualizzata in giallo con icona sticky_note. Elimina con tasto "Elimina" nel dialog. Dati in `notes.json` (nuovo file corsi-data, caricato da GhDbService). `SlotNote` model, `getNotesForWeek/addNote/deleteNote` in ScheduleService.
2. **Generatore intelligente**: venerdì filtrato a slot 1-3 (bug fix — prima usava tutti e 6 gli slot). Best-effort rotazione blocco stesso sottomodulo al venerdì (lookahead 40). Pratica in blocchi da 4h (era 2-3h). Teoria max 3h.
3. **Commit**: `1be99bb`

### Ultime modifiche (2026-06-13) — sessione 3
1. **Dialog recupero (schedule_tab)**: pratica suggerita per prima. `unrecPByModule`/`unrecPByAttendee` calcolati separatamente. Dropdown moduli: badge rosso "XP" se ci sono ore di pratica da recuperare, giallo "XT" per teoria. Chip frequentatori: badge "P" rosso + ordinati pratica-first per il modulo selezionato. Testo suggerimento aggiornato. Commit: `305d1b3`

### Ultime modifiche (2026-06-13) — sessione 2
1. **Barra bicolore T/P (theme.dart)**: `splitBar(pT, pP, {height})` — teoria kPrimary + pratica kAccent + residuo kSurface. Usata in admin e director.
2. **Admin course_detail_screen**: chip M11A/11B `width:48 softWrap:false overflow:ellipsis`, barra bicolore `splitBar(pT,pP,height:5)`, tap modulo → dialog Totale/Teoria/Pratica ore+%.
3. **Director overview_tab**: barra bicolore modulo, rimossa "h" dal testo durata `done/total`, tap modulo → dialog dettaglio. `rawT`/`rawP` spostate a scope funzione per fix compile error.
4. **BTC3 verifica dati**: tutti i moduli corretti — M6 gap 2h genuino (non ancora insegnato), differenze App/Excel solo su date post-registro (2026-06-08/09) legittime.
5. **Commit**: `0360bf0`

### Ultime modifiche (2026-06-13) — sessione 1
1. **UI overview direttore**: `_statCard` supporta `onTap` + icona info; tap su "Ore svolte" apre dialog con Totale/Teoria/Pratica ore. Barre modulo con testo `XX/XXh` in `SizedBox(w:64)` → larghezza uniforme. Label "M11A"/"M11B" in `SizedBox(w:52, softWrap:false)` → stessa riga.
2. **UI voti frequentatore**: rimossa label SUFFICIENTE/INSUFFICIENTE; posizione graduatoria su riga propria a larghezza piena (non più troncata con "...").
3. **BTC3 dati**: 140 lezioni duplicate rimosse (1523→1371 entro finestra registro), assenze ricreate da Excel con UUID completi. records.json: 1594 record totali.

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
15. **Recuperi: suggeriti solo oltre il 10% (attendance_service + `_addRecovery`)**: nuovo `attendeesOverRecoveryLimit(courseId, attendeeIds, totalHours)` — in lista chi ha (assenze − recuperi) > 10% delle ore confermate del corso; il dialog recupero suggerisce SOLO questi frequentatori. `courseHasAttendeesInRecovery` rifattorizzato su di esso. `saveAttendance` ora preserva la giustificazione se lo stato presente/assente non cambia.
16. **Appello nel dialog di validazione ora (`_editLessonInstructor`)**: FilterChip "Assenti in quest'ora" per frequentatore, prepopolati dai record esistenti; "Valida ora" salva sempre l'appello, "Salva" solo se modificato. Il direttore inserisce le assenze per ogni ora da validare.
17. **Generatore: fix contatori (schedule_service)**: doneT/doneP contano solo le lezioni che sopravvivono alla rigenerazione (confermate + manuali, via `keptIds`) — prima contava anche le auto non confermate che poi cancellava (ore perse silenziosamente). Rimossi clamp di modulo e module-skip: ogni sottomodulo arriva al SUO monte ore T/P → ultima ora sempre X/X (es. 9/9). ID univoci `gen_{runId}_{n}`. Simulazione Python su BTC3: 753h generate, zero sottomoduli sotto piano, +170h nette vs calendario attuale. **Il direttore deve rigenerare il calendario per sanare i contatori.** `_addLesson` allineato allo stesso criterio di chiusura modulo.
18. **Registrazione dal login (login_screen)**: link "Non hai un account? Registrati" → dialog Nome/Cognome/Username/Password + ruolo (Frequentatore/Istruttore), username check case-insensitive, `UserService.createUser`, auto-login dopo la creazione.
19. **Verifica AMC integrale vs annesso (chiusa)**: estrazione completa T2/T3 dal docx con font-trick e diff vs amcRules: teoria 210/210 e pratica 69/69 IDENTICI — zero correzioni a reference.json/amc.json. Ardia/Principe (ing. elettronici) su 11A.5 teoria LEGITTIMI: l'annesso marca Elettronica+B2 su 11A.5. NOTA: i NOMI 11A.* in reference.json sono probabilmente disallineati — il pattern qualifiche dell'annesso segue la numerazione EASA (11A.5 = Instruments/Avionic systems, 11A.11 = Hydraulic power; entrambi i documenti saltano 11A.17), mentre in app 11A.5 = "Hydraulic power". Codici e ore invariati; per riallineare i nomi serve il programma corso ufficiale.

### Sessione precedente (2026-06-11)
1. **`ScheduleService.normalizeSubCode` (statico)**: normalizzazione unica dei codici sottomodulo — toglie suffisso pratica 'P'/'p' minuscola (bug: schedules.json ha codici tipo '12.2p') e collassa codici a 3 componenti ('12.7.1'→'12.7'). Usato in: generatore, lookup AMC, `_lessonCell`, `my_schedule_screen`, `attendee_attendance_screen` (le vecchie normCode locali gestivano solo 'P' maiuscola → contatori sdoppiati tipo 67/50).
2. **Cap ore al piano ufficiale**: tutti i contatori X/Y (schedule_tab `_lessonCell` con marker "(rec.)", my_schedule_screen, attendee_attendance_screen, overview_tab header % e righe modulo) non superano mai il monte ore del programma — le ore extra sono recuperi.
3. **Performance salvataggi — `GhDbService` write queue**: `saveSchedules/Records/Grades/Updates` ora aggiornano la cache in modo ottimistico e accodano la PUT in background con coalescing per file (N salvataggi rapidi → 1-2 PUT). `pendingSaves`/`saveError` (ValueNotifier statici) + spinner/icona errore accanto al refresh in schedule_tab. `reloadAll()` fa `flushPending()` prima di `init()`. 409 → `_refreshSha` via directory listing (non clobbera la cache ottimistica). users/courses/reference/amc restano sincroni.
4. **Suggerimento istruttori qualificati**: `qualifiedInstructorIds(subCode, type)` su griglie AMC theoryGrid/practiceGrid; dropdown istruttore in `_addLesson` e `_editLessonInstructor` filtrato per materia+tipo, ordinato GO prima (badge verde GO / rosso NO GO, criterio identico a currency_tab: override || (6h ins. + 35h agg. + DAA valida)). Fallback a tutti se griglia vuota.
5. **Validazione del direttore**: pulsante "Valida ora" in `_editLessonInstructor` (conferma la singola ora al posto dell'istruttore, confirmed_by = direttore) + `confirmLessons` bulk in ScheduleService + pulsante "Valida N" nell'intestazione di ogni giorno del calendario (conferma tutte le ore non confermate con istruttore assegnato del giorno).
6. **"Salva e continua"** in `_addLesson`: salva la lezione e riapre il dialog sullo slot libero successivo (`_nextFreeSlot`: salta weekend, festività escluse, slot occupati, ven >3) con stesso modulo/sottomodulo/tipo/istruttore preimpostati.
7. **Percentuali presenze/assenze ovunque**: "Pres. X% · Ass. Y%" (pres = (confirmed−absent)/confirmed, ass = absent/confirmed) in attendance_tab (card frequentatore + righe modulo), course_detail_screen (presenze admin), attendee_attendance_screen (stat "Assenza" nel riepilogo + righe modulo).

### TODO pendenti
- Il direttore BTC3 deve rigenerare il calendario (pulsante genera) per sanare i contatori: ultima ora X/X, ~170h nette mancanti ri-pianificate.
- Nomi sottomoduli 11A in reference.json da verificare col programma corso ufficiale (probabile shift: numerazione EASA vs nomi attuali, vedi punto 19).

### Note importanti
- Se RASPATA o altri sembrano ancora rossi: è cache stale → fare refresh nell'app (pull-to-refresh)
- La cache si aggiorna SOLO con `reloadDb()`. Dati importati via Python non sono visibili finché non si ricarica.
- BTC2 ha tutti i dati corretti nel DB (0 assenze nette per Montini/RASPATA), solo problema di cache.
