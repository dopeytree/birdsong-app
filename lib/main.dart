import 'package:flutter/material.dart';

import 'app_state.dart';
import 'ui/home_shell.dart';

const paper = Color(0xFFEFE9D8);
const ink = Color(0xFF2A241C);
const madder = Color(0xFF9C3B2E);

// The plate's typefaces: IM Fell English for text, its small caps for
// headings, as the page uses them.
const serif = 'IM Fell English';
const caps = 'IM Fell English SC';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = await AppState.create();
  runApp(BirdsongApp(app: app));
}

ThemeData birdsongTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: madder, surface: paper);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true).textTheme
      .apply(fontFamily: serif);
  // IM Fell has one weight; let it stand rather than be faked bold.
  TextStyle? heading(TextStyle? t, double spacing) =>
      t?.copyWith(fontFamily: caps, fontWeight: FontWeight.w400, letterSpacing: spacing);
  TextStyle? plain(TextStyle? t) => t?.copyWith(fontWeight: FontWeight.w400);
  final text = base.copyWith(
    displayLarge: plain(base.displayLarge),
    displayMedium: plain(base.displayMedium),
    displaySmall: plain(base.displaySmall),
    headlineLarge: heading(base.headlineLarge, 1.2),
    headlineMedium: heading(base.headlineMedium, 1.1),
    headlineSmall: heading(base.headlineSmall, 1.0),
    titleLarge: heading(base.titleLarge, 0.8),
    titleMedium: heading(base.titleMedium, 0.6),
    titleSmall: heading(base.titleSmall, 0.5),
    bodyLarge: base.bodyLarge?.copyWith(fontSize: 17),
    bodyMedium: base.bodyMedium?.copyWith(fontSize: 16),
    bodySmall: base.bodySmall?.copyWith(fontSize: 13.5),
    labelLarge: plain(base.labelLarge)?.copyWith(fontSize: 15.5),
    labelMedium: plain(base.labelMedium),
    labelSmall: plain(base.labelSmall),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: serif,
    textTheme: text,
    scaffoldBackgroundColor: paper,
  );
}

class BirdsongApp extends StatelessWidget {
  const BirdsongApp({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Birdsong',
      debugShowCheckedModeBanner: false,
      theme: birdsongTheme(),
      home: HomeShell(app: app),
    );
  }
}
