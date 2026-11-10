import 'api_client.dart';
import 'models.dart';

class Repository {
  Repository(this._api);
  final ApiClient _api;

  // ───────────── Authentification ─────────────

  Future<void> signUp({
    required String firstName,
    required String email,
    required String password,
  }) async {
    final res = await _api.request('POST', '/auth/signup', body: {
      'first_name': firstName,
      'email': email,
      'password': password,
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

  Future<void> logOut() => _api.setToken(null);

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

  /// Supprime définitivement le compte (et tout ce qui s'y rattache).
  Future<void> deleteAccount(String password) async {
    await _api.request('DELETE', '/me', body: {'password': password});
    await _api.setToken(null);
  }

  // ───────────── Profils ─────────────

  Future<List<Profile>> campus() async {
    final rows = await _api.request('GET', '/profiles') as List<dynamic>;
    return rows
        .whereType<Map<String, dynamic>>()
        .map(Profile.fromMap)
        .where((p) => p.id.isNotEmpty)
        .toList();
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
}
