import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config.dart';

class ApiException implements Exception {
  const ApiException(this.message, [this.status]);
  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// Client HTTP minimal : ajoute le jeton, décode le JSON, traduit les erreurs.
class ApiClient {
  ApiClient(this._prefs) : _token = _prefs.getString(_tokenKey);

  static const _tokenKey = 'auth_token';

  final SharedPreferences _prefs;
  final http.Client _http = http.Client();
  final _changes = StreamController<bool>.broadcast();
  String? _token;

  bool get loggedIn => _token != null;
  Stream<bool> get authChanges => _changes.stream;

  Future<void> setToken(String? token) async {
    _token = token;
    if (token == null) {
      await _prefs.remove(_tokenKey);
    } else {
      await _prefs.setString(_tokenKey, token);
    }
    _changes.add(token != null);
  }

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final req = http.Request(method, Uri.parse('${Config.apiUrl}$path'));
    req.headers['Content-Type'] = 'application/json';
    final token = _token;
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);

    http.Response res;
    try {
      // 60 s : l'offre gratuite d'hébergement met l'API en veille et
      // le premier appel peut prendre une minute pour la réveiller.
      final streamed =
          await _http.send(req).timeout(const Duration(seconds: 60));
      res = await http.Response.fromStream(streamed);
    } catch (_) {
      throw const ApiException(
        'Connexion impossible. Vérifie ta connexion internet.',
      );
    }

    dynamic data;
    if (res.body.isNotEmpty) {
      try {
        data = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {}
    }

    if (res.statusCode >= 400) {
      // Jeton expiré : retour à l'écran de connexion.
      if (res.statusCode == 401 && token != null) await setToken(null);
      final msg = data is Map && data['error'] is String
          ? data['error'] as String
          : 'Erreur serveur. Réessaie.';
      throw ApiException(msg, res.statusCode);
    }
    return data;
  }
}
