import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../main.dart' show paper, serif;
import 'home_shell.dart';

const sepia = Color(0xFF6B5338);

/// Height of the cardinal on the loading screen; the iPhone's own launch
/// screen (tool/launch, set by patch_platforms.py) draws it at the same size
/// in the same place, so one hands over to the other without a jump.
const cardinalHeight = 175.0;

/// The northern cardinal and the line from the page's Support section.
class Cardinal extends StatelessWidget {
  const Cardinal({super.key, this.height = cardinalHeight});

  final double height;

  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/app/cardinal.webp', height: height, filterQuality: FilterQuality.medium);
}

class SupportQuote extends StatelessWidget {
  const SupportQuote({super.key, this.size = 17});

  final double size;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontFamily: serif, color: sepia, fontSize: size, height: 1.45);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Beautiful things, “singing out brilliantly from the wreck of time” '
          '— passed hand to hand to the next generation of lovers.',
          textAlign: TextAlign.center,
          style: base.copyWith(fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'after Donna Tartt, '),
            TextSpan(text: 'The Goldfinch', style: base.copyWith(fontStyle: FontStyle.italic)),
          ]),
          textAlign: TextAlign.center,
          style: base.copyWith(fontSize: size * 0.82),
        ),
      ],
    );
  }
}

class Splash extends StatelessWidget {
  const Splash({super.key, this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: paper,
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            const Center(child: Cardinal()),
            Positioned(
              left: 36,
              right: 36,
              top: box.maxHeight / 2 + cardinalHeight / 2 + 28,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: error == null
                      ? const SupportQuote()
                      : Text('Birdsong could not start:\n$error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontFamily: serif, color: sepia)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Starts the app behind the loading screen, and lifts it once the plate
/// has drawn (or after a while regardless).
class Boot extends StatefulWidget {
  const Boot({super.key, required this.boot});

  final Future<AppState> boot;

  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  AppState? _app;
  Object? _error;
  bool _minDone = false;
  bool _plateDrawn = false;
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    widget.boot.then((a) {
      if (mounted) setState(() => _app = a);
    }, onError: (Object e, StackTrace _) {
      if (mounted) setState(() => _error = e);
    });
    _timers
      ..add(Timer(const Duration(milliseconds: 1800), () => _set(() => _minDone = true)))
      ..add(Timer(const Duration(seconds: 8), () => _set(() => _plateDrawn = true)));
  }

  void _set(VoidCallback f) {
    if (mounted) setState(f);
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  void _plateLoaded() {
    // The page has loaded; give it a moment to fetch and lay out its birds.
    _timers.add(Timer(const Duration(milliseconds: 900), () => _set(() => _plateDrawn = true)));
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    final done = app != null && _minDone && (_plateDrawn || !app.settings.onboarded);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (app != null) HomeShell(app: app, onPlateLoaded: _plateLoaded),
        IgnorePointer(
          ignoring: done,
          child: AnimatedOpacity(
            opacity: done ? 0 : 1,
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOut,
            child: Splash(error: _error),
          ),
        ),
      ],
    );
  }
}
