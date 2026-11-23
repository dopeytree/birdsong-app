import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../main.dart' show paper;
import 'plate_buttons.dart';
import 'settings_screen.dart';

/// The plate's menu button. Settings grows out of it as a sheet of paper
/// (the animations package's container transform) and shrinks back into it
/// on closing. No shadow and no disc behind the icon: plain paper, as the
/// rest of the plate.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key, required this.app, required this.color});

  final AppState app;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return OpenContainer<void>(
      transitionDuration: const Duration(milliseconds: 300),
      closedShape: const CircleBorder(),
      closedElevation: 0,
      openElevation: 0,
      closedColor: Colors.transparent,
      middleColor: paper,
      openColor: paper,
      tappable: false,
      closedBuilder: (context, open) => IconButton(
        tooltip: 'Settings',
        constraints: const BoxConstraints.tightFor(
            width: SourcePill.rowHeight, height: SourcePill.rowHeight),
        icon: const Icon(Icons.menu),
        color: color,
        onPressed: open,
      ),
      openBuilder: (context, _) => SettingsScreen(app: app),
    );
  }
}
