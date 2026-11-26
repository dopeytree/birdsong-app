import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../engine/place_names.dart';
import '../main.dart' show caps, ink, madder, paper, rule, sepia, serif;
import '../store/detection_store.dart';
import '../ui/format.dart';
import '../ui/paper_surface.dart';
import 'index_view.dart' show thousands;
import 'station_archive.dart';
import 'station_feed.dart';
import 'walk_names.dart';

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Modern, compact, auto-fitting month grid shared by [DayPicker] and
/// [StationDayPicker]. Takes ~215 px vertically so sessions are always visible
/// immediately below on phones (and side-by-side on tablets/desktop).
class _CompactMonthGrid extends StatelessWidget {
  const _CompactMonthGrid({
    required this.month,
    required this.selected,
    required this.today,
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
    required this.isSelectable,
    required this.hasDot,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool Function(DateTime d) isSelectable;
  final bool Function(DateTime d) hasDot;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = (firstOfMonth.weekday - DateTime.monday) % 7;
    final totalCells = leadingBlanks + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
              padding: EdgeInsets.zero,
              iconSize: 20,
              color: ink,
              icon: const Icon(Symbols.chevron_left),
              onPressed: canPrev
                  ? () {
                      hapticTap();
                      onPrev();
                    }
                  : null,
            ),
            Expanded(
              child: Text(
                '${_monthNames[month.month - 1]} ${month.year}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: caps, fontSize: 14.5, letterSpacing: 0.7, color: ink),
              ),
            ),
            IconButton(
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
              padding: EdgeInsets.zero,
              iconSize: 20,
              color: ink,
              icon: const Icon(Symbols.chevron_right),
              onPressed: canNext
                  ? () {
                      hapticTap();
                      onNext();
                    }
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final wd in _weekdays)
              Expanded(
                child: Text(
                  wd,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: caps, fontSize: 11, color: sepia.withValues(alpha: 0.75)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: () {
                    final idx = r * 7 + c - leadingBlanks + 1;
                    if (idx < 1 || idx > daysInMonth) return const SizedBox(height: 32);
                    final d = DateTime(month.year, month.month, idx);
                    final sel = sameDay(d, selected);
                    final isToday = sameDay(d, today);
                    final ok = isSelectable(d);
                    final dot = hasDot(d);
                    return SizedBox(
                      height: 32,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        hoverColor: ink.withValues(alpha: 0.08),
                        onTap: ok
                            ? () {
                                hapticTap();
                                onSelect(d);
                              }
                            : null,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: sel
                                  ? const BoxDecoration(color: ink, shape: BoxShape.circle)
                                  : isToday
                                      ? BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: ink.withValues(alpha: 0.45)),
                                        )
                                      : null,
                              child: Text(
                                '$idx',
                                style: TextStyle(
                                  fontFamily: serif,
                                  fontSize: 13.5,
                                  color: sel
                                      ? paper
                                      : ok
                                          ? ink
                                          : sepia.withValues(alpha: 0.35),
                                ),
                              ),
                            ),
                            SizedBox(
                              height: 4,
                              child: dot && !sel
                                  ? Center(
                                      child: Container(
                                        width: 3.5,
                                        height: 3.5,
                                        decoration: const BoxDecoration(color: ink, shape: BoxShape.circle),
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    );
                  }(),
                ),
            ],
          ),
      ],
    );
  }
}

/// Modern responsive shell shared by [DayPicker] and [StationDayPicker]:
/// full-screen edge-to-edge on mobile (<= 720 px), translucent rounded dialog
/// matching the filter bar on tablets & desktop.
Widget _calendarFrame({
  required BuildContext context,
  required String title,
  required Widget body,
}) {
  final screen = MediaQuery.sizeOf(context);
  final pad = MediaQuery.paddingOf(context);
  final narrow = screen.width <= 720;
  final header = Row(
    children: [
      const SizedBox(width: 40),
      Expanded(
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: caps, fontSize: 17, letterSpacing: 1.0, color: ink),
        ),
      ),
      IconButton(
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        iconSize: 22,
        color: ink,
        icon: const Icon(Symbols.close),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  );
  if (narrow) {
    final topPad = pad.top > 24 ? math.max(16.0, pad.top - 16.0) : math.max(10.0, pad.top);
    final bottomPad = math.max(16.0, pad.bottom);
    return Dialog.fullscreen(
      backgroundColor: paper,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, topPad, 16, bottomPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 8),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
  return Dialog(
    backgroundColor: paper.withValues(alpha: 0.96),
    surfaceTintColor: Colors.transparent,
    elevation: 8,
    shadowColor: const Color(0x382A241C),
    insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: rule.withValues(alpha: 0.65)),
    ),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 680,
        maxHeight: screen.height * 0.88,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 8),
            Flexible(child: body),
          ],
        ),
      ),
    ),
  );
}

/// The calendar dialog for local walks: full-screen on phones, side-by-side
/// rounded modal on tablets/Mac, with rich delete confirmation.
class DayPicker extends StatefulWidget {
  const DayPicker({super.key, required this.store, required this.speciesIn, this.shown});

  final DetectionStore store;
  final int Function(Session) speciesIn;
  final Session? shown;

  static Future<Session?> show(BuildContext context, DayPicker picker) => showDialog<Session>(
        context: context,
        useSafeArea: false,
        barrierColor: const Color(0x662A241C),
        builder: (_) => picker,
      );

  @override
  State<DayPicker> createState() => _DayPickerState();
}

class _DayPickerState extends State<DayPicker> {
  List<Session> get _sessions => [
        for (final x in widget.store.sessions)
          if (x.live || widget.speciesIn(x) > 0) x,
      ];
  Set<DateTime> get _days => {for (final x in _sessions) _day(x.start)};
  late DateTime _picked = _sessions.isEmpty
      ? _day(DateTime.now())
      : _day(widget.shown?.start ?? _sessions.last.start);
  late DateTime _month = DateTime(_picked.year, _picked.month);

  List<Session> get _that => [for (final x in _sessions) if (sameDay(x.start, _picked)) x];

  String _placeLabel(Session x) {
    final town = !x.hasPlace
        ? 'Place unknown'
        : x.placeName == null
            ? place(x.lat!, x.lon!)
            : x.placeName!.isEmpty
                ? place(x.lat!, x.lon!)
                : x.placeName!;
    final area = x.placeArea ?? '';
    return area.isEmpty || area == town ? town : '$town – $area';
  }

  Future<void> _confirmDelete(Session x, int number) async {
    final detections = widget.store.inSession(x);
    final speciesNames = <String>[];
    final seen = <String>{};
    for (final d in detections) {
      if (seen.add(d.sci)) speciesNames.add(d.common);
    }
    speciesNames.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final when = x.end == null
        ? '${day(x.start)} · ${clock(x.start)}'
        : '${day(x.start)} · ${clock(x.start)}–${clock(x.end!)} (${lasting(x.end!.difference(x.start))})';
    final where = _placeLabel(x);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: paper,
        title: Text('Delete session #$number?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(when, style: const TextStyle(fontFamily: serif, fontSize: 15, color: ink)),
                const SizedBox(height: 4),
                Text(where, style: const TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 14, color: sepia)),
                const SizedBox(height: 10),
                Text(
                  speciesNames.isEmpty
                      ? 'No species detected.'
                      : '${speciesNames.length} species (${detections.length} calls):',
                  style: const TextStyle(fontFamily: caps, fontSize: 13, letterSpacing: 0.6, color: ink),
                ),
                if (speciesNames.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    speciesNames.join(', '),
                    style: const TextStyle(fontFamily: serif, fontSize: 14, height: 1.4, color: ink),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'This permanently deletes this walk, its detections, and its recordings. This cannot be undone.',
                  style: TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 13, color: sepia),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: madder, foregroundColor: paper),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.store.deleteSession(x);
    if (!mounted) return;
    setState(() {
      final days = _days;
      if (days.isNotEmpty && !days.contains(_picked)) {
        _picked = days.reduce((a, b) => a.isAfter(b) ? a : b);
        _month = DateTime(_picked.year, _picked.month);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (_sessions.isEmpty) return;
    widget.store.namePlaces(nearestPlace);
    widget.store.nameAreas(areaOfWalk);
  }

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 14.5, color: sepia);
    if (_days.isEmpty) {
      return _calendarFrame(
        context: context,
        title: 'Sessions',
        body: const Padding(
          padding: EdgeInsets.symmetric(vertical: 36),
          child: Text('Nothing recorded yet.', textAlign: TextAlign.center, style: small),
        ),
      );
    }

    final first = _days.reduce((a, b) => a.isBefore(b) ? a : b);
    final last = _days.reduce((a, b) => a.isAfter(b) ? a : b);
    final firstMonth = DateTime(first.year, first.month);
    final lastMonth = DateTime(last.year, last.month);
    final that = _that;
    final wide = MediaQuery.sizeOf(context).width > 720;

    final cal = _CompactMonthGrid(
      month: _month,
      selected: _picked,
      today: _day(DateTime.now()),
      canPrev: _month.isAfter(firstMonth),
      canNext: _month.isBefore(lastMonth),
      onPrev: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
      onNext: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
      isSelectable: (d) => _days.contains(d),
      hasDot: (d) => _days.contains(d),
      onSelect: (d) => setState(() => _picked = d),
    );

    final list = ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              that.length == 1 ? '1 session · ${day(_picked)}' : '${that.length} sessions · ${day(_picked)}',
              style: const TextStyle(fontFamily: caps, fontSize: 12.5, letterSpacing: 0.6, color: sepia),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (placeName, group) in _byPlace(_that)) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
                      child: Text(placeName,
                          style: const TextStyle(fontFamily: caps, fontSize: 13.5, letterSpacing: 0.6, color: ink)),
                    ),
                    for (final x in group) _session(x),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return _calendarFrame(
      context: context,
      title: 'Sessions',
      body: wide
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 280, child: cal),
                  const VerticalDivider(width: 24, color: rule),
                  Expanded(child: SizedBox(height: 290, child: list)),
                ],
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cal,
                const Divider(height: 16, color: rule),
                Flexible(child: list),
              ],
            ),
    );
  }

  List<(String, List<Session>)> _byPlace(List<Session> daySessions) {
    final groups = <String, List<Session>>{};
    for (final x in daySessions) {
      final name = _placeLabel(x);
      (groups[name] ??= []).add(x);
    }
    return [for (final e in groups.entries) (e.key, e.value)];
  }

  Widget _session(Session x) {
    final i = widget.store.sessions.indexOf(x);
    final on = widget.shown?.id == x.id;
    final when = x.live ? '${clock(x.start)}, live' : '${clock(x.start)} · ${lasting(x.end!.difference(x.start))}';
    final n = widget.speciesIn(x);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      hoverColor: ink.withValues(alpha: 0.08),
      onTap: () {
        hapticTap();
        Navigator.of(context).pop(x);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: rule.withValues(alpha: 0.55)))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 36,
              child: Text('#${i + 1}',
                  style: TextStyle(fontFamily: caps, fontSize: 13.5, color: on ? madder : sepia)),
            ),
            Expanded(
              child: Text(when, style: TextStyle(fontFamily: serif, fontSize: 15.5, color: on ? madder : ink)),
            ),
            Text(n == 1 ? '1 sp.' : '$n sp.',
                style: const TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 14, color: sepia)),
            if (!x.live)
              IconButton(
                constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                padding: EdgeInsets.zero,
                iconSize: 17,
                color: ink.withValues(alpha: 0.7),
                icon: const Icon(Symbols.delete),
                onPressed: () => _confirmDelete(x, i + 1),
              ),
          ],
        ),
      ),
    );
  }
}

/// The calendar dialog for a remote station, sharing the same compact modern
/// layout as [DayPicker].
class StationDayPicker extends StatefulWidget {
  const StationDayPicker({super.key, required this.feed, this.keepPast, this.onKeepPast});

  final StationFeed feed;
  final bool? keepPast;
  final ValueChanged<bool>? onKeepPast;

  static Future<DateTime?> show(BuildContext context, StationDayPicker picker) => showDialog<DateTime>(
        context: context,
        useSafeArea: false,
        barrierColor: const Color(0x662A241C),
        builder: (_) => picker,
      );

  @override
  State<StationDayPicker> createState() => _StationDayPickerState();
}

class _StationDayPickerState extends State<StationDayPicker> {
  late final DateTime _today = _day(DateTime.now());
  late DateTime _picked = widget.feed.day ?? _today;
  late DateTime _month = DateTime(_picked.year, _picked.month);
  late bool? _keep = widget.keepPast;

  @override
  void initState() {
    super.initState();
    widget.feed.archive?.markMonth(_picked);
  }

  void _stepMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    setState(() => _month = next);
    widget.feed.archive?.markMonth(next);
  }

  @override
  Widget build(BuildContext context) {
    final since = widget.feed.since;
    final first = since == null ? DateTime(_today.year - 2, _today.month, _today.day) : _day(since);
    final firstMonth = DateTime(first.year, first.month);
    final lastMonth = DateTime(_today.year, _today.month);
    final archive = widget.feed.archive;
    const small = TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 13.5, color: sepia);
    final shown = _picked.isBefore(first) ? first : _picked;
    final wide = MediaQuery.sizeOf(context).width > 720;

    return _calendarFrame(
      context: context,
      title: widget.feed.station.name,
      body: ListenableBuilder(
        listenable: archive ?? widget.feed,
        builder: (context, _) {
          final cal = _CompactMonthGrid(
            month: _month,
            selected: shown,
            today: _today,
            canPrev: _month.isAfter(firstMonth),
            canNext: _month.isBefore(lastMonth),
            onPrev: () => _stepMonth(-1),
            onNext: () => _stepMonth(1),
            isSelectable: (d) {
              if (d.isBefore(first) || d.isAfter(_today)) return false;
              final k = archive?.dayOf(d);
              return k == null || k.calls > 0 || sameDay(d, shown);
            },
            hasDot: (d) {
              final k = archive?.dayOf(d);
              return k != null && k.calls > 0;
            },
            onSelect: (d) => setState(() => _picked = d),
          );

          final details = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _row(shown, archive?.dayOf(shown)),
              if (archive != null && _keep == null && widget.onKeepPast != null)
                _ask(archive)
              else if (archive != null) ...[
                const SizedBox(height: 8),
                Text(_kept(archive), textAlign: TextAlign.center, style: small),
              ],
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: ink, foregroundColor: paper),
                  onPressed: () => Navigator.of(context).pop(shown),
                  child: const Text('Open day'),
                ),
              ),
            ],
          );

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 280, child: cal),
                const VerticalDivider(width: 24, color: rule),
                Expanded(child: details),
              ],
            );
          }
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cal,
                const Divider(height: 16, color: rule),
                details,
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _row(DateTime d, StationDay? k) {
    final on = widget.feed.day == d || (widget.feed.day == null && d == _today && widget.feed.span == Span.today);
    final what = k == null
        ? 'asking…'
        : k.calls == 0
            ? 'nothing heard'
            : '${k.species == 1 ? '1 species' : '${k.species} species'}, '
                '${k.calls == 1 ? '1 call' : '${thousands(k.calls)} calls'}';
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      hoverColor: ink.withValues(alpha: 0.08),
      onTap: () => Navigator.of(context).pop(d),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: rule.withValues(alpha: 0.55)))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(d == _today ? 'Today' : dayWords(d),
                  style: TextStyle(fontFamily: serif, fontSize: 16.5, color: on ? madder : ink)),
            ),
            if (k != null && k.saved)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Symbols.download_done, size: 15, color: ink),
              ),
            Text(what, style: const TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 14.5, color: sepia)),
          ],
        ),
      ),
    );
  }

  Widget _ask(StationArchive a) {
    final since = widget.feed.since;
    final back = since == null ? null : _today.difference(_day(since)).inDays;
    void answer(bool v) {
      setState(() => _keep = v);
      widget.onKeepPast?.call(v);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Keep ${widget.feed.station.name}\'s past days on this phone? '
            '${back == null ? 'Every day back to when its records begin' : 'About ${thousands(back)} days'}, '
            'fetched quietly while the station is shown, so they open without it. '
            'Days you open are kept either way.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 13.5, color: sepia),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(onPressed: () => answer(false), child: const Text('Not now')),
              TextButton(onPressed: () => answer(true), child: const Text('Keep them')),
            ],
          ),
        ],
      ),
    );
  }

  String _kept(StationArchive a) {
    if (a.unsupported) return "This station can't list a day's calls, so only its counts are kept.";
    final n = a.days.values.where((k) => k.saved && k.calls > 0).length;
    final past = _keep == true ? '' : ' Its past days are kept as you open them.';
    return n == 0
        ? 'Keeping its days on this device as they are shown.'
        : '${thousands(n)} ${n == 1 ? 'day' : 'days'} kept on this device.$past';
  }
}
