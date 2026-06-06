class GhConfig {
  static const String owner = 'rdagmr98';
  static const String dataRepo = 'corsi-data';
  static const String readPat = String.fromEnvironment(
    'READ_PAT',
    defaultValue: 'REPLACE_WITH_READ_ONLY_PAT',
  );
  static const String passwordSalt = 'corsi_salt_2024';
  static bool get isConfigured => readPat != 'REPLACE_WITH_READ_ONLY_PAT';
}
