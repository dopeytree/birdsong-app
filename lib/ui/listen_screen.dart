import 'package:flutter/material.dart';

import '../app_state.dart';
import '../engine/model_catalog.dart';
import '../server/local_api.dart' show hms;
import '../settings.dart';

class ListenScreen extends StatelessWidget {
  const ListenScreen({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final engine = app.engine;
    return ListenableBuilder(
      listenable: Listenable.merge([engine, app.store, app.settings]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final station = app.settings.mode == AppMode.station;
        final recent = app.store.all.reversed.take(30).toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Listen here & now', style: theme.textTheme.headlineSmall),
            if (station)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('The plate is showing your remote station. Switch to '
                    '"Listen here & now" under Settings to see what this device hears on the plate.'),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: engine.starting
                      ? null
                      : () => engine.running ? engine.stop() : engine.start(),
                  icon: Icon(engine.running ? Icons.stop : Icons.mic),
                  label: Text(engine.starting
                      ? 'Loading models...'
                      : engine.running
                          ? 'Stop'
                          : 'Start listening'),
                ),
                const SizedBox(width: 16),
                if (engine.running)
                  Expanded(
                    child: LinearProgressIndicator(
                      value: ((engine.levelDb + 70) / 70).clamp(0.0, 1.0).toDouble(),
                      minHeight: 10,
                    ),
                  ),
              ],
            ),
            if (engine.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(engine.error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            if (engine.running)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    'Input ${engine.levelDb.toStringAsFixed(0)} dBFS · analysing every '
                    '${app.settings.hopSeconds.toStringAsFixed(1)} s · '
                    'threshold ${(app.settings.threshold * 100).round()}%'
                    '${engine.skipped > 0 ? ' · ${engine.skipped} windows skipped (models busy)' : ''}'),
              ),
            const SizedBox(height: 16),
            for (final r in engine.reports.values)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.spec.name, style: theme.textTheme.titleMedium),
                      Text(
                          r.runs == 0
                              ? 'Waiting for ${r.spec.windowSeconds.toStringAsFixed(0)} s of audio'
                              : '${r.millis} ms last window · ${r.averageMillis} ms average · ${r.runs} windows · ${r.backend}',
                          style: theme.textTheme.bodySmall),
                      if (r.error != null)
                        Text(r.error!, style: TextStyle(color: theme.colorScheme.error)),
                      const SizedBox(height: 6),
                      for (final (name, score) in r.top)
                        Row(
                          children: [
                            SizedBox(
                              width: 44,
                              child: Text('${(score * 100).round()}%',
                                  // Above the threshold: the plate's madder red,
                                  // as the page marks counts (the face has no bold).
                                  style: TextStyle(
                                      color: score >= app.settings.threshold
                                          ? theme.colorScheme.primary
                                          : null)),
                            ),
                            Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text('Heard on this device (${app.store.all.length})',
                style: theme.textTheme.titleMedium),
            if (recent.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Nothing yet.'),
              ),
            for (final d in recent)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(d.common),
                subtitle: Text('${d.sci} · ${specById(d.model)?.family ?? d.model}'),
                trailing: Text('${hms(d.at)}\n${(d.confidence * 100).round()}%',
                    textAlign: TextAlign.right),
              ),
          ],
        );
      },
    );
  }
}
