import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_state.dart';
import '../settings.dart';
import 'format.dart';

/// Birdsong's own page, served by the app's local server. In Listen here it
/// shows one listening session at a time, with arrows to step through them,
/// and a microphone button to start a new one.
class PlateView extends StatefulWidget {
  const PlateView({super.key, required this.app, required this.openTab});

  final AppState app;

  /// Switch the app to another tab (2 is Models).
  final ValueChanged<int> openTab;

  @override
  State<PlateView> createState() => _PlateViewState();
}

class _PlateViewState extends State<PlateView> {
  late final WebViewController _web;
  late AppMode _mode;
  late String _plateModel;
  late String _station;
  Timer? _refreshSoon;
  String _livePushed = '';

  AppState get app => widget.app;
  Settings get _s => app.settings;

  // Listen here: the page's period buttons and date line give way to the
  // session bar, and period=all lets the session decide what is drawn.
  Uri get _url => Uri.parse(_s.mode == AppMode.listen
      ? '${app.server.origin}/?period=all&hide=periods,date'
      : '${app.server.origin}/');

  @override
  void initState() {
    super.initState();
    _mode = _s.mode;
    _plateModel = _s.plateModel;
    _station = '${_s.birdnetBase}|${_s.stationDigits}';
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) {
        _livePushed = '';
        _pushLive();
      }))
      ..loadRequest(_url);
    _s.addListener(_settingsChanged);
    app.store.addListener(_storeChanged);
    app.engine.addListener(_pushLive);
  }

  @override
  void dispose() {
    _refreshSoon?.cancel();
    _s.removeListener(_settingsChanged);
    app.store.removeListener(_storeChanged);
    app.engine.removeListener(_pushLive);
    super.dispose();
  }

  void _settingsChanged() {
    final station = '${_s.birdnetBase}|${_s.stationDigits}';
    if (_s.mode != _mode || _s.plateModel != _plateModel || station != _station) {
      _mode = _s.mode;
      _plateModel = _s.plateModel;
      _station = station;
      _web.loadRequest(_url);
    }
  }

  // A new detection, or another session picked: ask the page to fetch again.
  // Coalesced, since a burst of detections arrives within one window.
  void _storeChanged() {
    _refreshSoon ??= Timer(const Duration(milliseconds: 500), () {
      _refreshSoon = null;
      _web
          .runJavaScript('typeof refresh==="function"&&refresh(false)')
          .catchError((Object _) {});
    });
  }

  // Tell the page which creatures are being heard right now, so they glow.
  void _pushLive() {
    final list = app.engine.liveSpecies.toList()..sort();
    final js = jsonEncode(list);
    if (js == _livePushed) return;
    _livePushed = js;
    _web
        .runJavaScript('window.birdsongLive&&window.birdsongLive($js)')
        .catchError((Object _) {});
  }

  Future<void> _toggleListening() async {
    final engine = app.engine;
    if (engine.running) {
      await engine.stop();
      return;
    }
    await engine.start();
    if (!mounted || engine.error == null) return;
    final noModel = engine.error!.contains('Models');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(engine.error!),
      action: noModel
          ? SnackBarAction(label: 'Models', onPressed: () => widget.openTab(2))
          : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_s, app.store, app.engine]),
      builder: (context, _) {
        final listen = _s.mode == AppMode.listen;
        return Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _web),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: IconButton.filledTonal(
                      tooltip: 'Reload the plate',
                      icon: const Icon(Icons.refresh),
                      onPressed: () => _web.reload(),
                    ),
                  ),
                  if (listen)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: _MicButton(
                        listening: app.engine.running,
                        busy: app.engine.starting,
                        onPressed: _toggleListening,
                      ),
                    ),
                ],
              ),
            ),
            if (listen) _SessionBar(app: app),
          ],
        );
      },
    );
  }
}

/// ‹ date and time, species, place ›
class _SessionBar extends StatelessWidget {
  const _SessionBar({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = app.store;
    final ses = store.selected;
    final i = store.selectedIndex;
    final n = store.sessions.length;

    String title;
    String detail;
    if (ses == null) {
      title = 'Nothing recorded yet';
      detail = 'Tap the microphone to start listening.';
    } else {
      final heard = store.forPlate(app.settings.plateModel, session: ses);
      final species = heard.map((d) => d.sci).toSet().length;
      final end = ses.end ?? DateTime.now();
      title = ses.live ? 'Listening now, since ${clock(ses.start)}' : span(ses.start, end);
      final where = ses.hasPlace
          ? place(ses.lat!, ses.lon!)
          : ses.live
              ? (app.engine.locationNote ?? 'Finding the location…')
              : 'No location';
      detail = '${species == 0 ? 'Nothing heard' : species == 1 ? '1 species' : '$species species'}'
          ' · $where';
    }

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Earlier session',
              icon: const Icon(Icons.chevron_left),
              onPressed: i > 0 ? () => store.step(-1) : null,
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: theme.textTheme.titleSmall,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                      n > 1 ? '$detail · ${i + 1} of $n' : detail,
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Later session',
              icon: const Icon(Icons.chevron_right),
              onPressed: i >= 0 && i < n - 1 ? () => store.step(1) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Round microphone button; while listening it turns to a stop button with
/// a slow pulse around it.
class _MicButton extends StatefulWidget {
  const _MicButton({required this.listening, required this.busy, required this.onPressed});

  final bool listening;
  final bool busy;
  final VoidCallback onPressed;

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.listening) _pulse.repeat();
  }

  @override
  void didUpdateWidget(_MicButton old) {
    super.didUpdateWidget(old);
    if (widget.listening && !_pulse.isAnimating) _pulse.repeat();
    if (!widget.listening && _pulse.isAnimating) _pulse.reset();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final red = Theme.of(context).colorScheme.primary;
    const size = 64.0;
    return SizedBox(
      width: size + 28,
      height: size + 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.listening)
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => Container(
                width: size + 28 * _pulse.value,
                height: size + 28 * _pulse.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: red.withValues(alpha: 0.35 * (1 - _pulse.value)),
                ),
              ),
            ),
          Semantics(
            button: true,
            label: widget.listening ? 'Stop listening' : 'Start listening',
            child: Material(
              color: red,
              shape: const CircleBorder(),
              elevation: 3,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.busy ? null : widget.onPressed,
                child: SizedBox(
                  width: size,
                  height: size,
                  child: widget.busy
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : Icon(widget.listening ? Icons.stop_rounded : Icons.mic,
                          color: Colors.white, size: 32),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
