class Config {
  /// Adresse de ton API (celle donnée par Render, sans "/" à la fin).
  /// Peut être passée au lancement :
  /// flutter run --dart-define=API_URL=https://ding-api.onrender.com
  static const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://VOTRE-API.onrender.com',
  );

  /// Mode campus : domaine d'email obligatoire à l'inscription.
  /// Laisse vide pour accepter tous les emails (ex. pendant les tests).
  /// Le serveur applique aussi sa propre règle (variable ALLOWED_EMAIL_DOMAIN).
  static const allowedEmailDomain = '';

  /// Distance maximale (en mètres) pour que l'alarme sonne.
  /// Doit rester identique à ALARM_RADIUS_METERS côté API.
  static const alarmRadiusMeters = 150;
}
