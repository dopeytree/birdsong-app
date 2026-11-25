import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../app_state.dart';
import '../main.dart' show paper, rule;
import 'plate_buttons.dart';
import 'settings_screen.dart';

/// The plate's menu button. Slides Settings in cleanly from the right:
/// a 390 px sidebar on desktop / iPad (so the plate stays visible and updates
/// live beside it), or full screen on phones.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key, required this.app, required this.color, this.onOpenCalendar});

  final AppState app;
  final Color color;
  final VoidCallback? onOpenCalendar;

  void _open(BuildContext context) {
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: const Color(0x382A241C),
      barrierLabel: 'Close settings',
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, _, __) {
        final wide = MediaQuery.sizeOf(context).width >= 820;
        final sheet = CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
          child: Focus(
            autofocus: true,
            child: SettingsScreen(app: app, onOpenCalendar: onOpenCalendar),
          ),
        );
        if (!wide) return sheet;
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            width: 420,
            decoration: const BoxDecoration(
              color: paper,
              border: Border(left: BorderSide(color: rule)),
              boxShadow: [BoxShadow(color: Color(0x3D2A241C), blurRadius: 24, offset: Offset(-4, 0))],
            ),
            child: sheet,
          ),
        );
      },
      transitionsBuilder: (context, anim, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
        child: child,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Settings',
      constraints: const BoxConstraints.tightFor(
          width: SourcePill.rowHeight, height: SourcePill.rowHeight),
      icon: const Icon(Icons.menu),
      color: color,
      onPressed: () => _open(context),
    );
  }
}
