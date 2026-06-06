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
    required this.createdAt,
    required this.updatedAt,
  });

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
  }) => AppUser(
    id: id,
    nome: nome ?? this.nome,
    cognome: cognome ?? this.cognome,
    email: identical(email, _s) ? this.email : email as String?,
    username: identical(username, _s) ? this.username : username as String?,
    role: role ?? this.role,
    isActive: isActive ?? this.isActive,
    goOverride: goOverride ?? this.goOverride,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );
}
