import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:plate_share/plate_share.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_state.dart';
import '../engine/listen_engine.dart' show maxSessionSpecies;
import '../main.dart' show ink, paper, rule, sepia, serif;
import '../server/page_control.dart';
import '../settings.dart';
import 'format.dart';

/// Birdsong's own page, served by the app's local server. In Listen here it
/// shows one listening session at a time: small arrows either side step
/// through them, the page's date line says when and where, and a small
/// microphone button at the top right starts a new one.
class PlateView extends StatefulWidget {
  const PlateView({super.key, required this.app, required this.openSettings, this.onLoaded});

  final AppState app;

  /// Open Settings (sources, listening, models, data).
  final VoidCallback openSettings;

  final VoidCallback? onLoaded;

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
  String _sessionPushed = '';

  /// One of the page's own pop-ups (a creature's card, its dialog) is open:
  /// the app's buttons and arrows step aside.
  bool _popup = false;
  Timer? _popupBack;

  /// Where the page's "Index of species" line is, top to bottom, in logical
  /// pixels: the arrows sit on it, clear of the birds and the names.
  double? _plateMid;

  final _shareKey = GlobalKey();

  // ---- notes at the top of the plate ---------------------------------------
  // The app's short messages (a session started or ended, the size order
  // chosen, a photo saved), under the buttons rather than at the bottom.
  String? _note;
  String? _noteAction;
  VoidCallback? _noteDo;
  bool _noteShown = false;
  Timer? _noteTimer;

  void _say(String text, {String? action, VoidCallback? onAction, int seconds = 3}) {
    if (!mounted) return;
    _noteTimer?.cancel();
    setState(() {
      _note = text;
      _noteAction = action;
      _noteDo = onAction;
      _noteShown = true;
    });
    _noteTimer = Timer(Duration(seconds: seconds), () {
      if (mounted) setState(() => _noteShown = false);
    });
  }

  // Session started, ended, or full and carried on in a new one.
  int? _sesId;
  void _watchSession() {
    final now = app.engine.session?.id;
    if (now == _sesId) return;
    final before = _sesId;
    _sesId = now;
    final store = app.store;
    String number(int id) {
      final i = store.sessions.indexWhere((x) => x.id == id);
      return i < 0 ? '' : ' #${i + 1}';
    }

    if (before == null && now != null) {
      _say('Listening: session${number(now)} started.');
    } else if (before != null && now != null) {
      _say('Session${number(before)} is full at $maxSessionSpecies species; '
          'session${number(now)} started.', seconds: 5);
    } else if (before != null) {
      // The store closes (or drops) the session just after the engine stops.
      Future.delayed(const Duration(milliseconds: 400), () {
        final found = store.sessions.where((x) => x.id == before);
        if (found.isEmpty) {
          _say('Stopped. Nothing was heard, so no session was kept.');
          return;
        }
        final ses = found.first;
        final species = {
          for (final d in store.forPlate(_s.plateModel, session: ses)) d.sci
        }.length;
        _say('Session${number(before)} ended: '
            '${lasting((ses.end ?? DateTime.now()).difference(ses.start))}, '
            '$species species.', seconds: 4);
      });
    }
  }

  // The screen's safe-area insets, as last given to the page.
  EdgeInsets _insets = EdgeInsets.zero;
  String _insetsPushed = '';

  void _pushInsets() {
    final p = _insets;
    final key = '${p.top},${p.right},${p.bottom},${p.left}';
    if (key == _insetsPushed) return;
    _insetsPushed = key;
    String px(double v) => '${v.toStringAsFixed(1)}px';
    _web
        .runJavaScript('(function(s){s.setProperty("--bs-top","${px(p.top)}");'
            's.setProperty("--bs-right","${px(p.right)}");s.setProperty("--bs-bottom","${px(p.bottom)}");'
            's.setProperty("--bs-left","${px(p.left)}");dispatchEvent(new Event("resize"));})'
            '(document.documentElement.style)')
        .catchError((Object _) {});
  }

  AppState get app => widget.app;
  Settings get _s => app.settings;

  // Listen here: the page's period buttons give way to sessions, and
  // period=all lets the session decide what is drawn.
  Uri get _url => Uri.parse(_s.mode == AppMode.listen
      ? '${app.server.origin}/?period=all&hide=periods&bs=listen'
      : '${app.server.origin}/');

  @override
  void initState() {
    super.initState();
    _mode = _s.mode;
    _plateModel = _s.plateModel;
    _station = '${_s.birdnetBase}|${_s.stationDigits}';
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('BirdsongHost', onMessageReceived: (m) {
        if (m.message.startsWith('plate:')) {
          final mid = double.tryParse(m.message.substring(6));
          if (mid != _plateMid && mounted) setState(() => _plateMid = mid);
          return;
        }
        _popupBack?.cancel();
        if (m.message == 'popup-open') {
          if (!_popup && mounted) setState(() => _popup = true);
        } else if (_popup) {
          // Back a moment later: the page's Close sits where the menu button
          // is, and the same click mustn't land on it too.
          _popupBack = Timer(const Duration(milliseconds: 400), () {
            if (mounted) setState(() => _popup = false);
          });
        }
      })
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) {
        if (_popup) setState(() => _popup = false);
        _insetsPushed = '';
        _pushInsets();
        _livePushed = '';
        _sessionPushed = '';
        _pushLive();
        _pushSession();
        widget.onLoaded?.call();
      }))
      ..loadRequest(_url);
    app.page = PageControl(_web);
    // iOS: stop WebKit adding its own safe-area insets, so the page fills
    // the screen and pads itself.
    PlateShare.fullBleed().catchError((Object _) {});
    _s.addListener(_settingsChanged);
    app.store.addListener(_storeChanged);
    app.engine.addListener(_pushLive);
    app.engine.addListener(_pushSession);
    _sesId = app.engine.session?.id;
    app.engine.addListener(_watchSession);
  }

  @override
  void dispose() {
    app.page = null;
    _popupBack?.cancel();
    _refreshSoon?.cancel();
    _s.removeListener(_settingsChanged);
    app.store.removeListener(_storeChanged);
    app.engine.removeListener(_pushLive);
    app.engine.removeListener(_pushSession);
    app.engine.removeListener(_watchSession);
    _noteTimer?.cancel();
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
    _pushSession();
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

  // The session's date, time and place, for the page's date line.
  String _sessionText() {
    final store = app.store;
    final ses = store.selected;
    if (ses == null) return 'Nothing recorded yet: tap the microphone to start.';
    final when = ses.live
        ? 'Listening now, since ${clock(ses.start)}'
        : span(ses.start, ses.end ?? ses.start);
    return '$when.';
  }

  // Where, on a line of its own under the date.
  String _placeText() {
    final ses = app.store.selected;
    if (ses == null) return '';
    final w = weatherWords(ses.weather);
    if (ses.hasPlace) return 'At ${place(ses.lat!, ses.lon!)}${w.isEmpty ? '' : ', $w'}.';
    return ses.live ? '' : 'Place unknown.';
  }

  void _pushSession() {
    if (_s.mode != AppMode.listen) return;
    final store = app.store;
    final n = store.sessions.length;
    // Which session, after the title: Birdsong #2/3.
    final count = n > 0 && store.selectedIndex >= 0 ? '#${store.selectedIndex + 1}/$n' : '';
    final js = '${jsonEncode(_sessionText())},${jsonEncode(count)},${jsonEncode(_placeText())}';
    if (js == _sessionPushed) return;
    _sessionPushed = js;
    _web
        .runJavaScript('window.birdsongSession&&window.birdsongSession($js)')
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
    _say(engine.error!,
        action: noModel ? 'Models' : null,
        onAction: noModel ? widget.openSettings : null,
        seconds: 6);
  }

  // The arrows' own height is 40 (compact).
  double _arrowTop(BuildContext context) =>
      (_plateMid ?? MediaQuery.sizeOf(context).height / 2) - 20;

  // Hidden while that line is scrolled out of view.
  bool _arrowsShown(BuildContext context) {
    final mid = _plateMid;
    return mid == null || (mid > 24 && mid < MediaQuery.sizeOf(context).height - 24);
  }

  // Noisiest species, then recent ramblings, then no pecking order, round
  // again: the plate's Size by, a tap away.
  Future<void> _cycleSize() async {
    final page = app.page;
    if (page == null) return;
    final now = (await page.read())?['sizeBy'];
    const order = ['calls', 'time', 'equal'];
    final next = order[(order.indexOf(now is String ? now : 'calls') + 1) % order.length];
    await page.set('sizeBy', next);
    if (!mounted) return;
    _say(PageControl.sizeBy[next]!, seconds: 2);
  }

  Future<void> _share() async {
    final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
    final from = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    var ok = false;
    try {
      ok = await PlateShare.share(text: 'Heard with Birdsong', from: from);
    } catch (_) {}
    if (!ok && mounted) {
      _say("Couldn't take a picture of the plate.");
    }
  }

  Future<void> _save() async {
    var r = 'failed';
    try {
      r = await PlateShare.saveToPhotos();
    } catch (_) {}
    if (!mounted) return;
    _say(switch (r) {
      'saved' => 'Saved to Photos.',
      'denied' => 'Birdsong may not add to Photos: allow it in Settings.',
      _ => "Couldn't save the plate.",
    });
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    if (safe != _insets) {
      _insets = safe;
      WidgetsBinding.instance.addPostFrameCallback((_) => _pushInsets());
    }
    return ListenableBuilder(
      listenable: Listenable.merge([_s, app.store, app.engine]),
      builder: (context, _) {
        final listen = _s.mode == AppMode.listen;
        final store = app.store;
        final i = store.selectedIndex;
        final n = store.sessions.length;
        return Stack(
          children: [
            WebViewWidget(controller: _web),
            // A station plate keeps a reload button; Listen here refreshes
            // itself as birds are heard.
            if (!listen && !_popup)
              Positioned(
                right: 16 + safe.right,
                bottom: 16 + safe.bottom,
                child: IconButton.filledTonal(
                  tooltip: 'Reload the plate',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _web.reload(),
                ),
              ),
            if (!_popup)
              Positioned(
                right: 8 + safe.right,
                top: 8 + safe.top,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (listen)
                      _MicButton(
                        listening: app.engine.running,
                        busy: app.engine.starting,
                        onPressed: _toggleListening,
                      ),
                    IconButton(
                      tooltip: 'Size the birds by…',
                      icon: const Icon(Icons.autorenew),
                      color: Theme.of(context).colorScheme.primary,
                      onPressed: _cycleSize,
                    ),
                    if (PlateShare.supported)
                      PopupMenuButton<String>(
                        key: _shareKey,
                        tooltip: 'Share or save the plate',
                        icon: Icon(Icons.ios_share,
                            color: Theme.of(context).colorScheme.primary),
                        color: paper,
                        onSelected: (v) => v == 'save' ? _save() : _share(),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'share',
                            child: ListTile(
                                leading: Icon(Icons.ios_share), title: Text('Share…')),
                          ),
                          PopupMenuItem(
                            value: 'save',
                            child: ListTile(
                                leading: Icon(Icons.photo_library_outlined),
                                title: Text('Save to Photos')),
                          ),
                        ],
                      ),
                    IconButton(
                      tooltip: 'Settings',
                      icon: const Icon(Icons.menu),
                      color: Theme.of(context).colorScheme.primary,
                      onPressed: widget.openSettings,
                    ),
                  ],
                ),
              ),
            if (_note != null)
              Positioned(
                left: 16 + safe.left,
                right: 16 + safe.right,
                top: 64 + safe.top,
                child: IgnorePointer(
                  ignoring: !_noteShown,
                  child: AnimatedOpacity(
                    opacity: _noteShown && !_popup ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Center(
                      child: _Note(
                        text: _note!,
                        action: _noteAction,
                        onAction: _noteDo == null
                            ? null
                            : () {
                                setState(() => _noteShown = false);
                                _noteDo!();
                              },
                      ),
                    ),
                  ),
                ),
              ),
            if (listen && !_popup && n > 1 && _arrowsShown(context)) ...[
              Positioned(
                left: safe.left,
                top: _arrowTop(context),
                child: _Arrow(
                  icon: Icons.chevron_left,
                  tooltip: 'Earlier session',
                  onPressed: i > 0 ? () => store.step(-1) : null,
                ),
              ),
              Positioned(
                right: safe.right,
                top: _arrowTop(context),
                child: _Arrow(
                  icon: Icons.chevron_right,
                  tooltip: 'Later session',
                  onPressed: i >= 0 && i < n - 1 ? () => store.step(1) : null,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A small arrow at the edge of the plate; hidden at the first or last session.
class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (onPressed == null) return const SizedBox.shrink();
    // Small and quiet, in the sepia of the index line they sit on.
    return IconButton(
      tooltip: tooltip,
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      color: sepia.withValues(alpha: 0.75),
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}

/// A short message on paper, ruled like the plate's pop-ups.
class _Note extends StatelessWidget {
  const _Note({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: paper,
      elevation: 3,
      shadowColor: const Color(0x553C280A),
      shape: const RoundedRectangleBorder(side: BorderSide(color: rule)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, action == null ? 16 : 6, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(text,
                  style: const TextStyle(
                      fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 16, color: ink)),
            ),
            if (action != null)
              TextButton(onPressed: onAction, child: Text(action!)),
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
    const size = 40.0;
    return SizedBox(
      width: size + 16,
      height: size + 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.listening)
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => Container(
                width: size + 16 * _pulse.value,
                height: size + 16 * _pulse.value,
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
              elevation: 1,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.busy ? null : widget.onPressed,
                child: SizedBox(
                  width: size,
                  height: size,
                  child: widget.busy
                      ? const Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(widget.listening ? Icons.mic_off : Icons.mic,
                          color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
