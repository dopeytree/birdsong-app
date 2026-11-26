import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show paper, sepia;
import '../settings.dart';

/// BirdWeather's map of public stations. A station's page address ends in
/// its number (app.birdweather.com/stations/1234), which the editor reads.
const birdweatherMap = 'https://app.birdweather.com/';

/// Opens BirdWeather's map over the app where the system allows it (a sheet
/// on iPhone and iPad, a custom tab on Android), else in the browser.
Future<void> openBirdWeatherMap() async {
  final uri = Uri.parse(birdweatherMap);
  final inApp = await supportsLaunchMode(LaunchMode.inAppBrowserView);
  await launchUrl(uri, mode: inApp ? LaunchMode.inAppBrowserView : LaunchMode.externalApplication);
}

/// Adds a station, or edits [station]; saving switches the plate to it.
Future<void> editStation(BuildContext context, Settings s, {Station? station}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _StationDialog(s: s, station: station),
  );
}

class _StationDialog extends StatefulWidget {
  const _StationDialog({required this.s, this.station});

  final Settings s;
  final Station? station;

  @override
  State<_StationDialog> createState() => _StationDialogState();
}

class _StationDialogState extends State<_StationDialog> {
  late final _name = TextEditingController(text: widget.station?.name ?? '');
  late final _where = TextEditingController(text: widget.station?.input ?? '');

  @override
  void dispose() {
    _name.dispose();
    _where.dispose();
    super.dispose();
  }

  Station? get _parsed =>
      _where.text.trim().isEmpty ? null : Station.fromInput(_name.text, _where.text, id: widget.station?.id);

  void _save() {
    final st = _parsed;
    if (st == null) return;
    widget.s.putStation(st);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final st = _parsed;
    return AlertDialog(
      backgroundColor: paper,
      title: Text(widget.station == null ? 'Add a station' : 'Edit station'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'Garden'),
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _where,
              decoration: const InputDecoration(
                labelText: 'BirdNET-Go address or BirdWeather station',
                hintText: 'http://192.168.1.50:8080 or 1234',
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            Text(
              st == null ? 'Paste a BirdWeather station page to use its number.' : st.kind,
              style: theme.textTheme.bodySmall?.copyWith(color: sepia),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: openBirdWeatherMap,
              icon: const Icon(Symbols.map, size: 18),
              label: const Text('Find a station on BirdWeather'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: st == null ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
