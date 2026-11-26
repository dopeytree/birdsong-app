import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_symbols_icons/symbols.dart';

import '../main.dart' show paperDeep;
import '../native/station_archive.dart';
import '../settings.dart';

/// Settings' Station history: for each saved station, how many of its days
/// are kept on this device (station_archive.dart) and the latest lines of
/// its fill-log.txt, newest first, read again every two seconds while
/// open, so the filling in can be watched.
class StationHistory extends StatefulWidget {
  const StationHistory({super.key, required this.root, required this.stations});

  /// The app's data folder, where stations/ is.
  final Directory root;
  final List<Station> stations;

  @override
  State<StationHistory> createState() => _StationHistoryState();
}

class _Seen {
  const _Seen({this.kept = 0, this.counted = 0, this.calls = 0, this.oldest, this.lines = const []});

  /// Days with every call kept, and days only counted for the calendar.
  final int kept;
  final int counted;
  final int calls;
  final String? oldest;

  /// The log's latest lines, newest first.
  final List<String> lines;
}

class _StationHistoryState extends State<StationHistory> {
  final Map<String, _Seen> _seen = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _read();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _read());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Directory _dir(Station st) =>
      Directory('${widget.root.path}/stations/${StationArchive.safeName(st.id)}');

  Future<void> _read() async {
    final got = <String, _Seen>{};
    for (final st in widget.stations) {
      final dir = _dir(st);
      var kept = 0, counted = 0, calls = 0;
      String? oldest;
      var lines = const <String>[];
      try {
        final days = File('${dir.path}/days.json');
        if (await days.exists()) {
          final j = jsonDecode(await days.readAsString());
          if (j is Map) {
            for (final e in j.entries) {
              final k = e.value is Map ? StationDay.fromJson(Map<String, dynamic>.from(e.value as Map)) : null;
              if (k == null) continue;
              if (k.saved) {
                kept++;
                calls += k.calls;
                if (oldest == null || '${e.key}'.compareTo(oldest) < 0) oldest = '${e.key}';
              } else {
                counted++;
              }
            }
          }
        }
        final log = File('${dir.path}/fill-log.txt');
        if (await log.exists()) {
          final all = (await log.readAsString()).trimRight().split('\n');
          lines = all.reversed.take(60).toList();
        }
      } catch (_) {}
      got[st.id] = _Seen(kept: kept, counted: counted, calls: calls, oldest: oldest, lines: lines);
    }
    if (mounted) setState(() => _seen..clear()..addAll(got));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.stations.isEmpty) {
      return Text('No stations saved.', style: theme.textTheme.bodySmall);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final st in widget.stations) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Text(st.name, style: theme.textTheme.titleSmall),
          ),
          Text(_summary(_seen[st.id]), style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Container(
            height: 200,
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: paperDeep.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(12),
            ),
            child: (_seen[st.id]?.lines ?? const []).isEmpty
                ? Text('Nothing yet. Days are kept while the station is shown on the plate.',
                    style: theme.textTheme.bodySmall)
                : ListView(
                    children: [
                      for (final l in _seen[st.id]!.lines)
                        Text(l, style: const TextStyle(fontFamily: 'Menlo', fontSize: 11, height: 1.35)),
                    ],
                  ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () async {
                final f = File('${_dir(st).path}/fill-log.txt');
                final text = await f.exists() ? await f.readAsString() : '';
                await Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('The log is copied.')));
                }
              },
              icon: const Icon(Symbols.content_copy, size: 16),
              label: const Text('Copy the log'),
            ),
          ),
        ],
      ],
    );
  }

  String _summary(_Seen? s) {
    if (s == null) return 'Reading…';
    if (s.kept == 0 && s.counted == 0) return 'No days kept yet.';
    final kept = s.kept == 1 ? '1 day kept' : '${s.kept} days kept';
    final back = s.oldest == null ? '' : ', back to ${s.oldest}';
    final more = s.counted == 0 ? '' : '; ${s.counted} more counted for the calendar';
    return '$kept (${s.calls} calls)$back$more.';
  }
}
