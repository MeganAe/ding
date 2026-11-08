class Config {
  /// Renseigne ces deux valeurs (Supabase > Project Settings > API),
  /// ou passe-les au lancement :
  /// flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://VOTRE-PROJET.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'VOTRE_CLE_ANON',
  );

  /// Mode campus : domaine d'email obligatoire à l'inscription.
  /// Laisse vide pour accepter tous les emails (ex. pendant les tests).
  static const allowedEmailDomain = '';

  /// Distance maximale (en mètres) pour que l'alarme sonne.
  /// Doit rester identique à la valeur dans supabase/schema.sql.
  static const alarmRadiusMeters = 150;
}
