import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../engine/listen_engine.dart';
import '../engine/model_catalog.dart';
import '../main.dart' show sepia, serif;
import '../server/page_control.dart';
import '../settings.dart';
import 'format.dart';
import 'splash.dart' show Cardinal, SupportQuote;
import 'station_editor.dart';
import 'station_history.dart';

/// Everything that isn't the plate: where birds come from, listening,
/// models, the location filter and stored data. Opened from the plate's
/// menu button.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.app});

  final AppState app;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _lat;
  late final TextEditingController _lon;
  final _limit = TextEditingController();

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
    super.dispose();
  }

  void _saveLocation() => s.update((x) {
        x.latitude = double.tryParse(_lat.text.trim());
        x.longitude = double.tryParse(_lon.text.trim());
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: Listenable.merge([s, app.engine, app.models, app.store, app.updates]),
        builder: (context, _) {
          final listen = s.mode == AppMode.listen;
          // On a wide window (a Mac, an iPad) the settings keep to a
          // readable column in the middle.
          final side = ((MediaQuery.sizeOf(context).width - 680) / 2).clamp(16.0, 400.0);
          return ListView(
            padding: EdgeInsets.fromLTRB(side, 4, side, 32),
            children: [
              // the same menu whether listening here or showing a station:
              // the plate, the map and the experiments apply to both
              s.webPlate ? _displaySection(context, listen) : _flutterDisplaySection(context),
              _mapSection(context),
              _section(
                context,
                'Experimental',
                summary: s.webPlate ? 'The old web plate' : 'Nothing switched on',
                [
                  _switch('Use the old web plate', s.webPlate, (v) => s.update((x) => x.webPlate = v)),
                  Text(
                    'The plate as the web page drew it, before it was moved into Flutter. '
                    'Its own Display options show above while it is on.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SegmentedButton<AppMode>(
                segments: const [
                  ButtonSegment(
                      value: AppMode.listen,
                      icon: Icon(Icons.mic_none_outlined),
                      label: Text('Listen here & now')),
                  ButtonSegment(
                      value: AppMode.station, icon: Icon(Icons.sensors), label: Text('Remote station')),
                ],
                selected: {s.mode},
                showSelectedIcon: false,
                onSelectionChanged: (v) {
                  // a remote station with none saved yet: ask for one
                  if (v.first == AppMode.station && s.stations.isEmpty) {
                    editStation(context, s);
                    return;
                  }
                  s.update((x) => x.mode = v.first);
                },
              ),
              const SizedBox(height: 8),
              // the saved stations, then listening here: both, either way
              _remote(context),
              _listening(context),
              _models(context),
              _location(context),
              _data(context),
              // what keeping the stations' days is doing (station_archive.dart)
              if (s.stations.isNotEmpty)
                _section(
                  context,
                  'Station history',
                  summary: 'Days kept on this device, and the log',
                  [StationHistory(root: app.store.root, stations: s.stations)],
                ),
              const Divider(height: 32),
              _credits(context, listen),
              const Divider(height: 1),
              _support(context),
              const Divider(height: 1),
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
          );
        },
      ),
    );
  }

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
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) s.removeStation(st.id);
  }

  Widget _listening(BuildContext context) {
    final theme = Theme.of(context);
    final engine = app.engine;
    final locked = engine.running;
    return _section(
      context,
      'Listening',
      summary: engine.running
          ? 'Listening · ${engine.levelDb.toStringAsFixed(0)} dBFS'
          : '${(s.threshold * 100).round()}% · every ${s.hopSeconds.toStringAsFixed(1)} s',
      open: engine.running,
      [
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
        _slider('Every ${s.hopSeconds.toStringAsFixed(1)} s', s.hopSeconds, 0.5, 5, 9,
            (v) => s.update((x) => x.hopSeconds = v)),
        _slider('Repeat after ${s.repeatSeconds.round()} s', s.repeatSeconds, 3, 60, 19,
            (v) => s.update((x) => x.repeatSeconds = v)),
        _switch('Animals only', s.animalsOnly, (v) => s.update((x) => x.animalsOnly = v)),
        if (Platform.isIOS || Platform.isMacOS)
          _switch('Core ML (GPU / Neural Engine)', s.useCoreMl,
              locked ? null : (v) => s.update((x) => x.useCoreMl = v)),
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

  Widget _models(BuildContext context) {
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
      open: installed.isEmpty,
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

  Widget _location(BuildContext context) {
    final m = app.models;
    final locked = app.engine.running;
    final geoReady = m.isInstalled(geomodel);
    return _section(
      context,
      'Location filter',
      summary: s.useGeomodel
          ? (geoReady ? 'On' : 'On · geomodel not downloaded')
          : 'Off',
      [
        _switch('Drop species unlikely here', s.useGeomodel,
            locked ? null : (v) => s.update((x) => x.useGeomodel = v)),
        _switch('Note the weather (MET Norway)', s.recordWeather,
            (v) => s.update((x) => x.recordWeather = v)),
        if (!geoReady)
          m.isDownloading(geomodel)
              ? LinearProgressIndicator(value: m.progress[geomodel.id])
              : TextButton.icon(
                  onPressed: () => m.install(geomodel),
                  icon: const Icon(Icons.download),
                  label: Text('Geomodel, ${megabytes(geomodel.totalBytes)}'),
                ),
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
    );
  }

  Widget _data(BuildContext context) {
    final theme = Theme.of(context);
    final store = app.store;
    return _section(
      context,
      'Data',
      summary: '${store.sessions.length} sessions · ${store.all.length} detections',
      [
        FutureBuilder<int>(
          future: app.engine.clipBytes(),
          builder: (context, snap) =>
              Text('Recordings ${megabytes(snap.data ?? 0)}', style: theme.textTheme.bodySmall),
        ),
        const SizedBox(height: 8),
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

  /// The Flutter plate's Display options (the web plate's, below, while
  /// Experimental > Use the old web plate is on).
  Widget _flutterDisplaySection(BuildContext context) => _section(
        context,
        'Display',
        summary: PageControl.sizeBy[s.nativeSizeBy] ?? '',
        [
          _switch('Fit on one screen', s.nativeFit, (v) => s.update((x) => x.nativeFit = v)),
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
        ],
      );

  /// The web plate's Display options, read from and set through the page.
  Widget _displaySection(BuildContext context, bool listen) {
    final d = _display;
    if (d == null) {
      return _section(context, 'Display', summary: 'Open the plate first', const []);
    }
    bool on(String k) => d[k] == true;
    String pick(String k, Map<String, String> from, String fallback) {
      final v = d[k];
      return v is String && from.containsKey(v) ? v : fallback;
    }

    return _section(
      context,
      'Display',
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

  Widget _mapSection(BuildContext context) {
    final theme = Theme.of(context);
    return _section(
      context,
      'Map',
      summary: s.showMap ? 'Showing the walk · ${mapBirds[s.mapBirds]}' : 'Showing the collage',
      [
        _switch('Show the walk on a map', s.showMap, (v) => s.update((x) => x.showMap = v)),
        _dropdown('Crosses', s.mapBirds, mapBirds, (v) => s.update((x) => x.mapBirds = v)),
        _switch('Landmarks, heritage and nature sites', s.mapExtras,
            (v) => s.update((x) => x.mapExtras = v)),
        if (s.mapExtras)
          _switch('Descriptions in Passed on the way', s.mapPassedAbout,
              (v) => s.update((x) => x.mapPassedAbout = v)),
        if (kDebugMode)
          _switch('Timing readout on the map (debug)', s.mapDebugReadout,
              (v) => s.update((x) => x.mapDebugReadout = v)),
        Text(
          'The map is drawn from OpenFreeMap and open elevation data, so the area of each walk '
          'is sent to them. Landmarks also send it to Historic England, Natural England and '
          'Wikipedia, and list what the walk passed above the map.',
          style: theme.textTheme.bodySmall,
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
  Widget _credits(BuildContext context, bool listen) {
    final theme = Theme.of(context);
    final detections = listen
        ? 'BirdNET, run on this device (${effectiveById(s.plateModel, s.modelOverrides)?.family ?? 'the chosen model'})'
        : s.stationDigits.isNotEmpty
            ? 'BirdWeather'
            : 'BirdNET-Go';
    return _section(context, 'Credits', [
      FutureBuilder<String?>(
        future: _webVersion,
        builder: (context, snap) => Text(
          'Birdsong${snap.data == null ? '' : ' v${snap.data}'}. Created by Ed Stone. '
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
  Widget _support(BuildContext context) {
    final theme = Theme.of(context);
    return _section(context, 'Support', [
      const Center(child: Cardinal(height: 110)),
      const SizedBox(height: 12),
      const SupportQuote(size: 15),
      const SizedBox(height: 16),
      Text(
        'One hopes you are enjoying Birdsong. If something is amiss, or it does not yet do '
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
          SizedBox(width: 130, child: Text(label)),
          DropdownButton<String>(
            value: value,
            items: [
              for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => v == null ? null : onChanged(v),
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
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await app.store.clear();
  }
}
