import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:plate_share/plate_share.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_state.dart';
import '../engine/listen_engine.dart' show maxSessionSpecies;
import '../main.dart' show ink, paper, rule, sepia, serif;
import '../server/page_control.dart';
import '../settings.dart';
import 'format.dart';
import 'station_editor.dart';

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
  String _mapPushed = '';

  /// One of the page's own pop-ups (a creature's card, its dialog) is open:
  /// the app's buttons and arrows step aside.
  bool _popup = false;
  Timer? _popupBack;

  /// Where the page's "Index of species" line is, top to bottom, in logical
  /// pixels: the arrows sit on it, clear of the birds and the names.
  double? _plateMid;

  final _shareKey = GlobalKey();

  /// The page is showing the session arrows beside "Index of species"; the
  /// app's own pair is only for modes without that line.
  bool _arrowsInPage = false;

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
  Uri get _url {
    final mode = plateModes[_s.plateMode - 1];
    final q = <String>[
      if (_s.mode == AppMode.listen) ...['period=all', 'bs=listen'],
      // Listen here steps through sessions, not periods; mode b drops the index too.
      if (_s.mode == AppMode.listen || mode.query.startsWith('hide='))
        'hide=${[if (_s.mode == AppMode.listen) 'periods', if (mode.query == 'hide=index') 'index'].join(',')}',
      if (mode.query.isNotEmpty && !mode.query.startsWith('hide=')) mode.query,
    ];
    return Uri.parse('${app.server.origin}/${q.isEmpty ? '' : '?${q.join('&')}'}');
  }

  // The page as last asked for; a mode that keeps the same address (a, f, g)
  // changes the page in place instead of reloading it.
  String _loaded = '';

  void _load() {
    final u = _url;
    _loaded = u.toString();
    _web.loadRequest(u);
  }

  @override
  void initState() {
    super.initState();
    _mode = _s.mode;
    _plateModel = _s.plateModel;
    _station = '${_s.birdnetBase}|${_s.stationDigits}';
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('BirdsongHost', onMessageReceived: (m) {
        if (m.message == 'step:-1' || m.message == 'step:1') {
          app.store.step(m.message == 'step:1' ? 1 : -1);
          return;
        }
        if (m.message == 'arrows:page' || m.message == 'arrows:app') {
          final inPage = m.message == 'arrows:page';
          if (inPage != _arrowsInPage && mounted) setState(() => _arrowsInPage = inPage);
          return;
        }
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
        _mapPushed = '';
        _pushLive();
        _pushSession();
        final mode = plateModes[_s.plateMode - 1];
        if (mode.sizeBy != null) app.page?.set('sizeBy', mode.sizeBy!);
        _pushMap();
        widget.onLoaded?.call();
      }));
    _load();
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
    _pushMap();
    final station = '${_s.birdnetBase}|${_s.stationDigits}';
    if (_s.mode != _mode || _s.plateModel != _plateModel || station != _station) {
      _mode = _s.mode;
      _plateModel = _s.plateModel;
      _station = station;
      _load();
    } else if (_url.toString() != _loaded) {
      _load();
    }
  }

  // A new detection, or another session picked: ask the page to fetch again.
  // Coalesced, since a burst of detections arrives within one window.
  void _storeChanged() {
    _pushSession();
    _refreshSoon ??= Timer(const Duration(milliseconds: 500), () {
      _refreshSoon = null;
      _web
          .runJavaScript('typeof refresh==="function"&&refresh(false);'
              'window.birdsongMapRefresh&&window.birdsongMapRefresh()')
          .catchError((Object _) {});
    });
  }

  // Map or collage, and the map's options (assets/app/map-mode.js). The map
  // is a Listen here view (a station has no walks) and takes the collage's
  // place, so it has no room in views d and e, which show one bird alone.
  bool get _mapAllowed =>
      _s.mode == AppMode.listen && !plateModes[_s.plateMode - 1].currentOnly;
  bool get _mapOn => _mapAllowed && _s.showMap;

  void _pushMap() {
    final opts = jsonEncode({'birds': _s.mapBirds, 'extras': _s.mapExtras});
    final js = 'window.birdsongMapOptions&&window.birdsongMapOptions($opts);'
        'window.birdsongMap&&window.birdsongMap($_mapOn)';
    if (js == _mapPushed) return;
    _mapPushed = js;
    _web.runJavaScript(js).catchError((Object _) {});
  }

  void _toggleMap() {
    final on = !_s.showMap;
    _s.update((x) => x.showMap = on);
    _say(on ? 'The walk, on a map.' : 'The plate.', seconds: 2);
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
    final i = store.selectedIndex;
    final steps = '${n > 1 && i > 0},${n > 1 && i >= 0 && i < n - 1}';
    if ('$js|$steps' == _sessionPushed) return;
    _sessionPushed = '$js|$steps';
    _web
        .runJavaScript('window.birdsongSession&&window.birdsongSession($js);'
            'window.birdsongSteps&&window.birdsongSteps($steps)')
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

  // The plate's modes, a to g, a tap each: the noisiest collage, the collage
  // alone, the index alone, the latest bird, the most heard, then the two
  // other ways of sizing the collage.
  Future<void> _nextMode() async {
    final next = _s.plateMode % plateModes.length + 1;
    final mode = plateModes[next - 1];
    _s.update((x) => x.plateMode = next);   // b to e reload the page with their view
    if (mode.sizeBy != null) await app.page?.set('sizeBy', mode.sizeBy!);
    if (!mounted) return;
    _say(mode.name, seconds: 2);
  }

  // ---- the source pill, the record button and the stations button --------

  // The pill's microphone half: show Listen here.
  void _toListen() {
    if (_s.mode == AppMode.listen) return;
    _s.update((x) => x.mode = AppMode.listen);
    _say('Listen here & now', seconds: 2);
  }

  // The pill's sensors half: show the remote station last shown. With none
  // saved yet, it asks for one.
  void _toRemote() {
    if (_s.stations.isEmpty) {
      editStation(context, _s);
      return;
    }
    if (_s.mode == AppMode.station) return;
    _s.update((x) {
      x.mode = AppMode.station;
      x.stationId = x.station!.id;
    });
    _say(_s.station!.name, seconds: 2);
  }

  // The record button, under the microphone: a tap starts a new session, a
  // tap while recording stops it. A session started from a station's plate
  // starts before the plate moves to Listen here, so it opens on the new
  // session rather than drawing the last one first.
  Future<void> _record() async {
    if (app.engine.starting) return;
    if (!app.engine.running) HapticFeedback.mediumImpact();
    await _toggleListening();
    if (mounted && app.engine.running && _s.mode != AppMode.listen) {
      _s.update((x) => x.mode = AppMode.listen);
    }
  }

  // The stations button, under the sensors: with two saved stations a tap
  // goes to the other; otherwise it lists them, with Add a station.
  Future<void> _stationsTap(BuildContext context) async {
    if (_s.stations.length == 2) {
      _s.nextStation();
      _say(_s.station!.name, seconds: 2);
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final at = RelativeRect.fromRect(
        box.localToGlobal(Offset(0, box.size.height), ancestor: overlay) & box.size,
        Offset.zero & overlay.size);
    final current = _s.mode == AppMode.station ? _s.station?.id : null;
    final picked = await showMenu<String>(
      context: context,
      position: at,
      color: paper,
      items: [
        for (final st in _s.stations)
          PopupMenuItem(
            value: st.id,
            child: ListTile(
              dense: true,
              leading: Icon(st.id == current ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: Theme.of(context).colorScheme.primary),
              title: Text(st.name),
              subtitle: Text(st.kind),
            ),
          ),
        const PopupMenuItem(
          value: '+',
          child: ListTile(dense: true, leading: Icon(Icons.add), title: Text('Add a station')),
        ),
      ],
    );
    if (picked == null || !mounted) return;
    if (picked == '+') {
      if (context.mounted) await editStation(context, _s);
      return;
    }
    _s.update((x) {
      x.mode = AppMode.station;
      x.stationId = picked;
    });
    _say(_s.station!.name, seconds: 2);
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
            // No reload button: a station plate asks again every minute on
            // its own (CONFIG.refreshSeconds), and Listen here as birds are heard.
            if (!_popup)
              Positioned(
                right: 8 + safe.right,
                top: 8 + safe.top,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left of the pill: the record button (Listen here, or
                    // while a session is recording) and, on a remote
                    // station, the stations button.
                    if (listen || app.engine.running || app.engine.starting)
                      _RecordButton(
                        recording: app.engine.running,
                        busy: app.engine.starting,
                        onTap: _record,
                      ),
                    if (!listen && _s.stations.isNotEmpty)
                      Builder(
                        builder: (bc) => IconButton(
                          tooltip: _s.stations.length == 2 ? 'Next: ${_s.nextStationName}' : 'Stations',
                          icon: Icon(_s.stations.length == 2 ? Icons.swap_horiz : Icons.list),
                          color: Theme.of(context).colorScheme.primary,
                          onPressed: () => _stationsTap(bc),
                        ),
                      ),
                    // The source: a two-part pill, Listen here | remote
                    // station, the one shown filled.
                    Padding(
                      padding: const EdgeInsets.only(top: 5), // level with the round buttons
                      child: _SourcePill(
                        listen: listen,
                        stationName: _s.station?.name,
                        onListen: _toListen,
                        onRemote: _toRemote,
                      ),
                    ),
                    // The menu, and the plate's view (a to g) under it.
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Settings',
                          icon: const Icon(Icons.menu),
                          color: Theme.of(context).colorScheme.primary,
                          onPressed: widget.openSettings,
                        ),
                        IconButton(
                          tooltip: 'Plate: ${plateModes[_s.plateMode - 1].name}',
                          icon: const Icon(Icons.dashboard_outlined),
                          color: Theme.of(context).colorScheme.primary,
                          onPressed: _nextMode,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            // The walk on a map in place of the collage (Listen here), at the
            // bottom left.
            if (_mapAllowed && !_popup)
              Positioned(
                left: 8 + safe.left,
                bottom: 8 + safe.bottom,
                child: IconButton(
                  tooltip: _mapOn ? 'Back to the plate' : 'The walk on a map',
                  icon: Icon(_mapOn ? Icons.auto_awesome_mosaic_outlined : Icons.map_outlined),
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: _toggleMap,
                ),
              ),
            // Share or save, out of the way at the bottom right.
            if (PlateShare.supported && !_popup)
              Positioned(
                right: 8 + safe.right,
                bottom: 8 + safe.bottom,
                child: PopupMenuButton<String>(
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
              ),
            if (_note != null)
              Positioned(
                left: 16 + safe.left,
                right: 16 + safe.right,
                top: 112 + safe.top,
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
            if (listen && !_popup && n > 1 && !_arrowsInPage &&
                !plateModes[_s.plateMode - 1].currentOnly && _arrowsShown(context)) ...[
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

/// The source, as a two-part pill: Listen here (microphone) | a remote
/// station (sensors). The one on show is filled in madder; a tap on the
/// other switches to it.
class _SourcePill extends StatelessWidget {
  const _SourcePill({
    required this.listen,
    required this.stationName,
    required this.onListen,
    required this.onRemote,
  });

  /// Each half's width.
  static const half = 46.0;

  final bool listen;
  final String? stationName;
  final VoidCallback onListen;
  final VoidCallback onRemote;

  @override
  Widget build(BuildContext context) {
    final red = Theme.of(context).colorScheme.primary;
    Widget part(bool on, IconData icon, String tip, VoidCallback tap, BorderRadius r) => Tooltip(
          message: tip,
          child: Semantics(
            button: true,
            selected: on,
            label: tip,
            child: InkWell(
              borderRadius: r,
              onTap: tap,
              child: Container(
                width: half,
                height: 36,
                decoration: BoxDecoration(color: on ? red : Colors.transparent, borderRadius: r),
                child: Icon(icon, size: 21, color: on ? paper : sepia.withValues(alpha: 0.7)),
              ),
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: paper.withValues(alpha: 0.85),
        border: Border.all(color: red.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(19),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          part(listen, Icons.mic_none_outlined, 'Listen here & now', onListen,
              const BorderRadius.horizontal(left: Radius.circular(18))),
          part(!listen, Icons.sensors,
              stationName == null ? 'Add a remote station' : 'Remote station: $stationName',
              onRemote, const BorderRadius.horizontal(right: Radius.circular(18))),
        ],
      ),
    );
  }
}

/// Record a new session, or stop the one recording: a madder dot when idle,
/// a stop square with a slow pulse around it while recording, a spinner
/// while it starts.
class _RecordButton extends StatefulWidget {
  const _RecordButton({required this.recording, required this.busy, required this.onTap});

  final bool recording;
  final bool busy;
  final VoidCallback onTap;

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.recording) _pulse.repeat();
  }

  @override
  void didUpdateWidget(_RecordButton old) {
    super.didUpdateWidget(old);
    if (widget.recording && !_pulse.isAnimating) _pulse.repeat();
    if (!widget.recording && _pulse.isAnimating) _pulse.reset();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final red = Theme.of(context).colorScheme.primary;
    const size = 36.0;
    return SizedBox(
      width: size + 8,
      height: size + 8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.recording)
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => Container(
                width: size * 0.7 + 14 * _pulse.value,
                height: size * 0.7 + 14 * _pulse.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: red.withValues(alpha: 0.25 * (1 - _pulse.value)),
                ),
              ),
            ),
          widget.busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: red),
                )
              : IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: widget.recording ? 'Stop recording' : 'Record a new session',
                  icon: Icon(widget.recording ? Icons.stop_rounded : Icons.fiber_manual_record,
                      size: widget.recording ? 24 : 18),
                  color: red,
                  onPressed: widget.onTap,
                ),
        ],
      ),
    );
  }
}
