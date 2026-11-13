import 'api_client.dart';
import 'models.dart';

class Repository {
  Repository(this._api);
  final ApiClient _api;

  // ───────────── Authentification ─────────────

  /// Crée le compte. L'acceptation des conditions est obligatoire : l'API
  /// refuse la création sans elle, et garde la version acceptée.
  Future<void> signUp({
    required String firstName,
    required String email,
    required String password,
    bool acceptTerms = false,
  }) async {
    final res = await _api.request('POST', '/auth/signup', body: {
      'first_name': firstName,
      'email': email,
      'password': password,
      'accept_terms': acceptTerms,
    });
    await _api.setToken((res as Map)['token'] as String);
  }

  Future<void> logIn({
    required String email,
    required String password,
  }) async {
    final res = await _api.request('POST', '/auth/login', body: {
      'email': email,
      'password': password,
    });
    await _api.setToken((res as Map)['token'] as String);
  }

  /// Déconnexion : le jeton est d'abord révoqué côté serveur (utile si le
  /// téléphone a été perdu), puis effacé localement — même si le réseau a
  /// coupé entre les deux, parce qu'on veut pouvoir se déconnecter hors ligne.
  Future<void> logOut() async {
    try {
      await _api.request('POST', '/auth/logout');
    } on ApiException {
      // Rien à faire : le jeton local s'en va de toute façon.
    }
    await _api.setToken(null);
  }

  /// Demande l'envoi d'un code à 6 chiffres. L'API répond toujours OK, même
  /// si l'email est inconnu (pour ne pas révéler quels comptes existent).
  Future<void> requestPasswordReset(String email) async {
    await _api.request('POST', '/auth/forgot', body: {'email': email});
  }

  /// Échange le code contre un nouveau mot de passe. L'utilisateur est
  /// connecté directement si le code est bon.
  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    final res = await _api.request('POST', '/auth/reset', body: {
      'email': email,
      'code': code,
      'password': password,
    });
    await _api.setToken((res as Map)['token'] as String);
  }

  /// Confirme l'adresse email avec le code à 6 chiffres reçu.
  Future<void> verifyEmail(String code) async {
    await _api.request('POST', '/auth/verify-email', body: {'code': code});
  }

  /// Demande un nouveau code. L'API impose une minute d'attente entre deux
  /// envois : le message d'erreur le dit, l'écran l'affiche tel quel.
  Future<void> resendVerification() async {
    await _api.request('POST', '/auth/verify-email/resend');
  }

  /// Ré-accepte les conditions après un changement de version.
  Future<void> acceptTerms() async {
    await _api.request('POST', '/auth/accept-terms');
  }

  /// Supprime définitivement le compte (et tout ce qui s'y rattache).
  Future<void> deleteAccount(String password) async {
    await _api.request('DELETE', '/me', body: {'password': password});
    await _api.setToken(null);
  }

  // ───────────── Profils ─────────────

  /// Une page de l'annuaire. `query` filtre sur le début du prénom.
  Future<CampusPage> campus({
    String query = '',
    int offset = 0,
    int limit = 25,
  }) async {
    final res = await _api.request('GET', '/profiles', query: {
      'q': query,
      'offset': '$offset',
      'limit': '$limit',
    });

    if (res is Map<String, dynamic>) return CampusPage.fromMap(res);

    // Serveur pas encore mis à jour (ancienne réponse : un tableau nu).
    // On l'accepte pour que l'app puisse sortir avant l'API.
    if (res is List) {
      final items = res
          .whereType<Map<String, dynamic>>()
          .map(Profile.fromMap)
          .where((p) => p.id.isNotEmpty)
          .toList();
      return CampusPage(items: items, total: items.length);
    }
    return const CampusPage(items: [], total: 0);
  }

  Future<Profile?> me() async {
    try {
      final row = await _api.request('GET', '/me');
      return Profile.fromMap(row as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<void> updateProfile({
    required String firstName,
    required String faculty,
    required String promotion,
    bool? discoverable,
  }) async {
    await _api.request('PUT', '/me', body: {
      'first_name': firstName,
      'faculty': faculty,
      'promotion': promotion,
      if (discoverable != null) 'discoverable': discoverable,
    });
  }

  // ───────────── Crushes ─────────────

  /// Les crushes que j'ai choisis. L'API ne révèle jamais
  /// ceux qui m'ont choisi.
  Future<Set<String>> myCrushes() async {
    final rows = await _api.request('GET', '/crushes') as List<dynamic>;
    return rows.whereType<String>().toSet();
  }

  /// Choisit ([active] = true) ou retire (false) un crush.
  ///
  /// Deux appels identiques donnent le même résultat : c'est volontaire, pour
  /// qu'un double appui ou un nouvel essai après un timeout ne puisse pas
  /// annuler le choix par accident.
  Future<void> setCrush(String target, {required bool active}) async {
    if (active) {
      await _api.request('POST', '/crushes/$target');
    } else {
      await _api.request('DELETE', '/crushes/$target');
    }
  }

  // ───────────── Blocage et signalement ─────────────

  /// Les personnes que j'ai bloquées, avec leur prénom (écran Profil).
  Future<List<Profile>> blocked() async {
    final rows = await _api.request('GET', '/blocks') as List<dynamic>;
    return rows
        .whereType<Map<String, dynamic>>()
        .map(Profile.fromMap)
        .where((p) => p.id.isNotEmpty)
        .toList();
  }

  /// Bloque quelqu'un : la personne disparaît de l'annuaire, les choix
  /// mutuels sont effacés et les alarmes de la paire supprimées.
  Future<void> block(String id) => _api.request('POST', '/blocks/$id');

  Future<void> unblock(String id) =>
      _api.request('DELETE', '/blocks/$id');

  /// Signale un profil. Motifs acceptés par l'API : `harcelement`,
  /// `faux_profil`, `intimidation`, `autre`.
  Future<void> report(String id, String reason, {String? details}) =>
      _api.request('POST', '/reports/$id', body: {
        'reason': reason,
        if (details != null && details.isNotEmpty) 'details': details,
      });

  // ───────────── Modération (équipe du campus) ─────────────

  /// La file des personnes signalées. L'API répond 403 si le compte n'est pas
  /// modérateur : c'est la seule protection, l'écran n'est qu'un confort.
  Future<List<ModerationItem>> moderationQueue({bool all = false}) async {
    final res = await _api.request(
      'GET',
      '/admin/reports',
      query: {if (all) 'status': 'all'},
    );
    final rows = res is Map ? res['items'] : null;
    if (rows is! List) return const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(ModerationItem.tryFromMap)
        .whereType<ModerationItem>()
        .toList();
  }

  /// Lève une suspension. Réservé aux modérateurs.
  Future<void> restoreAccount(String id) =>
      _api.request('POST', '/admin/users/$id/restore');

  /// Referme un signalement : `dismiss` classe sans suite, `ban` suspend le
  /// compte (connexion coupée, profil retiré de l'annuaire).
  Future<void> resolveReport(
    String id, {
    required ReportAction action,
    String? note,
  }) =>
      _api.request('POST', '/admin/reports/$id/resolve', body: {
        'action': action.wire,
        if (note != null && note.isNotEmpty) 'note': note,
      });

  // ───────────── Position et alarmes ─────────────

  Future<void> sendLocation(double lat, double lng) async {
    await _api.request('POST', '/location', body: {'lat': lat, 'lng': lng});
  }

  Future<List<AlarmItem>> myAlarms() async {
    final rows = await _api.request('GET', '/alarms') as List<dynamic>;
    return rows
        .whereType<Map<String, dynamic>>()
        .map(AlarmItem.tryFromMap)
        .whereType<AlarmItem>()
        .toList();
  }

  /// Réglages publics de l'API. `null` si le serveur est trop ancien :
  /// l'app garde alors ses propres valeurs.
  Future<ServerConfig?> config() async {
    try {
      return ServerConfig.tryFromMap(await _api.request('GET', '/config'));
    } on ApiException {
      return null;
    }
  }
}

/// Ce qu'un modérateur peut décider pour une personne signalée.
enum ReportAction {
  dismiss('dismiss'),

  /// Suspend le compte. Réversible côté base, pas depuis l'app : une
  /// réactivation demande une intervention manuelle, et c'est voulu.
  ban('ban');

  const ReportAction(this.wire);

  final String wire;
}
