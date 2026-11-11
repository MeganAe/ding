import 'dart:convert';

import 'package:ding/core/providers.dart';
import 'package:ding/core/theme.dart';
import 'package:ding/data/api_client.dart';
import 'package:ding/data/token_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Une API de test : on décrit les réponses par route, et on relève les appels.
///
/// Les tests d'interface n'ont pas besoin d'un serveur : ils ont besoin de
/// réponses stables et de savoir ce que l'app a envoyé.
class FakeApi {
  FakeApi(this.respond);

  /// `respond('GET', '/profiles')` renvoie l'objet à sérialiser en JSON.
  /// Retourner `null` produit un 404.
  final Object? Function(String method, Uri uri) respond;

  final List<String> calls = [];

  bool called(String signature) => calls.contains(signature);

  http.Client get client => MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        final body = respond(req.method, req.url);
        if (body == null) {
          return http.Response('{"error":"introuvable"}', 404,
              headers: {'content-type': 'application/json'});
        }
        return http.Response(jsonEncode(body), 200,
            headers: {'content-type': 'application/json'});
      });
}

/// Ce qu'il faut pour monter un écran de l'app dans un test.
class TestApp {
  TestApp({required this.api, required this.prefs, required this.store});

  final FakeApi api;
  final SharedPreferences prefs;
  final TokenStore store;

  /// Pour les pages qui vivent d'habitude dans le Scaffold de `HomeShell` :
  /// sans Material au-dessus, les champs de texte ne peuvent pas se dessiner.
  Widget page(Widget child) => wrap(Scaffold(body: child));

  Widget wrap(Widget child) {
    final client = ApiClient(store, baseUrl: 'https://api.test',
        httpClient: api.client);
    return ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        tokenStoreProvider.overrideWithValue(store),
        apiClientProvider.overrideWithValue(client),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: child,
      ),
    );
  }
}

/// Prépare un écran isolé : préférences en mémoire, client HTTP bouchonné.
///
/// Le jeton n'est pas écrit dans le `TokenStore` : `flutter_secure_storage`
/// n'a pas d'implémentation en test (l'écriture resterait en attente). Les
/// écrans testés n'en ont pas besoin, les réponses sont simulées.
Future<TestApp> buildTestApp({
  required FakeApi api,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  return TestApp(api: api, prefs: p, store: TokenStore(p));
}

/// Monte un écran sur une surface de téléphone (390 × 844) plutôt que sur la
/// fenêtre de test par défaut (800 × 600), qui coupe le bas des pages.
Future<void> pumpPhone(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}
