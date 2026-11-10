import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/config.dart';
import 'token_store.dart';

class ApiException implements Exception {
  const ApiException(this.message, [this.status]);
  final String message;
  final int? status;

  /// true pour une coupure réseau / un serveur injoignable : dans ce cas
  /// l'app peut proposer de réessayer plutôt que d'afficher un message brut.
  bool get isNetwork => status == null;

  @override
  String toString() => message;
}

/// Client HTTP minimal : ajoute le jeton, décode le JSON, traduit les erreurs.
class ApiClient {
  ApiClient(this._tokens, {http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        _baseUrl = baseUrl;

  static const _timeout = Duration(seconds: 30);

  final TokenStore _tokens;
  final http.Client _http;

  /// Adresse imposée (tests) ; sinon celle de la configuration de build.
  final String? _baseUrl;
  final _changes = StreamController<bool>.broadcast();

  bool get loggedIn => _tokens.hasToken;
  Stream<bool> get authChanges => _changes.stream;

  Future<void> setToken(String? token) async {
    await _tokens.save(token);
    if (!_changes.isClosed) _changes.add(token != null);
  }

  void dispose() {
    _http.close();
    _changes.close();
  }

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (_baseUrl == null && !Config.isConfigured) {
      throw const ApiException(
        "L'app n'a pas d'adresse d'API.\n"
        'Relance-la avec --dart-define=API_URL=https://ton-api.onrender.com',
      );
    }

    final req = http.Request(method, Uri.parse('${_baseUrl ?? Config.apiUrl}$path'));
    req.headers['Content-Type'] = 'application/json';
    final token = _tokens.token;
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);

    http.Response res;
    try {
      // 30 s : l'offre gratuite d'hébergement met l'API en veille et le
      // premier appel peut être long. Au-delà, mieux vaut réessayer.
      final streamed = await _http.send(req).timeout(_timeout);
      res = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException(
        'Le serveur met trop de temps à répondre. Réessaie dans un instant.',
      );
    } on SocketException {
      throw const ApiException(
        'Connexion impossible. Vérifie ta connexion internet.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Connexion impossible. Vérifie ta connexion internet.',
      );
    }

    dynamic data;
    if (res.body.isNotEmpty) {
      try {
        data = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        // Corps non JSON (page d'erreur d'un proxy…) : laissé à null.
      }
    }

    if (res.statusCode >= 400) {
      // Jeton expiré ou compte supprimé : retour à l'écran de connexion.
      if (res.statusCode == 401 && token != null) await setToken(null);
      final msg = data is Map && data['error'] is String
          ? data['error'] as String
          : (res.statusCode == 429
              ? 'Trop de tentatives. Patiente un instant.'
              : 'Erreur serveur (${res.statusCode}). Réessaie.');
      throw ApiException(msg, res.statusCode);
    }
    return data;
  }
}
