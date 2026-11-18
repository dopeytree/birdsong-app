import 'package:flutter/material.dart';

import '../app_state.dart';
import '../engine/model_catalog.dart';

String megabytes(int bytes) =>
    bytes <= 0 ? 'size unknown' : '${(bytes / 1048576).toStringAsFixed(0)} MB';

class ModelsScreen extends StatelessWidget {
  const ModelsScreen({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app.models, app.settings, app.engine]),
      builder: (context, _) {
        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Models', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            const Text('Tick the models to listen with; every window goes through each of '
                'them, so you can compare. The plate draws one of them, or all.'),
            if (app.engine.running)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Stop listening to change which models run.',
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: ChoiceChip(
                label: const Text('Plate draws every model\'s detections'),
                selected: app.settings.plateModel == 'all',
                onSelected: (_) => app.settings.update((s) => s.plateModel = 'all'),
              ),
            ),
            for (final spec in catalog) _ModelCard(app: app, spec: spec),
            const SizedBox(height: 12),
            Text('Location filter', style: theme.textTheme.titleMedium),
            _ModelCard(app: app, spec: geomodel, audio: false),
          ],
        );
      },
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.app, required this.spec, this.audio = true});

  final AppState app;
  final ModelSpec spec;
  final bool audio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = app.models;
    final s = app.settings;
    final installed = m.isInstalled(spec);
    final downloading = m.isDownloading(spec);
    final active = s.activeModels.contains(spec.id);
    final locked = app.engine.running;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(spec.name, style: theme.textTheme.titleMedium)),
                Chip(
                  label: Text(spec.releaseOk ? spec.licence : '${spec.licence} · testing only'),
                  backgroundColor: spec.releaseOk
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.25),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Text(
                [
                  megabytes(spec.totalBytes),
                  if (audio) '${spec.sampleRate ~/ 1000} kHz, ${spec.windowSeconds.toStringAsFixed(0)} s windows',
                  if (spec.note.isNotEmpty) spec.note,
                ].join(' · '),
                style: theme.textTheme.bodySmall),
            if (m.errors[spec.id] != null)
              Text(m.errors[spec.id]!, style: TextStyle(color: theme.colorScheme.error)),
            if (downloading)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(value: m.progress[spec.id]),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (!installed && !downloading)
                  TextButton.icon(
                    onPressed: () => m.install(spec),
                    icon: const Icon(Icons.download),
                    label: const Text('Download'),
                  ),
                if (installed)
                  TextButton.icon(
                    onPressed: locked ? null : () => m.remove(spec),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                const Spacer(),
                if (audio && installed) ...[
                  const Text('Listen'),
                  Checkbox(
                    value: active,
                    onChanged: locked
                        ? null
                        : (v) => s.update((x) {
                              if (v == true) {
                                x.activeModels = {...x.activeModels, spec.id};
                              } else {
                                x.activeModels = {...x.activeModels}..remove(spec.id);
                              }
                            }),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('On the plate'),
                    selected: s.plateModel == spec.id,
                    onSelected: (_) => s.update((x) => x.plateModel = spec.id),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
