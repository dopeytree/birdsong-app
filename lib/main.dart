import 'package:flutter/material.dart';

import 'app_state.dart';
import 'ui/home_shell.dart';

const paper = Color(0xFFEFE9D8);
const ink = Color(0xFF2A241C);
const madder = Color(0xFF9C3B2E);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = await AppState.create();
  runApp(BirdsongApp(app: app));
}

class BirdsongApp extends StatelessWidget {
  const BirdsongApp({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: madder, surface: paper);
    return MaterialApp(
      title: 'Birdsong',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: paper,
        useMaterial3: true,
        fontFamily: 'Georgia',
      ),
      home: HomeShell(app: app),
    );
  }
}
