import 'package:flutter/material.dart';

import '../app_state.dart';
import 'onboarding_screen.dart';
import 'plate_view.dart';
import 'settings_screen.dart';

/// The plate fills the app; everything else is under its menu button.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.app});

  final AppState app;

  void _openSettings(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(app: app)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.settings,
      builder: (context, _) {
        if (!app.settings.onboarded) {
          return OnboardingScreen(app: app, onDone: (_) {});
        }
        return Scaffold(
          body: SafeArea(
            child: PlateView(app: app, openSettings: () => _openSettings(context)),
          ),
        );
      },
    );
  }
}
