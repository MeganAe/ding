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

  /// false si l'app a été compilée sans --dart-define=API_URL.
  /// Permet d'afficher une erreur claire au lieu d'un « connexion impossible ».
  static bool get isConfigured => _rawApiUrl.trim().isNotEmpty;

  /// Mode campus : domaine d'email obligatoire à l'inscription.
  /// Laisse vide pour accepter tous les emails (ex. pendant les tests).
  /// Doit rester cohérent avec ALLOWED_EMAIL_DOMAIN côté API.
  static const allowedEmailDomain = '';

  /// Distance maximale (en mètres) pour que l'alarme sonne.
  /// Doit rester identique à ALARM_RADIUS_METERS côté API (150 par défaut).
  static const alarmRadiusMeters = 150;

  /// Fréquence d'envoi de la position (l'app ne suit que lorsqu'elle est
  /// ouverte : voir la limite du premier plan dans le README).
  static const locationInterval = Duration(minutes: 2);

  /// Fréquence d'interrogation des alarmes.
  static const alarmPollInterval = Duration(seconds: 20);
}
