import 'package:flutter/material.dart';

import '../app_state.dart';
import 'onboarding_screen.dart';
import 'plate_view.dart';
import 'settings_screen.dart';

/// The plate fills the app; everything else is under its menu button.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.app, this.onPlateLoaded});

  final AppState app;

  /// Called when the plate page has loaded, to lift the loading screen.
  final VoidCallback? onPlateLoaded;

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
          // Edge to edge: the page's own paper runs under the status bar, the
          // Dynamic Island and the home indicator; the page pads its content
          // clear of them instead (PlateView passes it the insets).
          body: PlateView(
              app: app,
              openSettings: () => _openSettings(context),
              onLoaded: onPlateLoaded),
        );
      },
    );
  }
}
