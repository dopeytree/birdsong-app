import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';

import '../app_state.dart';
import '../engine/model_catalog.dart';
import '../settings.dart';
import 'models_screen.dart' show megabytes;

/// First launch: choose where birds come from, fetch a model, switch on
/// Core ML, allow the microphone, and start.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.app, required this.onDone});

  final AppState app;

  /// Called with the tab to land on (0 is the plate).
  final ValueChanged<int> onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// The models offered on first launch; the rest are under Models.
const _starterIds = ['bnl-v3-10k', 'plus-v3-uk'];

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  AppMode _mode = AppMode.listen;
  String _model = _starterIds.first;
  bool _coreMl = Platform.isIOS || Platform.isMacOS;
  bool? _micAllowed;
  bool? _locAllowed;
  late final TextEditingController _url;
  late final TextEditingController _station;

  AppState get app => widget.app;
  Settings get s => app.settings;
  bool get _apple => Platform.isIOS || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _mode = s.mode;
    _coreMl = _apple;
    _url = TextEditingController(text: s.birdnetUrl);
    _station = TextEditingController(text: s.birdweatherStation);
    app.models.addListener(_modelsChanged);
    // Someone coming back to the welcome keeps a model they already have.
    for (final id in _starterIds) {
      final spec = specById(id)!;
      if (app.models.isInstalled(spec)) {
        _model = id;
        break;
      }
    }
  }

  // The Next button waits on the download, so redraw as it progresses.
  void _modelsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    app.models.removeListener(_modelsChanged);
    _url.dispose();
    _station.dispose();
    super.dispose();
  }

  ModelSpec get _spec => specById(_model)!;

  Future<void> _askMic() async {
    final rec = AudioRecorder();
    try {
      final ok = await rec.hasPermission();
      if (mounted) setState(() => _micAllowed = ok);
    } catch (_) {
      if (mounted) setState(() => _micAllowed = false);
    } finally {
      rec.dispose();
    }
  }

  Future<void> _askLocation() async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      final ok = p == LocationPermission.whileInUse || p == LocationPermission.always;
      if (mounted) setState(() => _locAllowed = ok);
    } catch (_) {
      if (mounted) setState(() => _locAllowed = false);
    }
  }

  void _skip() {
    s.update((x) => x.onboarded = true);
    widget.onDone(0);
  }

  void _finishStation() {
    s.update((x) {
      x.mode = AppMode.station;
      x.birdnetUrl = _url.text.trim();
      x.birdweatherStation = _station.text.trim();
      x.onboarded = true;
    });
    widget.onDone(0);
  }

  void _finishListen() {
    s.update((x) {
      x.mode = AppMode.listen;
      x.activeModels = {_model};
      x.plateModel = _model;
      x.useCoreMl = _coreMl;
      // With a location, the geomodel drops birds that don't live there.
      if (_locAllowed == true) x.useGeomodel = true;
      x.onboarded = true;
    });
    widget.onDone(0);
    app.engine.start();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listen = _mode == AppMode.listen;
    final steps = listen ? 4 : 2;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Step ${_step + 1} of $steps', style: theme.textTheme.bodySmall),
                      const Spacer(),
                      TextButton(onPressed: _skip, child: const Text('Skip')),
                    ],
                  ),
                  LinearProgressIndicator(value: (_step + 1) / steps),
                  const SizedBox(height: 24),
                  Expanded(
                    child: SingleChildScrollView(
                      child: switch (_step) {
                        0 => _welcome(theme),
                        1 => listen ? _modelStep(theme) : _stationStep(theme),
                        2 => _speedStep(theme),
                        _ => _micStep(theme),
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (_step > 0)
                        TextButton(
                            onPressed: () => setState(() => _step--), child: const Text('Back')),
                      const Spacer(),
                      _nextButton(listen),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _nextButton(bool listen) {
    if (!listen && _step == 1) {
      return FilledButton(onPressed: _finishStation, child: const Text('Show the plate'));
    }
    if (listen && _step == 3) {
      return FilledButton.icon(
        onPressed: _finishListen,
        icon: const Icon(Icons.mic),
        label: const Text('Start listening'),
      );
    }
    final waitingForModel = listen && _step == 1 && !app.models.isInstalled(_spec);
    return FilledButton(
      onPressed: waitingForModel ? null : () => setState(() => _step++),
      child: const Text('Next'),
    );
  }

  // ---- step 1: where do the birds come from --------------------------------

  Widget _welcome(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Birdsong', style: theme.textTheme.displaySmall),
        const SizedBox(height: 8),
        const Text('The birds you hear, drawn as a plate of 1800s illustrations. '
            'Where should they come from?'),
        const SizedBox(height: 20),
        _choice(
          selected: _mode == AppMode.listen,
          icon: Icons.hearing,
          title: 'Listen here & now',
          body: 'Identifies birds through the microphone, on the device. '
              'Nothing else needed, and no audio leaves it.',
          onTap: () => setState(() => _mode = AppMode.listen),
        ),
        _choice(
          selected: _mode == AppMode.station,
          icon: Icons.router,
          title: 'A remote station',
          body: 'Show what your BirdNET-Go or a BirdWeather station has heard.',
          onTap: () => setState(() => _mode = AppMode.station),
        ),
        const SizedBox(height: 8),
        Text('You can change this at any time under Settings.',
            style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _choice({
    required bool selected,
    required IconData icon,
    required String title,
    required String body,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Card(
      color: selected ? theme.colorScheme.primaryContainer : null,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(body),
        trailing: selected ? const Icon(Icons.check_circle) : null,
        onTap: onTap,
      ),
    );
  }

  // ---- step 2 (station): the address ---------------------------------------

  Widget _stationStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your station', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        TextField(
          controller: _url,
          decoration: const InputDecoration(
            labelText: 'BirdNET-Go address',
            hintText: 'http://192.168.1.50:8080',
          ),
          keyboardType: TextInputType.url,
          autocorrect: false,
        ),
        TextField(
          controller: _station,
          decoration: const InputDecoration(
            labelText: 'or a public BirdWeather station number',
            hintText: '12345',
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        Text(
            'iOS will ask to let Birdsong find devices on your local network: '
            'allow it, or the station can\'t be reached.',
            style: theme.textTheme.bodySmall),
      ],
    );
  }

  // ---- step 2 (listen): a model --------------------------------------------

  Widget _modelStep(ThemeData theme) {
    return ListenableBuilder(
      listenable: app.models,
      builder: (context, _) {
        final m = app.models;
        final busy = _starterIds.any((id) => m.isDownloading(specById(id)!));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Download a model', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('The model is what recognises the birds. It is downloaded once '
                'and then works offline.'),
            const SizedBox(height: 16),
            for (final id in _starterIds)
              _modelChoice(specById(id)!, recommended: id == _starterIds.first, busy: busy),
            if (m.errors[_model] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Download failed: ${m.errors[_model]}',
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 12),
            if (m.isInstalled(_spec))
              const Row(children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Downloaded and ready.'),
              ])
            else if (m.isDownloading(_spec)) ...[
              LinearProgressIndicator(value: m.progress[_model]),
              const SizedBox(height: 6),
              Text('${((m.progress[_model] ?? 0) * 100).round()}% of ${megabytes(_spec.totalBytes)}'),
            ] else
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        m.install(_spec);
                        // The location filter is small; fetch it alongside.
                        if (!m.isInstalled(geomodel)) m.install(geomodel);
                      },
                icon: const Icon(Icons.download),
                label: Text('Download ${megabytes(_spec.totalBytes)}'),
              ),
            const SizedBox(height: 12),
            Text('More models, to compare side by side, are under Models.',
                style: theme.textTheme.bodySmall),
          ],
        );
      },
    );
  }

  Widget _modelChoice(ModelSpec spec, {required bool recommended, required bool busy}) {
    final theme = Theme.of(context);
    final selected = _model == spec.id;
    return Card(
      color: selected ? theme.colorScheme.primaryContainer : null,
      child: ListTile(
        title: Text(recommended ? '${spec.name} (recommended)' : spec.name),
        subtitle: Text('${megabytes(spec.totalBytes)} · ${spec.note}'),
        trailing: selected ? const Icon(Icons.check_circle) : null,
        onTap: busy ? null : () => setState(() => _model = spec.id),
      ),
    );
  }

  // ---- step 3 (listen): speed ----------------------------------------------

  Widget _speedStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Speed', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        if (_apple) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use the GPU and Neural Engine'),
            subtitle: const Text('Runs the model through Apple\'s Core ML rather than '
                'the processor alone. If a model can\'t run that way, Birdsong '
                'falls back to the processor by itself.'),
            value: _coreMl,
            onChanged: (v) => setState(() => _coreMl = v),
          ),
          const SizedBox(height: 8),
          Text(
              'The Listen tab shows the time each window takes, so you can try it '
              'both ways. The first start with this on can take a while, as the '
              'model is prepared for the chip.',
              style: theme.textTheme.bodySmall),
        ] else
          const Text('On this device the model runs on the processor. '
              'The Listen tab shows the time each window takes.'),
      ],
    );
  }

  // ---- step 4 (listen): the microphone -------------------------------------

  Widget _micStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Microphone and location', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Birdsong needs the microphone to hear the birds. Sound is analysed '
            'on this device and never sent anywhere. Short recordings of each '
            'detection are kept on the device so you can play them back.'),
        const SizedBox(height: 16),
        if (_micAllowed == true)
          const Row(children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Microphone allowed.'),
          ])
        else
          OutlinedButton.icon(
            onPressed: _askMic,
            icon: const Icon(Icons.mic_none),
            label: const Text('Allow the microphone'),
          ),
        if (_micAllowed == false)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                'It was refused. Allow Birdsong under the device\'s Settings > '
                'Privacy > Microphone, then try again.',
                style: TextStyle(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: 24),
        const Text('Location is optional. Each listening session is marked with where '
            'it happened, and the app leaves out birds that don\'t live there.'),
        const SizedBox(height: 12),
        if (_locAllowed == true)
          const Row(children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Location allowed.'),
          ])
        else
          OutlinedButton.icon(
            onPressed: _askLocation,
            icon: const Icon(Icons.place_outlined),
            label: const Text('Allow location'),
          ),
        if (_locAllowed == false)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Not allowed. Sessions will have no place; you can allow it later '
                'under the device\'s Settings > Privacy > Location Services.',
                style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}
