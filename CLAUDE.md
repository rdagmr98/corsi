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
- `b1`: M1-M17, 1994h — b1mil NON include b1, sono solo i 4 moduli MIL aggiuntivi
- `b2`: M1,2,3,4,5,6,7,8,9,10,13,14, 1760h
- `b1mil`: **SOLO** M50,M51,M53,M54, 138h (da aggiungere a b1, non sostituisce)
- `b2mil`: **SOLO** M50,M51,M53,M54,M55, 130h (da aggiungere a b2, non sostituisce)

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

## STATO SESSIONE — aggiornato 2026-06-09

### Ultime modifiche (commit 7563af8)
1. **Scheduling constraint**: `_addLesson` e `generateRemainingSchedule` usano tutte le lezioni schedulate (non solo confirmed)
2. **Fix totalHours==0**: skip modulo solo se `m.totalHours > 0`; `moduleCapacity = 9999` se 0
3. **Timeslot label**: `softWrap: false` — non va più a capo
4. **Double submodule**: rimosso `${l.submoduleCode} –` dal topic nelle lezioni admin
5. **Denominatore presenze**: `course_detail_screen` usa `confirmed` (non `total`/planned) per il 10%
6. **GO / NO GO**: `my_hours_screen` mostra "GO"/"NO GO" invece di "IDONEO"/"NON IDONEO"
7. **Estensione B1→MIL**: `Course.extensionTypeId`, `getEffectiveCourseType()`, pulsante `military_tech` nell'admin, badge "+MIL"
8. **Filtri presenze frequentatore**: chip Tutte/Presenze/Assenze/Recuperi + recovery window con lezioni mancanti per modulo

### TODO pendenti
*(nessuno al momento)*

### Note importanti
- Se RASPATA o altri sembrano ancora rossi: è cache stale → fare refresh nell'app (pull-to-refresh)
- La cache si aggiorna SOLO con `reloadDb()`. Dati importati via Python non sono visibili finché non si ricarica.
- BTC2 ha tutti i dati corretti nel DB (0 assenze nette per Montini/RASPATA), solo problema di cache.
