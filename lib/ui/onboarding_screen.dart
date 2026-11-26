import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';

import '../app_state.dart';
import '../engine/model_catalog.dart';
import '../main.dart' show caps, ink, madder, paper, paperDeep, rule, sepia, serif;
import '../settings.dart';
import 'format.dart' show megabytes;
import 'splash.dart' show Cardinal;
import 'station_editor.dart' show openBirdWeatherMap;

/// First launch: choose where birds come from, fetch a model, switch on
/// Core ML, allow permissions, and open birdsongs.ai (never auto-recording).
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
    // Keep the user's current model if they revisit the welcome screens.
    if (_starterIds.contains(s.plateModel) && app.models.isInstalled(_byId(s.plateModel))) {
      _model = s.plateModel;
    } else {
      for (final id in _starterIds) {
        final spec = _byId(id);
        if (app.models.isInstalled(spec)) {
          _model = id;
          break;
        }
      }
    }
  }

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

  ModelSpec _byId(String id) => effectiveById(id, s.modelOverrides)!;

  ModelSpec get _spec => _byId(_model);

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
    s.update((x) {
      x.plateMode = defaultPlateMode;
      x.onboarded = true;
    });
    widget.onDone(0);
  }

  void _finishStation() {
    final bw = _station.text.trim(), url = _url.text.trim();
    final input = bw.isNotEmpty ? bw : url;
    if (input.isNotEmpty) {
      final current = s.station;
      final same = current != null && current.input == input;
      if (!same) s.putStation(Station.fromInput('', input));
    }
    s.update((x) {
      x.mode = AppMode.station;
      x.plateMode = defaultPlateMode;
      x.nativeSizeBy = 'calls';
      x.onboarded = true;
    });
    widget.onDone(0);
  }

  void _finishListen() {
    // Never lose or hide existing sessions when re-running the welcome screens:
    // if prior detections exist from another model (or 'all' was already set),
    // keep plateModel as 'all' so every recorded walk stays visible.
    final hasOtherModelSessions = app.store.all.any((d) => d.model != _model);
    s.update((x) {
      x.mode = AppMode.listen;
      x.plateMode = defaultPlateMode;
      x.nativeSizeBy = 'time';
      if (x.activeModels.isEmpty) {
        x.activeModels = {_model};
      } else {
        x.activeModels = {...x.activeModels, _model};
      }
      x.plateModel = (hasOtherModelSessions || x.plateModel == 'all') ? 'all' : _model;
      x.useCoreMl = _coreMl;
      if (_locAllowed == true) x.useGeomodel = true;
      x.onboarded = true;
    });
    widget.onDone(0);
  }

  @override
  Widget build(BuildContext context) {
    final listen = _mode == AppMode.listen;
    final steps = listen ? 4 : 2;
    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _stepPills(steps),
                      const Spacer(),
                      TextButton(onPressed: _skip, child: const Text('Skip')),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0.03, 0), end: Offset.zero).animate(anim),
                          child: child,
                        ),
                      ),
                      child: SingleChildScrollView(
                        key: ValueKey('$_step|$listen'),
                        child: switch (_step) {
                          0 => _welcome(),
                          1 => listen ? _modelStep() : _stationStep(),
                          2 => _speedStep(),
                          _ => _micStep(),
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (_step > 0)
                        TextButton.icon(
                          onPressed: () => setState(() => _step--),
                          icon: const Icon(Icons.chevron_left, size: 18),
                          label: const Text('Back'),
                        ),
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

  Widget _stepPills(int total) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.only(right: 6),
            height: 6,
            width: i == _step ? 24 : 8,
            decoration: BoxDecoration(
              color: i <= _step ? ink : rule.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }

  Widget _nextButton(bool listen) {
    if (!listen && _step == 1) {
      return FilledButton.icon(
        onPressed: _finishStation,
        icon: const Icon(Icons.arrow_forward, size: 18),
        label: const Text('Open birdsongs.ai'),
      );
    }
    if (listen && _step == 3) {
      return FilledButton.icon(
        onPressed: _finishListen,
        icon: const Icon(Icons.arrow_forward, size: 18),
        label: const Text('Open birdsongs.ai'),
      );
    }
    final waitingForModel = listen && _step == 1 && !app.models.isInstalled(_spec);
    return FilledButton.icon(
      onPressed: waitingForModel ? null : () => setState(() => _step++),
      icon: const Icon(Icons.arrow_forward, size: 18),
      label: const Text('Continue'),
    );
  }

  Widget _header(String title, String subtitle, {Widget? crest}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (crest != null) ...[
          crest,
          const SizedBox(height: 12),
        ],
        Text(
          title,
          style: const TextStyle(fontFamily: caps, fontSize: 28, letterSpacing: 1.0, height: 1.15, color: ink),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(fontFamily: serif, fontSize: 16.5, height: 1.45, color: sepia),
        ),
      ],
    );
  }

  // ---- step 1: where do the birds come from --------------------------------

  Widget _welcome() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          'birdsongs.ai',
          'The birds you hear, illustrated as natural-history plates. Choose how you want to listen.',
          crest: const Cardinal(height: 64),
        ),
        const SizedBox(height: 22),
        _optionCard(
          selected: _mode == AppMode.listen,
          icon: Icons.mic_none_outlined,
          title: 'Listen here & now',
          body: 'Identifies birds on this device using the microphone. Works offline and no audio leaves your device.',
          onTap: () => setState(() => _mode = AppMode.listen),
        ),
        const SizedBox(height: 10),
        _optionCard(
          selected: _mode == AppMode.station,
          icon: Icons.sensors,
          title: 'Connect a remote station',
          body: 'Follow what your BirdNET-Go station or a public BirdWeather station has heard.',
          onTap: () => setState(() => _mode = AppMode.station),
        ),
        const SizedBox(height: 14),
        const Text(
          'You can switch between local and remote at any time from the top bar.',
          style: TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 13.5, color: sepia),
        ),
      ],
    );
  }

  Widget _optionCard({
    required bool selected,
    required IconData icon,
    required String title,
    required String body,
    String? badge,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        hoverColor: ink.withValues(alpha: 0.06),
        highlightColor: ink.withValues(alpha: 0.10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: selected ? paperDeep.withValues(alpha: 0.82) : paperDeep.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: selected ? ink : paperDeep.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: selected ? paper : ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontFamily: caps, fontSize: 15.5, letterSpacing: 0.5, color: ink),
                          ),
                        ),
                        if (badge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: paperDeep,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              badge,
                              style: const TextStyle(fontFamily: caps, fontSize: 10.5, letterSpacing: 0.4, color: sepia),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      body,
                      style: const TextStyle(fontFamily: serif, fontSize: 14.5, height: 1.4, color: sepia),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? ink : rule,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- step 2 (station): the address ---------------------------------------

  Widget _stationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          'Your station',
          'Enter your BirdNET-Go address on your home network, or any public BirdWeather station ID.',
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: paperDeep.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _url,
                decoration: const InputDecoration(
                  labelText: 'BirdNET-Go address',
                  hintText: 'http://192.168.1.50:8080',
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _station,
                decoration: const InputDecoration(
                  labelText: 'or a public BirdWeather station number',
                  hintText: '12345',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: openBirdWeatherMap,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Browse public stations on BirdWeather'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'iOS will ask to let birdsongs.ai find devices on your local network: allow it so your BirdNET-Go station can be reached.',
          style: TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 13.5, color: sepia),
        ),
      ],
    );
  }

  // ---- step 2 (listen): a model --------------------------------------------

  Widget _modelStep() {
    return ListenableBuilder(
      listenable: app.models,
      builder: (context, _) {
        final m = app.models;
        final busy = _starterIds.any((id) => m.isDownloading(_byId(id)));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(
              'Choose a model',
              'Downloaded once to your device so bird recognition works completely offline.',
            ),
            const SizedBox(height: 20),
            for (final id in _starterIds) ...[
              () {
                final spec = _byId(id);
                return _optionCard(
                  selected: _model == spec.id,
                  icon: Icons.psychology_outlined,
                  title: spec.name,
                  badge: id == _starterIds.first ? 'Recommended' : null,
                  body: '${megabytes(spec.totalBytes)} · ${spec.note}',
                  onTap: busy ? null : () => setState(() => _model = spec.id),
                );
              }(),
              const SizedBox(height: 10),
            ],
            if (m.errors[_model] != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Download failed: ${m.errors[_model]}',
                  style: const TextStyle(fontFamily: serif, fontSize: 14, color: madder),
                ),
              ),
            const SizedBox(height: 10),
            if (m.isInstalled(_spec))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: paperDeep.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 18, color: ink),
                    SizedBox(width: 8),
                    Text('Downloaded and ready.', style: TextStyle(fontFamily: serif, fontSize: 15, color: ink)),
                  ],
                ),
              )
            else if (m.isDownloading(_spec))
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: paperDeep.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: m.progress[_model], minHeight: 6),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Downloading · ${((m.progress[_model] ?? 0) * 100).round()}% of ${megabytes(_spec.totalBytes)}',
                      style: const TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 14, color: sepia),
                    ),
                  ],
                ),
              )
            else
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        m.install(_spec);
                        if (!m.isInstalled(geomodel)) m.install(geomodel);
                      },
                icon: const Icon(Icons.download_outlined, size: 18),
                label: Text('Download ${megabytes(_spec.totalBytes)}'),
              ),
            const SizedBox(height: 12),
            const Text(
              'More models are available under Settings whenever you want to compare them.',
              style: TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 13.5, color: sepia),
            ),
          ],
        );
      },
    );
  }

  // ---- step 3 (listen): speed ----------------------------------------------

  Widget _speedStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          'Performance',
          _apple
              ? 'Use Apple\'s GPU and Neural Engine for faster, lower-power listening.'
              : 'On this device the model runs directly on the processor.',
        ),
        const SizedBox(height: 20),
        if (_apple) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 12),
            decoration: BoxDecoration(
              color: paperDeep.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(16),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _coreMl ? ink : paperDeep,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.bolt_outlined, size: 20, color: _coreMl ? paper : ink),
              ),
              title: const Text(
                'Core ML acceleration',
                style: TextStyle(fontFamily: caps, fontSize: 15.5, letterSpacing: 0.5, color: ink),
              ),
              subtitle: const Text(
                'Falls back automatically to the CPU if a model cannot use Core ML.',
                style: TextStyle(fontFamily: serif, fontSize: 14, color: sepia),
              ),
              value: _coreMl,
              onChanged: (v) => setState(() => _coreMl = v),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'The first recording with Core ML on takes a few extra seconds while the chip compiles the model.',
            style: TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 13.5, color: sepia),
          ),
        ],
      ],
    );
  }

  // ---- step 4 (listen): permissions ----------------------------------------

  Widget _micStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          'Permissions',
          'Allow access when you\'re ready — recording only begins when you tap the record button.',
        ),
        const SizedBox(height: 20),
        _permissionCard(
          icon: Icons.mic_none_outlined,
          title: 'Microphone',
          body: 'Required to identify birds around you. All analysis stays on your device.',
          allowed: _micAllowed,
          actionLabel: 'Allow microphone',
          deniedNote: 'Refused. Enable it under Settings > Privacy > Microphone.',
          onAction: _askMic,
        ),
        const SizedBox(height: 12),
        _permissionCard(
          icon: Icons.location_on_outlined,
          title: 'Location (optional)',
          body: 'Maps your walk, notes the weather, and filters out species unlikely in your region.',
          allowed: _locAllowed,
          actionLabel: 'Allow location',
          deniedNote: 'Not allowed. Sessions will still record without a map location.',
          onAction: _askLocation,
        ),
      ],
    );
  }

  Widget _permissionCard({
    required IconData icon,
    required String title,
    required String body,
    required bool? allowed,
    required String actionLabel,
    required String deniedNote,
    required VoidCallback onAction,
  }) {
    final granted = allowed == true;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: granted ? paperDeep.withValues(alpha: 0.72) : paperDeep.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: granted ? ink : paperDeep.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 19, color: granted ? paper : ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontFamily: caps, fontSize: 15.5, letterSpacing: 0.5, color: ink),
                ),
              ),
              if (granted)
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 18, color: ink),
                    SizedBox(width: 4),
                    Text('Allowed', style: TextStyle(fontFamily: caps, fontSize: 12, color: ink)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(fontFamily: serif, fontSize: 14.5, height: 1.4, color: sepia)),
          if (!granted) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: Icon(icon, size: 17),
              label: Text(actionLabel),
            ),
          ],
          if (allowed == false)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(deniedNote, style: const TextStyle(fontFamily: serif, fontSize: 13, color: madder)),
            ),
        ],
      ),
    );
  }
}
