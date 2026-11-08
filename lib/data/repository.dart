import 'api_client.dart';
import 'models.dart';

class Repository {
  Repository(this._api);
  final ApiClient _api;

  // ───────────── Compte ─────────────
  Future<void> signUp({
    required String firstName,
    required String email,
    required String password,
  }) async {
    final data = await _api.request('POST', '/auth/signup', body: {
      'first_name': firstName,
      'email': email,
      'password': password,
    }) as Map<String, dynamic>;
    await _api.setToken(data['token'] as String);
  }

  Future<void> logIn({required String email, required String password}) async {
    final data = await _api.request('POST', '/auth/login', body: {
      'email': email,
      'password': password,
    }) as Map<String, dynamic>;
    await _api.setToken(data['token'] as String);
  }

  Future<void> logOut() => _api.setToken(null);

  // ───────────── Profil ─────────────
  Future<Profile?> me() async {
    final data = await _api.request('GET', '/me');
    return Profile.fromMap(data as Map<String, dynamic>);
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

  Future<List<Profile>> campus() async {
    final data = await _api.request('GET', '/profiles') as List<dynamic>;
    return data
        .map<Profile>((e) => Profile.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  // ───────────── Crushes ─────────────
  /// Les crushes que j'ai choisis. L'API ne révèle jamais
  /// ceux qui m'ont choisi.
  Future<Set<String>> myCrushes() async {
    final data = await _api.request('GET', '/crushes') as List<dynamic>;
    return data.map<String>((e) => e as String).toSet();
  }

  /// Retourne true si le crush est maintenant actif, false s'il est retiré.
  Future<bool> toggleCrush(String target) async {
    final data = await _api.request('POST', '/crushes/$target/toggle')
        as Map<String, dynamic>;
    return data['active'] as bool;
  }

  // ───────────── Position et alarmes ─────────────
  Future<void> sendLocation(double lat, double lng) async {
    await _api.request('POST', '/location', body: {'lat': lat, 'lng': lng});
  }

  Future<List<AlarmItem>> myAlarms() async {
    final data = await _api.request('GET', '/alarms') as List<dynamic>;
    return data
        .map<AlarmItem>((e) => AlarmItem.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}
