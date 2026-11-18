import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../settings.dart';
import 'models_screen.dart' show megabytes;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.app});

  final AppState app;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  late final TextEditingController _station;
  late final TextEditingController _lat;
  late final TextEditingController _lon;

  Settings get s => widget.app.settings;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: s.birdnetUrl);
    _station = TextEditingController(text: s.birdweatherStation);
    _lat = TextEditingController(text: s.latitude?.toString() ?? '');
    _lon = TextEditingController(text: s.longitude?.toString() ?? '');
  }

  @override
  void dispose() {
    _url.dispose();
    _station.dispose();
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  void _saveStation() => s.update((x) {
        x.birdnetUrl = _url.text.trim();
        x.birdweatherStation = _station.text.trim();
      });

  void _saveLocation() => s.update((x) {
        x.latitude = double.tryParse(_lat.text.trim());
        x.longitude = double.tryParse(_lon.text.trim());
      });

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return ListenableBuilder(
      listenable: Listenable.merge([s, app.engine]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final locked = app.engine.running;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Settings', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text('The plate shows', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<AppMode>(
              segments: const [
                ButtonSegment(value: AppMode.station, label: Text('Station'), icon: Icon(Icons.router)),
                ButtonSegment(value: AppMode.listen, label: Text('Listen here'), icon: Icon(Icons.hearing)),
              ],
              selected: {s.mode},
              onSelectionChanged: (v) => s.update((x) => x.mode = v.first),
            ),
            const SizedBox(height: 16),
            if (s.mode == AppMode.station) ...[
              TextField(
                controller: _url,
                decoration: const InputDecoration(
                  labelText: 'BirdNET-Go address',
                  hintText: 'http://192.168.1.50:8080',
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                onSubmitted: (_) => _saveStation(),
              ),
              TextField(
                controller: _station,
                decoration: const InputDecoration(
                  labelText: 'or a public BirdWeather station number',
                  hintText: '12345',
                ),
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _saveStation(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(onPressed: _saveStation, child: const Text('Save and reload the plate')),
              ),
              const SizedBox(height: 4),
              Text('A BirdWeather station, if given, wins over BirdNET-Go.',
                  style: theme.textTheme.bodySmall),
              const Divider(height: 32),
            ],
            Text('Listen here', style: theme.textTheme.titleMedium),
            _slider(
              'Threshold ${(s.threshold * 100).round()}%',
              s.threshold, 0.05, 0.95, 18,
              (v) => s.update((x) => x.threshold = v),
            ),
            _slider(
              'Analyse every ${s.hopSeconds.toStringAsFixed(1)} s${locked ? ' (applies on next start)' : ''}',
              s.hopSeconds, 0.5, 5, 9,
              (v) => s.update((x) => x.hopSeconds = v),
            ),
            _slider(
              'Same bird again counts after ${s.repeatSeconds.round()} s',
              s.repeatSeconds, 3, 60, 19,
              (v) => s.update((x) => x.repeatSeconds = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Animals only'),
              subtitle: const Text('Ignore classes such as engine, dog or human voice'),
              value: s.animalsOnly,
              onChanged: (v) => s.update((x) => x.animalsOnly = v),
            ),
            if (Platform.isIOS || Platform.isMacOS)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use Core ML (Neural Engine / GPU)'),
                subtitle: Text('Experimental. Takes effect on next start.'
                    '${locked ? ' Stop listening first.' : ''}'),
                value: s.useCoreMl,
                onChanged: locked ? null : (v) => s.update((x) => x.useCoreMl = v),
              ),
            const Divider(height: 32),
            Text('Location filter', style: theme.textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Drop species unlikely here this week'),
              subtitle: const Text('Needs the geomodel (Models) and a location'),
              value: s.useGeomodel,
              onChanged: locked ? null : (v) => s.update((x) => x.useGeomodel = v),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _lat,
                    decoration: const InputDecoration(labelText: 'Latitude', hintText: '51.5'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    onSubmitted: (_) => _saveLocation(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _lon,
                    decoration: const InputDecoration(labelText: 'Longitude', hintText: '-0.12'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    onSubmitted: (_) => _saveLocation(),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(onPressed: _saveLocation, child: const Text('Save')),
              ],
            ),
            _slider(
              'Keep species above ${(s.geoThreshold * 100).toStringAsFixed(0)}% likely',
              s.geoThreshold, 0.01, 0.2, 19,
              (v) => s.update((x) => x.geoThreshold = v),
            ),
            const Divider(height: 32),
            Text('Data', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            FutureBuilder<int>(
              future: app.engine.clipBytes(),
              builder: (context, snap) => Text(
                  '${app.store.all.length} detections · recordings ${megabytes(snap.data ?? 0)}\n'
                  '${app.dataDir.path}',
                  style: theme.textTheme.bodySmall),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: locked ? null : () => _confirmClear(context),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Forget everything heard here'),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: locked ? null : () => s.update((x) => x.onboarded = false),
                child: const Text('Show the welcome screens again'),
              ),
            ),
            const SizedBox(height: 8),
            Text('Page served at ${app.server.origin}', style: theme.textTheme.bodySmall),
          ],
        );
      },
    );
  }

  Widget _slider(String label, double value, double min, double max, int divisions,
      ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(label)),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Forget everything heard here?'),
        content: const Text('Deletes every detection and recording on this device. '
            'Downloaded models stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await widget.app.store.clear();
  }
}
