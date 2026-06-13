import json, base64, hashlib, uuid, openpyxl
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding as crypto_padding
from collections import defaultdict

KEY = b'c9f4a12b83e06d5a71b2945bc80f3e1d'
IV = bytes(16)
SALT = 'corsi_salt_2024'

def decrypt_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read().strip()
    if content.startswith('ENC:'):
        ct = base64.b64decode(content[4:])
        cipher = Cipher(algorithms.AES(KEY), modes.CBC(IV))
        dec = cipher.decryptor()
        padded = dec.update(ct) + dec.finalize()
        unpadder = crypto_padding.PKCS7(128).unpadder()
        return (unpadder.update(padded) + unpadder.finalize()).decode('utf-8')
    return content

def encrypt_file(data_str):
    raw = data_str.encode('utf-8')
    padder = crypto_padding.PKCS7(128).padder()
    padded = padder.update(raw) + padder.finalize()
    cipher = Cipher(algorithms.AES(KEY), modes.CBC(IV))
    enc = cipher.encryptor()
    ct = enc.update(padded) + enc.finalize()
    return 'ENC:' + base64.b64encode(ct).decode('ascii')

def enc_field(v):
    if v is None:
        return None
    raw = v.encode('utf-8')
    padder = crypto_padding.PKCS7(128).padder()
    padded = padder.update(raw) + padder.finalize()
    cipher = Cipher(algorithms.AES(KEY), modes.CBC(IV))
    enc = cipher.encryptor()
    ct = enc.update(padded) + enc.finalize()
    return 'ENC:' + base64.b64encode(ct).decode('ascii')

def hash_pw(pw):
    return hashlib.sha256((SALT + pw).encode()).hexdigest()

DB = r'C:/Users/Gianmarco/corsi-data/db'

users = json.loads(decrypt_file(f'{DB}/users.json'))
courses = json.loads(decrypt_file(f'{DB}/courses.json'))
records = json.loads(decrypt_file(f'{DB}/records.json'))
schedules = json.loads(decrypt_file(f'{DB}/schedules.json'))

BTC1_ID = '09089caf-0baa-4c31-a8f6-413aedf4348d'
BTC2_ID = 'd3d468d5-eb15-43af-985f-58dd4b4e02e4'

NOW = '2026-06-08T12:00:00Z'

# 2btc students: (nome, cognome_with_grade, username)
# D’Anna uses U+2019 RIGHT SINGLE QUOTATION MARK as in Excel
btc2_students = [
    ('Christian',             'C.le Magg. Adamo',               'adamo.christian'),
    ('Gabriele',              'C.le Magg. Cocciolo',            'cocciolo.gabriele'),
    ('Edoardo',               'Grd. D’Anna',               'danna.edoardo'),
    ('Giuseppe',              'C.le Magg. Di Guardo',           'diguardo.giuseppe'),
    ('Stefano',               'C.le Magg. Diaferio',            'diaferio.stefano'),
    ('Angelo',                'C.le Magg. Greco',               'greco.angelo'),
    ('Giovanni',              'C.le Magg. Loi',                 'loi.giovanni'),
    ('Marta',                 'C.le Magg. Montini',             'montini.marta'),
    ('Luca',                  'C.le Magg. Peretti',             'peretti.luca'),
    ('Federico',              'C.le Magg. Rannisi',             'rannisi.federico'),
    ('Francesco',             'C.le Magg. Romeo',               'romeo.francesco'),
    ('Riccardo',              'C.le Magg. Ruscitto',            'ruscitto.riccardo'),
    ('Lapo',                  'C.le Caldani',                   'caldani.lapo'),
    ('Luca',                  'C.le Guerrini',                  'guerrini.luca'),
    ('Luca',                  'C.le Lucentini',                 'lucentini.luca'),
    ('Matteo',                'C.le Mecocci',                   'mecocci.matteo'),
    ('Antonio',               'C.le Venneri',                   'venneri.antonio'),
    ('Nicole Maria Vittoria', 'C.le Zucchini Vertuani',         'zucchinivertuani.nicole'),
    ('Pier Paolo',            'Mar. Ord. Catalogna',            'catalogna.pierpaolo'),
    ('Luciano',               'Car. Di Gangi',                  'digangi.luciano'),
]

# Mapping from exact Excel cell value to username
excel_to_uname = {
    'C.le Magg. Adamo Christian':               'adamo.christian',
    'C.le Magg. Cocciolo Gabriele':             'cocciolo.gabriele',
    'Grd. D’Anna Edoardo':                 'danna.edoardo',
    'C.le Magg. Di Guardo Giuseppe':            'diguardo.giuseppe',
    'C.le Magg. Diaferio Stefano':              'diaferio.stefano',
    'C.le Magg. Greco Angelo':                  'greco.angelo',
    'C.le Magg. Loi Giovanni':                  'loi.giovanni',
    'C.le Magg. Montini Marta':                 'montini.marta',
    'C.le Magg. Peretti Luca':                  'peretti.luca',
    'C.le Magg. Rannisi Federico':              'rannisi.federico',
    'C.le Magg. Romeo Francesco':               'romeo.francesco',
    'C.le Magg. Ruscitto Riccardo':             'ruscitto.riccardo',
    'C.le Caldani Lapo':                        'caldani.lapo',
    'C.le Guerrini Luca':                       'guerrini.luca',
    'C.le Lucentini Luca':                      'lucentini.luca',
    'C.le Mecocci Matteo':                      'mecocci.matteo',  # Section 2 spelling
    'C.le Meconi Matteo':                       'mecocci.matteo',  # RECUPERI spelling
    'C.le Venneri Antonio':                     'venneri.antonio',
    'C.le Zucchini Vertuani Nicole Maria Vittoria': 'zucchinivertuani.nicole',
    'Mar. Ord. Catalogna Pier Paolo':           'catalogna.pierpaolo',
    'Car. Di Gangi Luciano':                    'digangi.luciano',
}

new_users = []
uname_to_uid = {}
for nome, cognome_grade, uname in btc2_students:
    uid = str(uuid.uuid4())
    uname_to_uid[uname] = uid
    new_users.append({
        'id': uid,
        'nome': enc_field(nome),
        'cognome': enc_field(cognome_grade),
        'email': None,
        'username': enc_field(uname),
        'password_hash': hash_pw(uname),
        'role': 'attendee',
        'is_active': True,
        'created_at': NOW,
        'updated_at': NOW,
    })

btc1_uid = str(uuid.uuid4())
uname_to_uid['gianmarco'] = btc1_uid
new_users.append({
    'id': btc1_uid,
    'nome': enc_field('Gianmarco'),
    'cognome': enc_field('Gianmarco'),
    'email': None,
    'username': enc_field('gianmarco'),
    'password_hash': hash_pw('gianmarco'),
    'role': 'attendee',
    'is_active': True,
    'created_at': NOW,
    'updated_at': NOW,
})

users.extend(new_users)
print(f'Created {len(new_users)} users ({len(btc2_students)} BTC2 + 1 BTC1)')

# Update courses with attendee_ids
btc2_ids = [uname_to_uid[uname] for _, _, uname in btc2_students]
for c in courses:
    if c['id'] == BTC2_ID:
        c['attendee_ids'] = btc2_ids
    elif c['id'] == BTC1_ID:
        c['attendee_ids'] = [btc1_uid]

# Build lesson lookup by (courseId, moduleNumber) sorted by date+slot
lesson_by_course_mod = defaultdict(list)
for s in schedules:
    if s.get('confirmed') and s.get('time_slot', 0) > 0:
        lesson_by_course_mod[(s['course_id'], s['module_number'])].append(s)

for key in lesson_by_course_mod:
    lesson_by_course_mod[key].sort(key=lambda s: (s['date'], s.get('time_slot', 0)))

new_records = []

# Column index 0..19 → module number mapping
col_to_mod = {0:1,1:2,2:3,3:4,4:5,5:6,6:7,7:8,8:9,9:10,10:11,11:11,12:12,13:15,14:16,15:17,16:50,17:51,18:53,19:54}

wb = openpyxl.load_workbook(r'C:/Users/Gianmarco/Documents/Controlloistruttori.xlsx', data_only=True)
ws2 = wb['assenze 2btc']
rows2 = list(ws2.iter_rows(values_only=True))

# ── 2btc absences: Section 2 only (rows 34-53, "assenze al 3/6/25") ──────────
print('\n--- 2BTC ABSENCES (Section 2 rows 34-53) ---')
for row in rows2[34:54]:
    name = row[0]
    if not name or not str(name).strip():
        continue
    name_str = str(name).strip()
    uname = excel_to_uname.get(name_str)
    if not uname:
        print(f'  SKIP unknown: {name_str!r}')
        continue
    uid = uname_to_uid[uname]
    student_records = 0

    for col_idx in range(20):
        cell_val = row[col_idx + 1]
        if cell_val is None:
            continue
        try:
            val = int(cell_val)
        except (ValueError, TypeError):
            continue
        if val == 0:
            continue
        n_absent = abs(val)
        mod_num = col_to_mod[col_idx]
        lessons = lesson_by_course_mod.get((BTC2_ID, mod_num), [])
        used = lessons[:n_absent]
        if len(used) < n_absent:
            print(f'  WARN: {name_str} M{mod_num}: {n_absent} abs requested, only {len(used)} lessons')
        for l in used:
            new_records.append({
                'id': 'imp_' + uuid.uuid4().hex[:16],
                'schedule_id': l['id'],
                'course_id': BTC2_ID,
                'attendee_id': uid,
                'present': False,
                'justification': None,
                'confirmed_by': 'import',
                'confirmed_at': NOW,
            })
            student_records += 1
    if student_records > 0:
        print(f'  {name_str}: {student_records} absence records')

print(f'2btc absence records total: {len(new_records)}')

# ── 2btc recoveries: RECUPERI section (rows 88-107) ──────────────────────────
print('\n--- 2BTC RECUPERI (rows 88-107) ---')
rec_before = len(new_records)
for row in rows2[88:108]:
    name = row[0]
    if not name or not str(name).strip():
        continue
    name_str = str(name).strip()
    uname = excel_to_uname.get(name_str)
    if not uname:
        print(f'  SKIP unknown: {name_str!r}')
        continue
    uid = uname_to_uid[uname]
    student_recs = 0

    for col_idx in range(20):
        cell_val = row[col_idx + 1]
        if cell_val is None:
            continue
        try:
            val = int(cell_val)
        except (ValueError, TypeError):
            continue
        if val == 0:
            continue
        n_rec = abs(val)
        mod_num = col_to_mod[col_idx]
        for i in range(n_rec):
            new_records.append({
                'id': 'imp_' + uuid.uuid4().hex[:16],
                'schedule_id': f'recovery:{BTC2_ID[:8]}:{uid[:8]}:imp{i:03d}:m{mod_num}',
                'course_id': BTC2_ID,
                'attendee_id': uid,
                'present': True,
                'justification': 'recupero',
                'recovered_module': mod_num,
                'confirmed_by': 'import',
                'confirmed_at': NOW,
            })
            student_recs += 1
    if student_recs > 0:
        print(f'  {name_str}: {student_recs} recovery records')

print(f'2btc recovery records total: {len(new_records) - rec_before}')

# ── 1btc gianmarco absences ───────────────────────────────────────────────────
print('\n--- 1BTC (gianmarco) ---')
ws1 = wb['assenze 1btc']
rows1 = list(ws1.iter_rows(values_only=True))
# Row 4 has gianmarco's data: first name cell, then module values
btc1_uid_ref = uname_to_uid['gianmarco']
rec_before = len(new_records)
for row in rows1[4:]:
    name = row[0]
    if not name:
        continue
    name_str = str(name).strip().lower()
    if 'gianmarco' not in name_str:
        continue
    print(f'  Found row: {repr(row[0])}')
    for col_idx in range(20):
        cell_val = row[col_idx + 1]
        if cell_val is None:
            continue
        try:
            val = int(cell_val)
        except (ValueError, TypeError):
            continue
        if val == 0:
            continue
        n_absent = abs(val)
        mod_num = col_to_mod[col_idx]
        lessons = lesson_by_course_mod.get((BTC1_ID, mod_num), [])
        used = lessons[:n_absent]
        if len(used) < n_absent:
            print(f'    WARN: M{mod_num}: {n_absent} abs, only {len(used)} lessons')
        for l in used:
            new_records.append({
                'id': 'imp_' + uuid.uuid4().hex[:16],
                'schedule_id': l['id'],
                'course_id': BTC1_ID,
                'attendee_id': btc1_uid_ref,
                'present': False,
                'justification': None,
                'confirmed_by': 'import',
                'confirmed_at': NOW,
            })
    print(f'  1btc absence records: {len(new_records) - rec_before}')
    break

print(f'\nTotal new records: {len(new_records)}')
records.extend(new_records)

# Save as plain JSON (the Flutter app reads plain JSON; only user fields are encrypted)
print('\nSaving users.json...')
with open(f'{DB}/users.json', 'w', encoding='utf-8') as f:
    json.dump(users, f, ensure_ascii=False)

print('Saving courses.json...')
with open(f'{DB}/courses.json', 'w', encoding='utf-8') as f:
    json.dump(courses, f, ensure_ascii=False)

print('Saving records.json...')
with open(f'{DB}/records.json', 'w', encoding='utf-8') as f:
    json.dump(records, f, ensure_ascii=False)

print('DONE')
