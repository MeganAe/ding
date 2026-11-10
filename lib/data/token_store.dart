import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Conserve le jeton de session.
///
/// Le jeton donne un accès complet au compte : il va donc dans le Keystore
/// Android (via flutter_secure_storage) et non dans SharedPreferences, qui
/// n'est qu'un fichier XML lisible sur un appareil rooté et inclus dans les
/// sauvegardes.
class TokenStore {
  TokenStore(this._prefs);

  static const _key = 'auth_token';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  String? _token;
  String? get token => _token;
  bool get hasToken => _token != null;

  /// À appeler une fois au démarrage, avant de construire l'app.
  Future<void> load() async {
    try {
      _token = await _secure.read(key: _key);
    } catch (_) {
      // Keystore indisponible : on repart d'une session vide.
      _token = null;
    }

    // Migration : les versions ≤ 0.1 stockaient le jeton en clair.
    final legacy = _prefs.getString(_key);
    if (legacy != null) {
      if (_token == null) await save(legacy);
      await _prefs.remove(_key);
    }
  }

  Future<void> save(String? token) async {
    _token = token;
    try {
      if (token == null) {
        await _secure.delete(key: _key);
      } else {
        await _secure.write(key: _key, value: token);
      }
    } catch (_) {
      // Repli : mieux vaut une session qui marche qu'une déconnexion forcée
      // sur les rares appareils sans Keystore exploitable.
      if (token == null) {
        await _prefs.remove(_key);
      } else {
        await _prefs.setString(_key, token);
      }
    }
  }
}
