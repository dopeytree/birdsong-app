import 'package:flutter/material.dart';

import '../app_state.dart';
import 'listen_screen.dart';
import 'models_screen.dart';
import 'plate_view.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.app});

  final AppState app;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [
            PlateView(app: app),
            ListenScreen(app: app),
            ModelsScreen(app: app),
            SettingsScreen(app: app),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.image_outlined), label: 'Plate'),
          NavigationDestination(icon: Icon(Icons.hearing), label: 'Listen'),
          NavigationDestination(icon: Icon(Icons.memory), label: 'Models'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
        ],
      ),
    );
  }
}
