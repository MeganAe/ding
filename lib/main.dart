import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/providers.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'data/token_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Barres système au papier, icônes sombres. Sans ça, Android 8 et 9
  // affichent une barre de navigation noire en bas de l'écran — un liseré noir
  // très visible sous l'onboarding, dont le bas est clair. (Le thème Android
  // fait de même pour l'écran de démarrage : tool/android/styles.xml.)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: DingColors.paper,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: DingColors.paper,
    ),
  );
  final prefs = await SharedPreferences.getInstance();
  final tokens = TokenStore(prefs);
  // Le jeton vit dans le Keystore : il faut le lire avant de connaître
  // l'état de connexion (le routeur en dépend).
  await tokens.load();

  runApp(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        tokenStoreProvider.overrideWithValue(tokens),
      ],
      child: const DingApp(),
    ),
  );
}

class DingApp extends ConsumerWidget {
  const DingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Ding',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
