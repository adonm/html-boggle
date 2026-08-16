import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'debug_hooks.dart';
import 'game.dart';
import 'screens.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Real semantics DOM: screen readers and tests can navigate the app.
  SemanticsBinding.instance.ensureSemantics();

  final game = Game();
  await game.init();
  installDebugHooks(game);

  final themes = ThemeController.instance;

  runApp(
    ListenableBuilder(
      listenable: themes,
      builder: (context, _) => MaterialApp(
        title: 'Boggle',
        debugShowCheckedModeBanner: false,
        theme: themes.themeData,
        home: HomeScreen(game: game),
      ),
    ),
  );
}
