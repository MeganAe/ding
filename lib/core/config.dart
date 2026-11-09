class Config {
  /// Adresse de l'API Ding (sans « / » final). Passée au build :
  /// flutter run --dart-define=API_URL=https://ton-api.onrender.com
  /// En CI, elle vient du secret GitHub API_URL.
  static const _defaultApiUrl = 'https://VOTRE-API.onrender.com';
  static const _rawApiUrl = String.fromEnvironment('API_URL');

  static String get apiUrl {
    final v = _rawApiUrl.trim().isEmpty ? _defaultApiUrl : _rawApiUrl.trim();
    return v.replaceAll(RegExp(r'/+$'), '');
  }

  /// Mode campus : domaine d'email obligatoire à l'inscription.
  /// Laisse vide pour accepter tous les emails (ex. pendant les tests).
  /// Doit rester cohérent avec ALLOWED_EMAIL_DOMAIN côté API.
  static const allowedEmailDomain = '';

  /// Distance maximale (en mètres) pour que l'alarme sonne.
  /// Doit rester identique à ALARM_RADIUS_METERS côté API (150 par défaut).
  static const alarmRadiusMeters = 150;
}
