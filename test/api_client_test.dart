import 'dart:convert';

import 'package:ding/data/api_client.dart';
import 'package:ding/data/repository.dart';
import 'package:ding/data/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _base = 'https://api.test';

Future<TokenStore> _emptyStore() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return TokenStore(prefs);
}

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiClient', () {
    test('ajoute le jeton dans l’en-tête Authorization', () async {
      final store = await _emptyStore();
      await store.save('jeton-abc');

      String? vu;
      final client = ApiClient(
        store,
        baseUrl: _base,
        httpClient: MockClient((req) async {
          vu = req.headers['Authorization'];
          return _json(const {'ok': true});
        }),
      );

      await client.request('GET', '/me');
      expect(vu, 'Bearer jeton-abc');
    });

    test('efface le jeton quand le serveur répond 401', () async {
      final store = await _emptyStore();
      await store.save('jeton-expire');

      final client = ApiClient(
        store,
        baseUrl: _base,
        httpClient: MockClient(
          (_) async => _json(const {'error': 'Session expirée.'}, 401),
        ),
      );

      expect(client.loggedIn, isTrue);
      await expectLater(
        client.request('GET', '/me'),
        throwsA(isA<ApiException>()),
      );
      expect(client.loggedIn, isFalse);
      expect(store.token, isNull);
    });

    test('remonte le message d’erreur du serveur', () async {
      final store = await _emptyStore();
      final client = ApiClient(
        store,
        baseUrl: _base,
        httpClient: MockClient(
          (_) async =>
              _json(const {'error': 'Un compte existe déjà avec cet email.'}, 409),
        ),
      );

      await expectLater(
        client.request('POST', '/auth/signup'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message',
                  'Un compte existe déjà avec cet email.')
              .having((e) => e.status, 'status', 409),
        ),
      );
    });

    test('traduit une réponse 429 sans corps JSON', () async {
      final store = await _emptyStore();
      final client = ApiClient(
        store,
        baseUrl: _base,
        httpClient: MockClient((_) async => http.Response('', 429)),
      );

      await expectLater(
        client.request('POST', '/location'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('Trop de tentatives'))),
      );
    });
  });

  group('Repository', () {
    test('setCrush(true) fait un POST, setCrush(false) un DELETE', () async {
      final store = await _emptyStore();
      final appels = <String>[];
      final repo = Repository(ApiClient(
        store,
        baseUrl: _base,
        httpClient: MockClient((req) async {
          appels.add('${req.method} ${req.url.path}');
          return _json(const {'active': true});
        }),
      ));

      await repo.setCrush('id-1', active: true);
      await repo.setCrush('id-1', active: false);

      // Idempotence : un second appui ne peut pas annuler le premier.
      expect(appels, ['POST /crushes/id-1', 'DELETE /crushes/id-1']);
    });

    test('myAlarms ignore les lignes inutilisables', () async {
      final store = await _emptyStore();
      final repo = Repository(ApiClient(
        store,
        baseUrl: _base,
        httpClient: MockClient(
          (_) async => _json([
            {
              'alarm_id': 'a1',
              'created_at': '2026-11-09T10:00:00Z',
              'other_id': 'u1',
              'other_name': 'Bo',
            },
            {'alarm_id': 'a2'}, // incomplète
          ]),
        ),
      ));

      final alarmes = await repo.myAlarms();
      expect(alarmes, hasLength(1));
      expect(alarmes.single.id, 'a1');
    });

    test('campus ignore les profils sans identifiant', () async {
      final store = await _emptyStore();
      final repo = Repository(ApiClient(
        store,
        baseUrl: _base,
        httpClient: MockClient(
          (_) async => _json([
            {'id': 'u1', 'first_name': 'Bo'},
            {'first_name': 'Sans id'},
          ]),
        ),
      ));

      final profils = await repo.campus();
      expect(profils, hasLength(1));
      expect(profils.single.firstName, 'Bo');
    });

    test('resetPassword enregistre le nouveau jeton', () async {
      final store = await _emptyStore();
      final repo = Repository(ApiClient(
        store,
        baseUrl: _base,
        httpClient: MockClient(
          (_) async => _json(const {'ok': true, 'token': 'jeton-neuf'}),
        ),
      ));

      await repo.resetPassword(
        email: 'a@example.com',
        code: '123456',
        password: 'secret123',
      );
      expect(store.token, 'jeton-neuf');
    });
  });
}
