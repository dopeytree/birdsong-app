import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:plate_share/plate_share.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../engine/listen_engine.dart';
import '../engine/model_catalog.dart';
import '../main.dart' show caps, ink, madder, paper, paperDeep, rule, sepia, serif;
import '../server/page_control.dart';
import '../settings.dart';
import '../store/detection_store.dart';
import 'format.dart';
import 'splash.dart' show Cardinal, SupportQuote;
import 'station_editor.dart';
import 'station_history.dart';

enum _SettingsTab {
  display('Display', Icons.palette_outlined),
  map('Map', Icons.map_outlined),
  stations('Stations', Icons.sensors),
  listening('Listening', Icons.mic_none_outlined),
  models('Models', Icons.psychology_outlined),
  location('Location', Icons.location_on_outlined),
  data('Data', Icons.storage_outlined),
  about('About', Icons.info_outline);

  const _SettingsTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Everything that isn't the plate: where birds come from, listening,
/// models, the location filter and stored data. Opened from the plate's
/// menu button.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.app,
    this.onGoHome,
    this.onOpenMap,
    this.onOpenCalendar,
    this.onOpenBestSession,
  });

  final AppState app;
  final VoidCallback? onGoHome;
  final VoidCallback? onOpenMap;
  final VoidCallback? onOpenCalendar;
  final VoidCallback? onOpenBestSession;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _lat;
  late final TextEditingController _lon;
  final _limit = TextEditingController();
  final _ignoreAdd = TextEditingController();
  late _SettingsTab _tab = widget.app.engine.running ? _SettingsTab.listening : _SettingsTab.display;
  bool _converting = false;
  String? _convertNote;

  /// The page's version, from assets/web/UPSTREAM.json (tool/sync_web.py).
  late final Future<String?> _webVersion = rootBundle
      .loadString('assets/web/UPSTREAM.json')
      .then((t) => (jsonDecode(t) as Map)['version'] as String?)
      .catchError((Object _) => null);

  /// The plate's Display options as the page has them; null until read.
  Map<String, Object?>? _display;

  AppState get app => widget.app;
  Settings get s => app.settings;

  @override
  void initState() {
    super.initState();
    _lat = TextEditingController(text: s.latitude?.toString() ?? '');
    _lon = TextEditingController(text: s.longitude?.toString() ?? '');
    app.page?.read().then((d) {
      if (!mounted || d == null) return;
      final n = (d['limit'] as num?)?.toInt() ?? 0;
      _limit.text = n > 0 ? '$n' : '';
      setState(() => _display = d);
    });
  }

  @override
  void dispose() {
    _lat.dispose();
    _lon.dispose();
    _limit.dispose();
    _ignoreAdd.dispose();
    super.dispose();
  }

  void _addIgnored() {
    final term = _ignoreAdd.text.trim();
    if (term.isEmpty) return;
    final exists = s.ignoredSpecies.any((x) => x.toLowerCase() == term.toLowerCase());
    if (!exists) {
      s.update((x) => x.ignoredSpecies = [...x.ignoredSpecies, term]);
    }
    _ignoreAdd.clear();
  }

  void _saveLocation() => s.update((x) {
        x.latitude = double.tryParse(_lat.text.trim());
        x.longitude = double.tryParse(_lon.text.trim());
      });

  /// Finds the local session with the highest distinct (non-ignored) species count.
  ({Session session, int species})? _bestLocalSession() {
    final model = s.plateModel;
    Session? best;
    var bestCount = 0;
    for (final ses in app.store.sessions) {
      final count = {
        for (final d in app.store.forPlate(model, session: ses))
          if (!s.isIgnoredSpecies(d.common, d.sci)) d.sci
      }.length;
      if (count > bestCount || (count == bestCount && count > 0 && best != null && ses.start.isAfter(best.start))) {
        best = ses;
        bestCount = count;
      }
    }
    return best == null ? null : (session: best, species: bestCount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'birdsongs.ai',
          style: TextStyle(fontFamily: caps, fontSize: 18, letterSpacing: 1.0, color: ink),
        ),
        actions: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Use the actual panel width (e.g. 420 px inside the desktop sidebar,
          // or full screen on mobile) so sidebar and mobile show the exact same
          // settings without squishing.
          final side = ((constraints.maxWidth - 680) / 2).clamp(16.0, 400.0);
          return ListenableBuilder(
            listenable: Listenable.merge([s, app.engine, app.models, app.store, app.updates, app.icloud]),
            builder: (context, _) {
              final listen = s.mode == AppMode.listen;
              final best = listen ? _bestLocalSession() : null;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _quickLaunchBar(context, side, best),
                  Divider(height: 1, color: rule.withValues(alpha: 0.6)),
                  _iconBar(side),
                  Divider(height: 1, color: rule.withValues(alpha: 0.6)),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(side, 12, side, 32),
                      children: _tabBody(context, listen),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _quickLaunchBar(BuildContext context, double side, ({Session session, int species})? best) {
    Widget tile({
      required IconData icon,
      required String label,
      String? detail,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Material(
          color: paperDeep.withValues(alpha: 0.42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: rule.withValues(alpha: 0.55)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            hoverColor: ink.withValues(alpha: 0.08),
            highlightColor: ink.withValues(alpha: 0.12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: ink),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: caps, fontSize: 11.5, letterSpacing: 0.4, color: ink),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 11, color: sepia),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    final tiles = <Widget>[
      tile(
        icon: Icons.home_outlined,
        label: 'Home',
        onTap: () {
          Navigator.of(context).pop();
          if (widget.onGoHome != null) {
            widget.onGoHome!();
          } else {
            s.update((x) {
              x.plateMode = defaultPlateMode;
              x.nativeSizeBy = x.mode == AppMode.station ? 'calls' : 'time';
            });
          }
        },
      ),
      if (widget.onOpenMap != null)
        tile(
          icon: Icons.map_outlined,
          label: 'Map',
          onTap: () {
            Navigator.of(context).pop();
            widget.onOpenMap!();
          },
        ),
      if (widget.onOpenCalendar != null)
        tile(
          icon: Icons.calendar_today_outlined,
          label: 'Calendar',
          onTap: () {
            Navigator.of(context).pop();
            widget.onOpenCalendar!();
          },
        ),
      if (best != null)
        tile(
          icon: Icons.emoji_events_outlined,
          label: 'Best walk',
          detail: '${best.species} sp.',
          onTap: () {
            Navigator.of(context).pop();
            if (widget.onOpenBestSession != null) {
              widget.onOpenBestSession!();
            } else {
              app.store.select(best.session);
              s.update((x) {
                x.mode = AppMode.listen;
                x.plateMode = defaultPlateMode;
                x.nativeSizeBy = 'time';
              });
            }
          },
        ),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(side, 6, side, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            tiles[i],
          ],
        ],
      ),
    );
  }

  Widget _iconBar(double side) {
    return Container(
      color: paper,
      padding: EdgeInsets.symmetric(horizontal: side - 4, vertical: 6),
      child: Wrap(
        spacing: 2,
        runSpacing: 4,
        alignment: WrapAlignment.spaceBetween,
        children: [
          for (final tab in _SettingsTab.values)
            _iconButton(tab),
        ],
      ),
    );
  }

  Widget _iconButton(_SettingsTab tab) {
    final active = _tab == tab;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      hoverColor: ink.withValues(alpha: 0.08),
      highlightColor: ink.withValues(alpha: 0.12),
      onTap: () => setState(() => _tab = tab),
      child: Container(
        width: 46,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        decoration: active
            ? const BoxDecoration(
                border: Border(bottom: BorderSide(color: ink, width: 2)),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tab.icon, size: 20, color: active ? ink : ink.withValues(alpha: 0.55)),
            const SizedBox(height: 2),
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: caps,
                fontSize: 9.5,
                letterSpacing: 0.2,
                color: active ? ink : sepia,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _tabBody(BuildContext context, bool listen) => switch (_tab) {
        _SettingsTab.display => [
            s.webPlate ? _displaySection(context, listen, open: true) : _flutterDisplaySection(context, open: true),
          ],
        _SettingsTab.map => [
            _mapSection(context, open: true),
          ],
        _SettingsTab.stations => [
            _remote(context),
            if (s.stations.isNotEmpty) ...[
              const Divider(height: 24, color: rule),
              _section(
                context,
                'Station history',
                summary: 'Days kept on this device, and the log',
                open: true,
                [StationHistory(root: app.store.root, stations: s.stations)],
              ),
            ],
          ],
        _SettingsTab.listening => [
            _listening(context, open: true),
          ],
        _SettingsTab.models => [
            _models(context, open: true),
          ],
        _SettingsTab.location => [
            _location(context, open: true),
          ],
        _SettingsTab.data => [
            _data(context, open: true),
          ],
        _SettingsTab.about => [
            _credits(context, listen, open: true),
            const Divider(height: 16, color: rule),
            _support(context, open: true),
            const Divider(height: 16, color: rule),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: app.engine.running
                    ? null
                    : () {
                        s.update((x) => x.onboarded = false);
                        Navigator.of(context).pop();
                      },
                child: const Text('Show the welcome again'),
              ),
            ),
          ],
      };

  // ---- sections -------------------------------------------------------------

  Widget _section(BuildContext context, String title, List<Widget> children,
      {bool open = false, String? summary}) {
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      initiallyExpanded: open,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(title, style: theme.textTheme.titleMedium),
      subtitle: summary == null ? null : Text(summary, style: theme.textTheme.bodySmall),
      children: children,
    );
  }

  /// The saved stations: tap one to show it, edit or remove it, add more.
  Widget _remote(BuildContext context) {
    final theme = Theme.of(context);
    final shown = s.station?.id;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final st in s.stations)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.sensors,
                  color: st.id == shown ? theme.colorScheme.primary : theme.disabledColor),
              title: Text(st.name),
              subtitle: Text(st.isBirdWeather ? st.kind : st.birdnetUrl,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              selected: st.id == shown,
              onTap: () => s.update((x) {
                x.stationId = st.id;
                x.mode = AppMode.station;
                x.plateMode = defaultPlateMode;
              }),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => editStation(context, s, station: st),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmRemove(context, st),
                  ),
                ],
              ),
            ),
          // each station's past days, kept on this device in the session
          // format (a phone asks first, in the calendar)
          for (final st in s.stations)
            _switch('Keep ${st.name}\'s past days on this device', s.keepPastOf(st) ?? false,
                (v) => s.update((x) => x.stationKeepPast[st.id] = v)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => editStation(context, s),
                icon: const Icon(Icons.add),
                label: const Text('Add a station'),
              ),
              TextButton.icon(
                onPressed: openBirdWeatherMap,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Find one on BirdWeather'),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, Station st) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove ${st.name}?'),
        content: const Text('Only the saved address goes; nothing on the station changes.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: madder, foregroundColor: paper),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) s.removeStation(st.id);
  }

  Widget _listening(BuildContext context, {bool open = false}) {
    final theme = Theme.of(context);
    final engine = app.engine;
    final locked = engine.running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (engine.error != null)
          Text(engine.error!, style: TextStyle(color: theme.colorScheme.error)),
        if (engine.running) ...[
          LinearProgressIndicator(
            value: ((engine.levelDb + 70) / 70).clamp(0.0, 1.0).toDouble(),
            minHeight: 6,
          ),
          const SizedBox(height: 8),
          for (final r in engine.reports.values) _report(context, r),
          if (engine.skipped > 0)
            Text('${engine.skipped} windows skipped', style: theme.textTheme.bodySmall),
          const Divider(height: 24),
        ],
        _dropdown('Microphone', s.micSource, microphones, (v) => s.update((x) => x.micSource = v)),
        Text(
          s.micSource == 'headset'
              ? 'Bluetooth headphones send their microphone at call quality, which misses '
                  'the higher songs, and your music drops to call quality while listening. '
                  'A wired headset\'s microphone hears the full range, but rubs on clothes. '
                  'Both work; for the best detections use the phone\'s own.'
              : 'Best for birds: the full range of song, even with headphones plugged in. '
                  'Music and podcasts keep playing, in full quality on Bluetooth headphones.',
          style: theme.textTheme.bodySmall,
        ),
        if (locked)
          Text('A change of microphone applies from the next recording.',
              style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        _slider('Threshold ${(s.threshold * 100).round()}%', s.threshold, 0.05, 0.95, 18,
            (v) => s.update((x) => x.threshold = v)),
        _switch('Animals only', s.animalsOnly, (v) => s.update((x) => x.animalsOnly = v)),
        const Divider(height: 20, color: rule),
        _section(
          context,
          'More listening options',
          summary: 'Format, timing, ignored species and Core ML',
          [
            if (PlateShare.supported) ...[
              _dropdown(
                'Recording format',
                s.clipFormat,
                const {
                  'aac': 'AAC 128 kbps (.m4a, smaller)',
                  'wav': 'WAV (uncompressed)',
                },
                (v) => s.update((x) => x.clipFormat = v),
              ),
              Text(
                'Saved clips include 2 seconds of pre-record before each detection.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
            ],
            _slider('Every ${s.hopSeconds.toStringAsFixed(1)} s', s.hopSeconds, 0.5, 5, 9,
                (v) => s.update((x) => x.hopSeconds = v)),
            _slider('Repeat after ${s.repeatSeconds.round()} s', s.repeatSeconds, 3, 60, 19,
                (v) => s.update((x) => x.repeatSeconds = v)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Ignored species', style: theme.textTheme.titleSmall)),
                if (s.ignoredSpecies.join('\u0000') != Settings.defaultIgnoredSpecies.join('\u0000'))
                  TextButton(
                    onPressed: () => s.update((x) => x.ignoredSpecies = List<String>.of(Settings.defaultIgnoredSpecies)),
                    child: const Text('Reset defaults'),
                  ),
              ],
            ),
            Text(
              'Detections matching these names are ignored while listening and hidden from the plate.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            if (s.ignoredSpecies.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final term in s.ignoredSpecies)
                    InputChip(
                      label: Text(term),
                      visualDensity: VisualDensity.compact,
                      onDeleted: () => s.update((x) => x.ignoredSpecies = [
                            for (final item in x.ignoredSpecies)
                              if (item != term) item,
                          ]),
                    ),
                ],
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ignoreAdd,
                    decoration: const InputDecoration(
                      hintText: 'Add species or sound to ignore',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addIgnored(),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: _addIgnored, child: const Text('Add')),
              ],
            ),
            const SizedBox(height: 8),
            if (Platform.isIOS || Platform.isMacOS)
              _switch('Core ML (GPU / Neural Engine)', s.useCoreMl,
                  locked ? null : (v) => s.update((x) => x.useCoreMl = v)),
          ],
        ),
      ],
    );
  }

  Widget _report(BuildContext context, ModelReport r) {
    final theme = Theme.of(context);
    final top = r.top.take(3).map((e) => '${e.$1} ${(e.$2 * 100).round()}%').join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${r.spec.family} · ${r.millis} ms · ${r.backend}', style: theme.textTheme.bodySmall),
          Text(r.error ?? (top.isEmpty ? '…' : top),
              style: r.error != null ? TextStyle(color: theme.colorScheme.error) : null),
        ],
      ),
    );
  }

  Widget _models(BuildContext context, {bool open = false}) {
    final theme = Theme.of(context);
    final m = app.models;
    final specs = effectiveCatalog(s.modelOverrides);
    final installed = [for (final spec in specs) if (m.isInstalled(spec)) spec];
    final locked = app.engine.running;
    final plateIds = ['all', for (final spec in installed) spec.id];
    return _section(
      context,
      'Models',
      summary: '${s.activeModels.where((id) => installed.any((x) => x.id == id)).length} listening'
          ' · ${installed.length} downloaded',
      open: open || installed.isEmpty,
      [
        if (locked)
          Text('Stop listening to change models.', style: theme.textTheme.bodySmall),
        for (final spec in specs) _modelRow(context, spec),
        const SizedBox(height: 8),
        if (installed.length > 1)
          Row(
            children: [
              const Text('Plate shows'),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: plateIds.contains(s.plateModel) ? s.plateModel : 'all',
                items: [
                  for (final id in plateIds)
                    DropdownMenuItem(
                        value: id,
                        child: Text(id == 'all'
                            ? 'All models'
                            : effectiveById(id, s.modelOverrides)!.family)),
                ],
                onChanged: (v) => s.update((x) => x.plateModel = v ?? 'all'),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: app.updates.checking ? null : () => app.updates.checkIfDue(force: true),
            child: const Text('Check now'),
          ),
        ),
      ],
    );
  }

  /// The catalogue name, with the installed build's version after it.
  String _modelTitle(ModelSpec spec) {
    final label = s.modelOverrides[spec.id]?['label'];
    if (label is! String || label.isEmpty) return spec.name;
    return '${spec.name} · ${label.split(',').first.trim()}';
  }

  Widget _modelRow(BuildContext context, ModelSpec spec) {
    final theme = Theme.of(context);
    final m = app.models;
    final installed = m.isInstalled(spec);
    final downloading = m.isDownloading(spec);
    final locked = app.engine.running;
    final active = s.activeModels.contains(spec.id);
    final offer = app.updates.offerFor(spec.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 48,
              child: !installed
                  ? null
                  : Checkbox(
                value: active,
                onChanged: locked
                    ? null
                    : (v) => s.update((x) {
                          x.activeModels = v == true
                              ? {...x.activeModels, spec.id}
                              : ({...x.activeModels}..remove(spec.id));
                          // A model that listens alone is the one the plate draws.
                          if (x.activeModels.length == 1) x.plateModel = x.activeModels.first;
                        }),
                    ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_modelTitle(spec)),
                  Text(
                      '${megabytes(spec.totalBytes)} · ${spec.licence}'
                      '${spec.releaseOk ? '' : ' · testing only'}',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (downloading)
              const SizedBox(
                  width: 48, child: Center(child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))))
            else if (installed)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: locked ? null : () => m.remove(spec),
              )
            else
              IconButton(
                tooltip: 'Download',
                icon: const Icon(Icons.download),
                onPressed: () => m.install(spec),
              ),
          ],
        ),
        if (downloading)
          Padding(
            padding: const EdgeInsets.only(left: 48, right: 8),
            child: LinearProgressIndicator(value: m.progress[spec.id]),
          ),
        if (m.errors[spec.id] != null)
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Text(m.errors[spec.id]!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        if (offer != null)
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Text(
              'Newer build ready: ${offer.label}',
              style: const TextStyle(
                fontFamily: serif,
                fontStyle: FontStyle.italic,
                fontSize: 14,
                color: sepia,
              ),
            ),
          ),
      ],
      ),
    );
  }

  Widget _location(BuildContext context, {bool open = false}) {
    final m = app.models;
    final locked = app.engine.running;
    final geoReady = m.isInstalled(geomodel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _switch('Drop species unlikely here', s.useGeomodel,
            locked ? null : (v) => s.update((x) => x.useGeomodel = v)),
        _switch('Note the weather (MET Norway)', s.recordWeather,
            (v) => s.update((x) => x.recordWeather = v)),
        if (!geoReady)
          m.isDownloading(geomodel)
              ? LinearProgressIndicator(value: m.progress[geomodel.id])
              : TextButton.icon(
                  onPressed: () => m.install(geomodel),
                  icon: const Icon(Icons.download_outlined),
                  label: Text('Geomodel, ${megabytes(geomodel.totalBytes)}'),
                ),
        const Divider(height: 20, color: rule),
        _section(
          context,
          'More location options',
          summary: 'Manual coordinates and threshold',
          [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _lat,
                    decoration: const InputDecoration(labelText: 'Latitude', hintText: 'GPS'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    onSubmitted: (_) => _saveLocation(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _lon,
                    decoration: const InputDecoration(labelText: 'Longitude', hintText: 'GPS'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    onSubmitted: (_) => _saveLocation(),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: _saveLocation, child: const Text('Save')),
              ],
            ),
            _slider('Above ${(s.geoThreshold * 100).toStringAsFixed(0)}% likely', s.geoThreshold,
                0.01, 0.2, 19, (v) => s.update((x) => x.geoThreshold = v)),
          ],
        ),
      ],
    );
  }

  Future<void> _batchConvert() async {
    if (_converting || !PlateShare.supported) return;
    setState(() {
      _converting = true;
      _convertNote = 'Converting WAV recordings to AAC…';
    });
    final res = await app.store.batchConvertWavToAac(
      (wav, m4a) => PlateShare.encodeAac(wav, m4a, bitrate: 128000),
      onProgress: (done, total) {
        if (!mounted) return;
        setState(() => _convertNote = 'Converting $done of $total…');
      },
    );
    if (!mounted) return;
    setState(() {
      _converting = false;
      if (res.converted == 0 && res.failed == 0) {
        _convertNote = 'No uncompressed WAV recordings found.';
      } else {
        final saved = megabytes(res.savedBytes);
        _convertNote = 'Converted ${res.converted} recordings (saved $saved)'
            '${res.failed > 0 ? ' · ${res.failed} failed' : ''}.';
      }
    });
  }

  Widget _data(BuildContext context, {bool open = false}) {
    final theme = Theme.of(context);
    final store = app.store;
    final icloud = app.icloud;
    return _section(
      context,
      'Data',
      open: open,
      summary: '${store.sessions.length} sessions · ${store.all.length} detections',
      [
        FutureBuilder<int>(
          future: app.engine.clipBytes(),
          builder: (context, snap) =>
              Text('Recordings ${megabytes(snap.data ?? 0)}', style: theme.textTheme.bodySmall),
        ),
        if (PlateShare.supported) ...[
          const SizedBox(height: 12),
          FutureBuilder<int>(
            future: store.wavClipCount(),
            builder: (context, snap) {
              final count = snap.data ?? 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: _converting || app.engine.running || count == 0 ? null : _batchConvert,
                    icon: const Icon(Icons.compress_outlined),
                    label: Text(count > 0
                        ? 'Convert $count WAV recordings to AAC'
                        : 'All recordings compressed'),
                  ),
                  if (_convertNote != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_convertNote!, style: theme.textTheme.bodySmall),
                    ),
                ],
              );
            },
          ),
          const Divider(height: 24, color: rule),
          _switch('iCloud sync', s.icloudSync, (v) {
            s.update((x) => x.icloudSync = v);
            if (v) icloud.syncNow();
          }),
          Text(
            'Syncs listening sessions and recordings via iCloud Drive so walks '
            'recorded on iPhone appear on Mac and iPad.',
            style: theme.textTheme.bodySmall,
          ),
          if (s.icloudSync) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: icloud.syncing ? null : () => icloud.syncNow(),
                  icon: icloud.syncing
                      ? const SizedBox.square(
                          dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_sync_outlined, size: 18),
                  label: Text(icloud.syncing ? 'Syncing…' : 'Sync now'),
                ),
              ],
            ),
            if (icloud.status != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(icloud.status!, style: theme.textTheme.bodySmall),
              ),
            if (icloud.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(icloud.error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
              ),
          ],
        ],
        const Divider(height: 24, color: rule),
        OutlinedButton.icon(
          onPressed: app.engine.running ? null : () => _confirmClear(context),
          icon: const Icon(Icons.delete_sweep_outlined),
          label: const Text('Forget everything heard'),
        ),
      ],
    );
  }

  void _setDisplay(String key, Object value) {
    setState(() => _display = {...?_display, key: value});
    // Size by is also the plate button's modes a, f and g.
    if (key == 'sizeBy') {
      final n = plateModes.indexWhere((m) => m.sizeBy == value) + 1;
      if (n > 0) s.update((x) => x.plateMode = n);
    }
    app.page?.set(key, value);
  }

  /// The Flutter plate's Display options: core everyday controls upfront,
  /// fine-grained tweaks tucked cleanly under "More display options".
  Widget _flutterDisplaySection(BuildContext context, {bool open = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _switch('Fit on one screen', s.nativeFit, (v) => s.update((x) => x.nativeFit = v)),
          _dropdown(
              'Song scribble',
              s.songScribbleMode,
              const {
                'scribble': 'Pencil scribble (default)',
                'wave': 'Simple wave (black, lighter)',
                'off': 'Off',
              },
              (v) => s.update((x) => x.songScribbleMode = v)),
          _switch('Name tickets on all birds', s.nativeAllNameTickets,
              (v) => s.update((x) => x.nativeAllNameTickets = v)),
          _switch('Show bird info on hover', s.nativeHoverInfo, (v) => s.update((x) => x.nativeHoverInfo = v)),
          _dropdown(
              'Limit species',
              '${s.nativeLimit}',
              {
                '0': 'All',
                for (final n in const [5, 10, 15, 20, 30, 40]) '$n': 'The $n most heard',
                if (!const [0, 5, 10, 15, 20, 30, 40].contains(s.nativeLimit))
                  '${s.nativeLimit}': 'The ${s.nativeLimit} most heard',
              },
              (v) => s.update((x) => x.nativeLimit = int.tryParse(v) ?? 0)),
          const Divider(height: 20, color: rule),
          _section(
            context,
            'More display options',
            summary: 'Heading, plates, markers and legacy view',
            [
              _switch('Title', s.nativeShowTitle, (v) => s.update((x) => x.nativeShowTitle = v)),
              _switch('Date', s.nativeShowDate, (v) => s.update((x) => x.nativeShowDate = v)),
              _switch('Species and calls under the date', s.nativeTotals, (v) => s.update((x) => x.nativeTotals = v)),
              _switch('Heading in small capitals', s.nativeTitleCaps, (v) => s.update((x) => x.nativeTitleCaps = v)),
              _dropdown('Heading lines', s.nativeHeadingInk ? 'ink' : 'sepia',
                  const {'ink': 'Black, as the title (default)', 'sepia': 'Sepia'},
                  (v) => s.update((x) => x.nativeHeadingInk = v == 'ink')),
              _dropdown('Latest marked by', s.nativeMarkAt, const {...PageControl.markAt, 'none': 'Nothing'},
                  (v) => s.update((x) => x.nativeMarkAt = v)),
              _dropdown('Size by', s.nativeSizeBy, PageControl.sizeBy, (v) => s.update((x) => x.nativeSizeBy = v)),
              _dropdown(
                  'Plates on paper',
                  s.nativePlateStyle,
                  const {
                    'cutout': 'Cut out, as the web plate does',
                    'tint': 'Tinted into the page',
                    'plain': 'As they come',
                  },
                  (v) => s.update((x) => x.nativePlateStyle = v)),
              _switch('Skulls, wings and eggs', s.nativeParts, (v) => s.update((x) => x.nativeParts = v)),
              _switch('Use the old web plate', s.webPlate, (v) => s.update((x) => x.webPlate = v)),
            ],
          ),
        ],
      );

  /// The web plate's Display options, read from and set through the page.
  Widget _displaySection(BuildContext context, bool listen, {bool open = false}) {
    final d = _display;
    if (d == null) {
      return _section(context, 'Display', open: open, summary: 'Open the plate first', const []);
    }
    bool on(String k) => d[k] == true;
    String pick(String k, Map<String, String> from, String fallback) {
      final v = d[k];
      return v is String && from.containsKey(v) ? v : fallback;
    }

    return _section(
      context,
      'Display',
      open: open,
      summary: PageControl.sizeBy[pick('sizeBy', PageControl.sizeBy, 'calls')],
      [
        _switch('Fit on one screen', on('fit'), (v) => _setDisplay('fit', v)),
        for (final e in PageControl.parts.entries)
          // Listen here steps through sessions instead of periods.
          if (!(listen && e.key == 'periods'))
            _switch(e.value, on(e.key), (v) => _setDisplay(e.key, v)),
        _switch('Mark the latest', on('mark'), (v) => _setDisplay('mark', v)),
        if (on('mark'))
          _dropdown('Marked by', pick('markAt', PageControl.markAt, 'centre'), PageControl.markAt,
              (v) => _setDisplay('markAt', v)),
        _dropdown('Size by', pick('sizeBy', PageControl.sizeBy, 'calls'), PageControl.sizeBy,
            (v) => _setDisplay('sizeBy', v)),
        _switch('Skulls, wings and eggs', on('parts'), (v) => _setDisplay('parts', v)),
        Row(
          children: [
            const SizedBox(width: 130, child: Text('Limit species')),
            Expanded(
              child: TextField(
                controller: _limit,
                decoration: const InputDecoration(hintText: 'all', isDense: true),
                keyboardType: TextInputType.number,
                onSubmitted: (v) => _setDisplay('limit', '${int.tryParse(v.trim()) ?? 0}'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Which microphone listens (Settings.micSource).
  static const microphones = {
    'phone': "The phone's own",
    'headset': "Headphones' or headset's (wired or Bluetooth)",
  };

  /// The map of the walk (the map button on the plate switches to it).
  static const mapBirds = {
    'first': 'Where each was first heard',
    'all': 'Every call',
  };

  Widget _mapSection(BuildContext context, {bool open = false}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _switch('Landmarks, heritage and nature sites', s.mapExtras,
            (v) => s.update((x) => x.mapExtras = v)),
        _dropdown('Bird pins', s.mapBirds, mapBirds, (v) => s.update((x) => x.mapBirds = v)),
        const Divider(height: 20, color: rule),
        _section(
          context,
          'More map options',
          summary: 'Button style, descriptions and privacy',
          [
            _dropdown(
              'Map buttons',
              s.mapButtonStyle,
              const {
                'ink': 'All black icons (default)',
                'paper': 'Paper circle, madder icons',
                'madder': 'Solid madder',
              },
              (v) => s.update((x) => x.mapButtonStyle = v),
            ),
            if (s.mapExtras)
              _switch('Descriptions in Passed on the way', s.mapPassedAbout,
                  (v) => s.update((x) => x.mapPassedAbout = v)),
            if (kDebugMode)
              _switch('Timing readout on the map (debug)', s.mapDebugReadout,
                  (v) => s.update((x) => x.mapDebugReadout = v)),
            const SizedBox(height: 6),
            Text(
              'The map is drawn from OpenFreeMap and open elevation data, so the area of each walk '
              'is sent to them. Landmarks also send it to Historic England, Natural England and '
              'Wikipedia, and list what the walk passed above the map.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }

  Widget _link(String label, String url) => TextButton(
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
        onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: Text(label),
      );

  /// As the page's own Credits.
  Widget _credits(BuildContext context, bool listen, {bool open = false}) {
    final theme = Theme.of(context);
    final detections = listen
        ? 'BirdNET, run on this device (${effectiveById(s.plateModel, s.modelOverrides)?.family ?? 'the chosen model'})'
        : s.stationDigits.isNotEmpty
            ? 'BirdWeather'
            : 'BirdNET-Go';
    return _section(context, 'Credits', open: open, [
      FutureBuilder<String?>(
        future: _webVersion,
        builder: (context, snap) => Text(
          'birdsongs.ai${snap.data == null ? '' : ' v${snap.data}'}. Created by Ed Stone. '
          'Detections by $detections. Bird cut-outs from the Fugleramme project by '
          'Arne Giacomo, after Gould, the von Wright brothers, Audubon and others, used under '
          'CC BY-SA 4.0. Descriptions from Wikipedia, CC BY-SA. Weather from MET Norway, CC BY 4.0. '
          'Maps from OpenFreeMap and OpenStreetMap contributors (ODbL), drawn with MapLibre; '
          'heights from the Mapzen Terrain Tiles. Names of woods and heaths from OS Open Names: '
          'contains OS data \u00a9 Crown copyright and database right 2026 (OGL). Further plates from '
          'Nederlandsche Vogelen (Nozeman & Sepp, Amsterdam, 1770\u20131829), digitised by the '
          'Koninklijke Bibliotheek, with others from public-domain works held on Wikimedia Commons.',
          style: theme.textTheme.bodyMedium,
        ),
      ),
      const SizedBox(height: 4),
      Wrap(
        children: [
          _link('Ed Stone', 'https://ed-stone.co.uk'),
          _link('Fugleramme', 'https://github.com/arnegiacomo/fugleramme'),
          _link('BirdNET', 'https://birdnet.cornell.edu'),
        ],
      ),
    ]);
  }

  /// As the page's own Support.
  Widget _support(BuildContext context, {bool open = false}) {
    final theme = Theme.of(context);
    return _section(context, 'Support', open: open, [
      const Center(child: Cardinal(height: 110)),
      const SizedBox(height: 12),
      const SupportQuote(size: 15),
      const SizedBox(height: 16),
      Text(
        'One hopes you are enjoying birdsongs.ai. If something is amiss, or it does not yet do '
        'what you want of it, say so on GitHub.',
        style: theme.textTheme.bodyMedium,
      ),
      _link('GitHub', 'https://github.com/dopeytree/birdsong/issues'),
    ]);
  }

  Widget _dropdown(String label, String value, Map<String, String> items,
          ValueChanged<String> onChanged) =>
      Row(
        children: [
          SizedBox(width: 120, child: Text(label)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value,
              items: [
                for (final e in items.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => v == null ? null : onChanged(v),
            ),
          ),
        ],
      );

  // ---- bits -----------------------------------------------------------------

  Widget _switch(String label, bool value, ValueChanged<bool>? onChanged) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(label),
        value: value,
        onChanged: onChanged,
      );

  Widget _slider(String label, double value, double min, double max, int divisions,
      ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 130, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Forget everything heard?'),
        content: const Text('Deletes all sessions, detections and recordings. Models stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: madder, foregroundColor: paper),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await app.store.clear();
  }
}
