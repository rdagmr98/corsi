"""
Import BTC3 absences and recoveries from Controlloistruttori.xlsx
Uses the detailed '3btc' sheet (one row per lesson-hour with Assenze/Recuperi columns).
Also adds MORELLI to BTC3 attendee_ids.
"""
import json, base64, uuid, openpyxl, warnings
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding as crypto_padding
from collections import defaultdict

warnings.filterwarnings('ignore')

KEY = b'c9f4a12b83e06d5a71b2945bc80f3e1d'
IV = bytes(16)

DB = r'C:/Users/Gianmarco/corsi-data/db'
BTC3_ID = '06b19534-a649-489d-8c74-32cfeaa3df92'
MORELLI_ID = 'ffa48f21-2842-4d93-b132-2bbe842df749'
NOW = '2026-06-09T12:00:00Z'

with open(f'{DB}/records.json', encoding='utf-8') as f:
    records = json.load(f)
with open(f'{DB}/schedules.json', encoding='utf-8') as f:
    schedules = json.load(f)
with open(f'{DB}/courses.json', encoding='utf-8') as f:
    courses = json.load(f)

# ── Step 1: Add MORELLI to BTC3 attendee_ids ──────────────────────────────────
for c in courses:
    if c['id'] == BTC3_ID:
        if MORELLI_ID not in c['attendee_ids']:
            c['attendee_ids'].append(MORELLI_ID)
            print(f'Added MORELLI ({MORELLI_ID[:8]}) to BTC3 attendee_ids')
        else:
            print('MORELLI already in BTC3 attendee_ids')
        break

# ── Step 2: Delete all existing BTC3 records ─────────────────────────────────
before = len(records)
records = [r for r in records if r.get('course_id') != BTC3_ID]
print(f'Removed {before - len(records)} existing BTC3 records')

# ── Step 3: Build lesson lookup for BTC3 ──────────────────────────────────────
# Key: (date_str, module_number) → list of lessons sorted by time_slot
lesson_by_date_mod = defaultdict(list)
for s in schedules:
    if s.get('course_id') == BTC3_ID and (s.get('time_slot', 0) or 0) > 0:
        date_str = s.get('date', '')[:10]  # YYYY-MM-DD
        lesson_by_date_mod[(date_str, s['module_number'])].append(s)
for key in lesson_by_date_mod:
    lesson_by_date_mod[key].sort(key=lambda s: s.get('time_slot', 0))
print(f'BTC3 lesson slots indexed by (date, module): {len(lesson_by_date_mod)} groups')

# ── Step 4: Name → UID mapping ─────────────────────────────────────────────────
name_to_uid = {
    'CHRISTIAN LARASPATA': '2e99ca9e-0605-4363-8fbd-c7a93216791b',
    'LORENZO CODINA':      '1575d99c-17ab-426d-bf0d-c7f3d54e2a1c',
    'FERDINANDO AVELLO':   'c1f7c5b0-7fb1-46e6-be77-cabf85b56021',
    'GIUSEPPE BERNI':      '62147c07-0172-487d-aabc-c44865dd6dde',
    'OSKAR FONTANA':       'd0b8c2d0-3985-4a82-b1ea-c42c10b80772',
    'LUIGI GRECO':         '13789c2d-7b06-4f07-a70c-702f36425361',
    'ENRICO SERENA':       '7ab0a5e1-0d0f-4c8f-bf62-032657ce3e4a',
    'SIMONE MORELLI':      MORELLI_ID,
}

# ── Step 5: Parse '3btc' sheet ────────────────────────────────────────────────
wb = openpyxl.load_workbook(
    r'C:/Users/Gianmarco/Documents/Controlloistruttori.xlsx', data_only=True)
ws = wb['3btc']

# Group Excel rows by (date, module_number, person) for absences and recoveries
# Then map sequentially to DB lesson slots
absent_groups  = defaultdict(list)  # (date, mod_num, uid) → list of rows (in order)
recovery_groups = defaultdict(list) # (date, mod_num, uid) → list of rows

skipped_names = set()
for row in ws.iter_rows(min_row=2, values_only=True):
    date_cell  = row[0]
    mod_cell   = row[2]
    assente    = row[5]
    recupero   = row[6]
    if not date_cell or not mod_cell:
        continue
    # Parse date
    if hasattr(date_cell, 'strftime'):
        date_str = date_cell.strftime('%Y-%m-%d')
    else:
        date_str = str(date_cell)[:10]
    # Parse module number from submodule code like '6.1', '12.3', '5.14'
    try:
        mod_num = int(str(mod_cell).split('.')[0])
    except (ValueError, TypeError):
        continue

    if assente:
        name = str(assente).strip()
        uid = name_to_uid.get(name)
        if uid:
            absent_groups[(date_str, mod_num, uid)].append(row)
        else:
            skipped_names.add(name)

    if recupero:
        name = str(recupero).strip()
        uid = name_to_uid.get(name)
        if uid:
            recovery_groups[(date_str, mod_num, uid)].append(row)
        else:
            skipped_names.add(name)

if skipped_names:
    print(f'Skipped unknown names: {sorted(skipped_names)}')

# ── Step 6: Create absence records ────────────────────────────────────────────
new_records = []
warn_counts = defaultdict(int)

for (date_str, mod_num, uid), rows in sorted(absent_groups.items()):
    lessons = lesson_by_date_mod.get((date_str, mod_num), [])
    n = len(rows)
    used = lessons[:n]
    if len(used) < n:
        warn_counts[('abs', mod_num)] += n - len(used)
    for lesson in used:
        new_records.append({
            'id': 'imp3_' + uuid.uuid4().hex[:16],
            'schedule_id': lesson['id'],
            'course_id': BTC3_ID,
            'attendee_id': uid,
            'present': False,
            'justification': None,
            'confirmed_by': 'import',
            'confirmed_at': NOW,
        })

print(f'Absence records created: {len(new_records)}')

# ── Step 7: Create recovery records ───────────────────────────────────────────
rec_before = len(new_records)
recovery_counters = defaultdict(int)  # uid → counter per module

for (date_str, mod_num, uid), rows in sorted(recovery_groups.items()):
    n = len(rows)
    for i in range(n):
        idx = recovery_counters[(uid, mod_num)]
        recovery_counters[(uid, mod_num)] += 1
        new_records.append({
            'id': 'imp3_' + uuid.uuid4().hex[:16],
            'schedule_id': f'recovery:{BTC3_ID[:8]}:{uid[:8]}:{date_str}:m{mod_num}i{idx}',
            'course_id': BTC3_ID,
            'attendee_id': uid,
            'present': True,
            'justification': 'recupero',
            'recovered_module': mod_num,
            'confirmed_by': 'import',
            'confirmed_at': NOW,
        })

print(f'Recovery records created: {len(new_records) - rec_before}')

if warn_counts:
    print('WARNINGS (absences where not enough DB lessons):')
    for (kind, mod), cnt in sorted(warn_counts.items()):
        print(f'  M{mod}: {cnt} {kind} records could not be matched')

# ── Print summary by person ───────────────────────────────────────────────────
uid_to_name = {v: k for k, v in name_to_uid.items()}
abs_by_person = defaultdict(int)
rec_by_person = defaultdict(int)
for r in new_records:
    if not r.get('present'):
        abs_by_person[r['attendee_id']] += 1
    else:
        rec_by_person[r['attendee_id']] += 1
print('\nSummary per person:')
for uid in sorted(uid_to_name):
    a = abs_by_person.get(uid, 0)
    r = rec_by_person.get(uid, 0)
    if a or r:
        print(f'  {uid_to_name[uid]}: {a} absences, {r} recoveries')

# ── Step 8: Save ──────────────────────────────────────────────────────────────
records.extend(new_records)
print(f'\nTotal records.json after: {len(records)}')

print('Saving courses.json...')
with open(f'{DB}/courses.json', 'w', encoding='utf-8') as f:
    json.dump(courses, f, ensure_ascii=False)

print('Saving records.json...')
with open(f'{DB}/records.json', 'w', encoding='utf-8') as f:
    json.dump(records, f, ensure_ascii=False)

print('DONE')
