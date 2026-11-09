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

  // ───────────── Profils ─────────────

  Future<List<Profile>> campus() async {
    final rows = await _api.request('GET', '/profiles') as List<dynamic>;
    return rows
        .map<Profile>((e) => Profile.fromMap(e as Map<String, dynamic>))
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
  }) async {
    await _api.request('PUT', '/me', body: {
      'first_name': firstName,
      'faculty': faculty,
      'promotion': promotion,
    });
  }

  // ───────────── Crushes ─────────────

  /// Les crushes que j'ai choisis. L'API ne révèle jamais
  /// ceux qui m'ont choisi.
  Future<Set<String>> myCrushes() async {
    final rows = await _api.request('GET', '/crushes') as List<dynamic>;
    return rows.map<String>((e) => e as String).toSet();
  }

  /// Retourne true si le crush est maintenant actif, false s'il est retiré.
  Future<bool> toggleCrush(String target) async {
    final res = await _api.request('POST', '/crushes/$target/toggle');
    return (res as Map)['active'] as bool;
  }

  // ───────────── Position et alarmes ─────────────

  Future<void> sendLocation(double lat, double lng) async {
    await _api.request('POST', '/location', body: {'lat': lat, 'lng': lng});
  }

  Future<List<AlarmItem>> myAlarms() async {
    final rows = await _api.request('GET', '/alarms') as List<dynamic>;
    return rows
        .map<AlarmItem>((e) => AlarmItem.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}
