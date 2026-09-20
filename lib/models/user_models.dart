enum UserRole { adminMaster, courseDirector, instructor, attendee }

extension UserRoleExt on UserRole {
  String get value => switch (this) {
    UserRole.adminMaster => 'admin_master',
    UserRole.courseDirector => 'course_director',
    UserRole.instructor => 'instructor',
    UserRole.attendee => 'attendee',
  };

  String get label => switch (this) {
    UserRole.adminMaster => 'Admin Master',
    UserRole.courseDirector => 'Direttore Corso',
    UserRole.instructor => 'Istruttore',
    UserRole.attendee => 'Frequentatore',
  };

  bool get isDesktop =>
      this == UserRole.adminMaster || this == UserRole.courseDirector;

  static UserRole fromString(String s) => switch (s) {
    'admin_master' => UserRole.adminMaster,
    'course_director' => UserRole.courseDirector,
    'instructor' => UserRole.instructor,
    _ => UserRole.attendee,
  };
}

class AppUser {
  final String id;
  final String nome;
  final String cognome;
  final String? email;
  final String? username;
  final String role;
  final bool isActive;
  final bool goOverride;
  final DateTime? daaExpiry;
  // Data perdita currency (null = nessuna registrata / ripristinata senza storico locale).
  final DateTime? currencyLostAt;
  // OJT capacità didattiche: 'iniziale' | 'ripristino' (+ data).
  final String? ojtKind;
  final DateTime? ojtAt;
  // Qualifiche AMC (id da reference.amcRules.qualifications); null = mai compilate.
  final List<String>? qualifications;
  // Grado / titolo (frequentatori: es. GRD, CAR. SC; istruttori: abilitazione).
  final String? titolo;
  final String? licenza;
  /// Forza armata per PS PERSONALE: `EI` (sinistra) o `CC` (destra). Null = EI.
  final String? forza;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AppUser({
    required this.id,
    required this.nome,
    required this.cognome,
    this.email,
    this.username,
    required this.role,
    this.isActive = true,
    this.goOverride = false,
    this.daaExpiry,
    this.currencyLostAt,
    this.ojtKind,
    this.ojtAt,
    this.qualifications,
    this.titolo,
    this.licenza,
    this.forza,
    required this.createdAt,
    required this.updatedAt,
  });

  static String? ojtKindLabel(String? kind) => switch (kind) {
    'iniziale' => 'OJT iniziali',
    'ripristino' => 'OJT di ripristino',
    _ => null,
  };

  UserRole get userRole => UserRoleExt.fromString(role);
  String get fullName => '$cognome $nome'.trim();
  String get displayName => fullName;
  bool get isAdminMaster => role == 'admin_master';

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
    id: j['id'] as String,
    nome: j['nome'] as String? ?? '',
    cognome: j['cognome'] as String? ?? '',
    email: j['email'] as String?,
    username: j['username'] as String?,
    role: j['role'] as String? ?? 'attendee',
    isActive: j['is_active'] as bool? ?? true,
    goOverride: j['go_override'] as bool? ?? false,
    daaExpiry: j['daaa_expiry'] != null
        ? DateTime.tryParse(j['daaa_expiry'] as String)
        : null,
    currencyLostAt: j['currency_lost_at'] != null
        ? DateTime.tryParse(j['currency_lost_at'] as String)
        : null,
    ojtKind: j['ojt_kind'] as String?,
    ojtAt: j['ojt_at'] != null
        ? DateTime.tryParse(j['ojt_at'] as String)
        : null,
    qualifications: j['qualifications'] != null
        ? List<String>.from(j['qualifications'] as List)
        : null,
    titolo: j['titolo'] as String?,
    licenza: j['licenza'] as String?,
    forza: j['forza'] as String?,
    createdAt: DateTime.parse(
      j['created_at'] as String? ?? DateTime.now().toIso8601String(),
    ),
    updatedAt: DateTime.parse(
      j['updated_at'] as String? ?? DateTime.now().toIso8601String(),
    ),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nome': nome,
    'cognome': cognome,
    'email': email,
    'username': username,
    'role': role,
    'is_active': isActive,
    'go_override': goOverride,
    if (daaExpiry != null) 'daaa_expiry': daaExpiry!.toIso8601String().substring(0, 10),
    if (currencyLostAt != null)
      'currency_lost_at': currencyLostAt!.toIso8601String().substring(0, 10),
    if (ojtKind != null) 'ojt_kind': ojtKind,
    if (ojtAt != null) 'ojt_at': ojtAt!.toIso8601String().substring(0, 10),
    if (qualifications != null) 'qualifications': qualifications,
    if (titolo != null) 'titolo': titolo,
    if (licenza != null) 'licenza': licenza,
    if (forza != null) 'forza': forza,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  static const Object _s = Object();

  AppUser copyWith({
    String? nome,
    String? cognome,
    Object? email = _s,
    Object? username = _s,
    String? role,
    bool? isActive,
    bool? goOverride,
    Object? daaExpiry = _s,
    Object? currencyLostAt = _s,
    Object? ojtKind = _s,
    Object? ojtAt = _s,
    Object? qualifications = _s,
    Object? titolo = _s,
    Object? licenza = _s,
    Object? forza = _s,
  }) => AppUser(
    id: id,
    nome: nome ?? this.nome,
    cognome: cognome ?? this.cognome,
    email: identical(email, _s) ? this.email : email as String?,
    username: identical(username, _s) ? this.username : username as String?,
    role: role ?? this.role,
    isActive: isActive ?? this.isActive,
    goOverride: goOverride ?? this.goOverride,
    daaExpiry: identical(daaExpiry, _s) ? this.daaExpiry : daaExpiry as DateTime?,
    currencyLostAt: identical(currencyLostAt, _s)
        ? this.currencyLostAt
        : currencyLostAt as DateTime?,
    ojtKind: identical(ojtKind, _s) ? this.ojtKind : ojtKind as String?,
    ojtAt: identical(ojtAt, _s) ? this.ojtAt : ojtAt as DateTime?,
    qualifications: identical(qualifications, _s)
        ? this.qualifications
        : qualifications as List<String>?,
    titolo: identical(titolo, _s) ? this.titolo : titolo as String?,
    licenza: identical(licenza, _s) ? this.licenza : licenza as String?,
    forza: identical(forza, _s) ? this.forza : forza as String?,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  bool get isCarabinieri =>
      (forza ?? '').toUpperCase() == 'CC' ||
      RegExp(
        r'(?:^|\b)(?:CAR\.?|CC|CARABINIER)',
        caseSensitive: false,
      ).hasMatch(titolo ?? '');
}
