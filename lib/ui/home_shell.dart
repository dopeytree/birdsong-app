import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../main.dart' show caps, ink, madder, paper, rule, sepia, serif;
import '../native/native_plate.dart';
import 'onboarding_screen.dart';
import 'plate_view.dart';
import 'settings_screen.dart';

/// The plate fills the app; everything else is under its menu button.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.app, this.onPlateLoaded});

  final AppState app;

  /// Called when the plate page has loaded, to lift the loading screen.
  final VoidCallback? onPlateLoaded;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  Timer? _checkTimer;
  var _checked = false;

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkTimer = Timer.periodic(const Duration(hours: 3), (_) => _check());
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  /// Once the welcome is done, and again whenever the app comes forward or
  /// has been open for three hours. The check itself waits 24 hours.
  void _check() {
    if (!mounted || !app.settings.onboarded) return;
    unawaited(app.updates.checkIfDue());
  }

  void _openSettings() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(app: app)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.settings,
      builder: (context, _) {
        if (app.settings.onboarded && !_checked) {
          _checked = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _check());
        }
        if (!app.settings.onboarded) {
          return OnboardingScreen(app: app, onDone: (_) {});
        }
        final plate = app.settings.nativePlate
            ? NativePlate(
                app: app,
                openSettings: _openSettings,
                onLoaded: widget.onPlateLoaded)
            : PlateView(
                app: app,
                openSettings: _openSettings,
                onLoaded: widget.onPlateLoaded);
        return Scaffold(
          // Edge to edge: the page's own paper runs under the status bar, the
          // Dynamic Island and the home indicator; the page pads its content
          // clear of them instead (PlateView passes it the insets).
          // The plate drawn by Flutter itself (the default), for Listen here
          // and for remote stations, or the old web page (Settings >
          // Experimental > Use the old web plate).
          // The update notice sits here, outside the plate's RepaintBoundary,
          // so a download's progress does not redraw the plate.
          body: Stack(
            fit: StackFit.expand,
            children: [
              plate,
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: _ModelNotice(app: app),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A slim paper strip along the top when a newer model build is ready.
class _ModelNotice extends StatelessWidget {
  const _ModelNotice({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app.updates, app.models]),
      builder: (context, _) {
        final updates = app.updates;
        final failed = updates.failed;
        final busy = updates.busy;
        final offer = updates.notice;
        if (failed != null) {
          return _strip(
            'The download failed. It will be offered again.',
            [_act('Close', sepia, updates.dismissFailure)],
          );
        }
        if (busy != null) {
          final pct = ((app.models.progress[busy.spec.id] ?? 0) * 100).round();
          return _strip('Downloading ${busy.spec.name}… $pct%', const []);
        }
        if (offer == null) return const SizedBox.shrink();
        final mb = (offer.model.bytes / 1e6).round();
        return _strip(
          'A newer ${offer.spec.name} is ready (${offer.label}, $mb MB).',
          [
            _act('Download', madder, () => unawaited(updates.accept(offer))),
            _act('Skip', sepia, () => updates.skip(offer)),
          ],
        );
      },
    );
  }

  /// The sentence is one line inside the 600-wide strip; Download and Skip
  /// take the line under it, set well apart.
  Widget _strip(String text, List<Widget> actions) {
    final message = Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: serif,
        fontStyle: FontStyle.italic,
        fontSize: 16,
        color: ink,
      ),
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Material(
            color: paper,
            elevation: 3,
            shadowColor: const Color(0x553C280A),
            shape: const RoundedRectangleBorder(side: BorderSide(color: rule)),
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 6, actions.length == 1 ? 6 : 14, 6),
              child: actions.isEmpty
                  ? message
                  : actions.length == 1
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: message),
                            actions.single,
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            message,
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 40,
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: actions,
                            ),
                          ],
                        ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _act(String label, Color color, VoidCallback onTap) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(
          fontFamily: caps,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
      ),
      onPressed: onTap,
      child: Text(label),
    );
  }
}
