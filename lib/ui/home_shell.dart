import 'package:flutter/material.dart';

import '../app_state.dart';
import '../native/native_plate.dart';
import '../settings.dart';
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
          // Experimental (Settings > Experimental): in Listen here the plate
          // drawn by Flutter itself. A remote station still uses the page.
          body: app.settings.nativePlate && app.settings.mode == AppMode.listen
              ? NativePlate(
                  app: app,
                  openSettings: () => _openSettings(context),
                  onLoaded: onPlateLoaded)
              : PlateView(
                  app: app,
                  openSettings: () => _openSettings(context),
                  onLoaded: onPlateLoaded),
        );
      },
    );
  }
}
