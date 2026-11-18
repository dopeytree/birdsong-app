import 'package:flutter/material.dart';

import '../app_state.dart';
import '../main.dart' show caps, paper, sepia, serif;
import 'home_shell.dart';


/// Height of the cardinal on the loading screen; the iPhone's own launch
/// screen (tool/launch, set by patch_platforms.py) draws it at the same size
/// in the same place, so one hands over to the other without a jump.
const cardinalHeight = 175.0;

/// How far above the middle the cardinal sits (the launch screen matches).
const cardinalLift = 56.0;

/// The northern cardinal and the line from the page's Support section.
class Cardinal extends StatelessWidget {
  const Cardinal({super.key, this.height = cardinalHeight});

  final double height;

  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/app/cardinal.png', height: height, filterQuality: FilterQuality.medium);
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
  const Splash({super.key, this.error, this.ready = false});

  final Object? error;

  /// The app has started: say that a tap goes in.
  final bool ready;

  @override
  Widget build(BuildContext context) {
    // Material, so the text has a proper style (bare text shows Flutter's
    // yellow underline).
    return Material(
      color: paper,
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: box.maxHeight / 2 - cardinalLift - cardinalHeight / 2,
              child: const Center(child: Cardinal()),
            ),
            Positioned(
              left: 36,
              right: 36,
              top: box.maxHeight / 2 - cardinalLift + cardinalHeight / 2 + 28,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: error == null
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SupportQuote(),
                            const SizedBox(height: 28),
                            AnimatedOpacity(
                              opacity: ready ? 1 : 0,
                              duration: const Duration(milliseconds: 900),
                              child: Text('tap to begin',
                                  style: TextStyle(
                                      fontFamily: caps,
                                      color: sepia.withValues(alpha: 0.7),
                                      fontSize: 14,
                                      letterSpacing: 1.2)),
                            ),
                          ],
                        )
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

/// Starts the app behind the loading screen, which stays until tapped.
/// The plate is only built after the tap: on macOS the web view draws over
/// anything Flutter puts on top of it, so it can't wait underneath. After the
/// tap the screen stays until the plate has loaded, then fades.
class Boot extends StatefulWidget {
  const Boot({super.key, required this.boot});

  final Future<AppState> boot;

  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  AppState? _app;
  Object? _error;
  bool _tapped = false;
  bool _plateLoaded = false;
  bool _onboarded = true;

  // "Show the welcome again": back to the cardinal first, then the setup.
  void _settingsChanged() {
    final now = _app!.settings.onboarded;
    if (_onboarded && !now && mounted) {
      setState(() {
        _tapped = false;
        _plateLoaded = false;
      });
    }
    _onboarded = now;
  }

  @override
  void dispose() {
    _app?.settings.removeListener(_settingsChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.boot.then((a) {
      if (!mounted) return;
      setState(() => _app = a);
      _onboarded = a.settings.onboarded;
      a.settings.addListener(_settingsChanged);
    }, onError: (Object e, StackTrace _) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    final done = app != null && _tapped && (_plateLoaded || !app.settings.onboarded);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (app != null && _tapped)
          HomeShell(
            app: app,
            onPlateLoaded: () {
              if (mounted && !_plateLoaded) setState(() => _plateLoaded = true);
            },
          ),
        IgnorePointer(
          ignoring: done,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: app == null || _tapped
                ? null
                : () {
                    setState(() => _tapped = true);
                    // Don't hold the screen up for ever if the page stalls.
                    Future.delayed(const Duration(seconds: 6), () {
                      if (mounted && !_plateLoaded) setState(() => _plateLoaded = true);
                    });
                  },
            child: AnimatedOpacity(
              opacity: done ? 0 : 1,
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOut,
              child: Splash(error: _error, ready: app != null),
            ),
          ),
        ),
      ],
    );
  }
}
