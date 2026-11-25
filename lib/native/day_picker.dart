import 'package:flutter/material.dart';

import '../main.dart' show caps, ink, madder, paper, rule, sepia, serif;
import '../engine/place_names.dart';
import 'index_view.dart' show thousands;
import 'station_archive.dart';
import 'station_feed.dart';
import 'walk_names.dart';
import '../store/detection_store.dart';
import '../ui/format.dart';

/// The calendar button's dialog: a month with only the days that have a
/// session to pick, and under it that day's sessions, grouped under the
/// nearest town or village (named from OpenStreetMap, saved with each
/// session; sessions not yet named are named while it is open) and where
/// the walk went ("Ashcott – RSPB Ham Wall", walk_names.dart), each with
/// its number, start time, how long it ran and how many species it heard. A tap on a
/// session shows it; OK shows the day's first, and the ‹ › step through the
/// rest. Returns the session to show, or null.
///
/// A simple way in for now; the calendar can say more about each day later.
class DayPicker extends StatefulWidget {
  const DayPicker({super.key, required this.store, required this.speciesIn, this.shown});

  /// Where the sessions are (oldest first), and where their names are saved.
  final DetectionStore store;

  /// How many species the plate draws for a session.
  final int Function(Session) speciesIn;

  /// The session on show now: its day opens first, and it is marked.
  final Session? shown;

  static Future<Session?> show(BuildContext context, DayPicker picker) => showDialog<Session>(
        context: context,
        barrierColor: const Color(0x8C2A241C),
        builder: (_) => picker,
      );

  @override
  State<DayPicker> createState() => _DayPickerState();
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

class _DayPickerState extends State<DayPicker> {
  List<Session> get _sessions => [
        for (final x in widget.store.sessions)
          if (x.live || widget.speciesIn(x) > 0) x,
      ];
  Set<DateTime> get _days => {for (final x in _sessions) _day(x.start)};
  late DateTime _picked = _sessions.isEmpty
      ? _day(DateTime.now())
      : _day(widget.shown?.start ?? _sessions.last.start);

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
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Delete')),
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
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (_sessions.isEmpty) return;
    // name the places of sessions that have none yet; the list follows
    widget.store.namePlaces(nearestPlace);
    // and where each walk went (a reserve, wood or heath)
    widget.store.nameAreas(areaOfWalk);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    const small = TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 15, color: sepia);
    if (_days.isEmpty) {
      return Dialog(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: screen.width * .04, vertical: screen.height * .04),
        shape: const RoundedRectangleBorder(side: BorderSide(color: sepia)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 400, maxHeight: screen.height * .92),
          child: Stack(
            children: [
              const Positioned.fill(
                child: IgnorePointer(
                  child: Padding(
                    padding: EdgeInsets.all(6),
                    child: DecoratedBox(
                        decoration: BoxDecoration(border: Border.fromBorderSide(BorderSide(color: rule)))),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Sessions on',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: caps, fontSize: 18, letterSpacing: 1.1, color: ink)),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Text('Nothing recorded yet.', textAlign: TextAlign.center, style: small),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final first = _days.reduce((a, b) => a.isBefore(b) ? a : b);
    final last = _days.reduce((a, b) => a.isAfter(b) ? a : b);
    final that = _that;
    return Dialog(
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: screen.width * .04, vertical: screen.height * .04),
      shape: const RoundedRectangleBorder(side: BorderSide(color: sepia)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 400, maxHeight: screen.height * .92),
        child: Stack(
          children: [
            // the page's dialogs: a rule just inside the edge
            const Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: DecoratedBox(decoration: BoxDecoration(border: Border.fromBorderSide(BorderSide(color: rule)))),
                ),
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Sessions on',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: caps, fontSize: 18, letterSpacing: 1.1, color: ink)),
                  SizedBox(
                    height: 352,
                    child: CalendarDatePicker(
                      initialDate: _picked,
                      firstDate: first,
                      lastDate: last,
                      currentDate: _day(DateTime.now()),
                      selectableDayPredicate: (d) => _days.contains(_day(d)),
                      onDateChanged: (d) => setState(() => _picked = _day(d)),
                    ),
                  ),
                  const Divider(color: rule, height: 1),
                  const SizedBox(height: 8),
                  Text(
                    that.length == 1 ? '1 session on ${day(_picked)}' : '${that.length} sessions on ${day(_picked)}',
                    textAlign: TextAlign.center,
                    style: small,
                  ),
                  const SizedBox(height: 4),
                  ListenableBuilder(
                    listenable: widget.store,
                    builder: (context, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (place, group) in _byPlace(_that)) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 10, 6, 2),
                            child: Text(place,
                                style: const TextStyle(
                                    fontFamily: caps, fontSize: 16, letterSpacing: 16 * .06, color: ink)),
                          ),
                          for (final x in group) _session(x),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                      TextButton(
                        onPressed: that.isEmpty ? null : () => Navigator.of(context).pop(that.first),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The day's sessions under their places, in the order the places were
  /// first visited that day.
  List<(String, List<Session>)> _byPlace(List<Session> day) {
    final groups = <String, List<Session>>{};
    for (final x in day) {
      final town = !x.hasPlace
          ? 'Place unknown'
          : x.placeName == null
              ? place(x.lat!, x.lon!) // being named
              : x.placeName!.isEmpty
                  ? place(x.lat!, x.lon!)
                  : x.placeName!;
      final area = x.placeArea ?? '';
      // "Ashcott – RSPB Ham Wall"; not "Shapwick – Shapwick"
      final name = area.isEmpty || area == town ? town : '$town – $area';
      (groups[name] ??= []).add(x);
    }
    return [for (final e in groups.entries) (e.key, e.value)];
  }

  /// "#3  07:42 for 38m  ·  12 species", the one on show in madder.
  Widget _session(Session x) {
    final i = widget.store.sessions.indexOf(x);
    final on = widget.shown?.id == x.id;
    final when = x.live ? '${clock(x.start)}, listening now' : '${clock(x.start)} for ${lasting(x.end!.difference(x.start))}';
    final n = widget.speciesIn(x);
    return InkWell(
      onTap: () => Navigator.of(context).pop(x),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: rule))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 44,
              child: Text('#${i + 1}',
                  style: TextStyle(fontFamily: caps, fontSize: 15, color: on ? madder : sepia)),
            ),
            Expanded(
              child: Text(when, style: TextStyle(fontFamily: serif, fontSize: 17, color: on ? madder : ink)),
            ),
            Text(n == 1 ? '1 species' : '$n species',
                style: const TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 15, color: sepia)),
            if (!x.live)
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.only(left: 6),
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                iconSize: 18,
                color: sepia,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(x, i + 1),
              ),
          ],
        ),
      ),
    );
  }
}

/// The calendar button on a remote station: any day from when its records
/// begin (as far as it says) to today, each day like one of Listen's
/// sessions. Days known to have heard nothing are greyed; under the month,
/// the picked day's row: how many species and calls, and whether it is kept
/// on the phone (station_archive.dart). Returns the day picked, or null.
class StationDayPicker extends StatefulWidget {
  const StationDayPicker({super.key, required this.feed, this.keepPast, this.onKeepPast});

  final StationFeed feed;

  /// Whether the station's past days are filled in on this device; null on
  /// a phone not yet asked, when the calendar asks, and [onKeepPast] hears.
  final bool? keepPast;
  final ValueChanged<bool>? onKeepPast;

  static Future<DateTime?> show(BuildContext context, StationDayPicker picker) => showDialog<DateTime>(
        context: context,
        barrierColor: const Color(0x8C2A241C),
        builder: (_) => picker,
      );

  @override
  State<StationDayPicker> createState() => _StationDayPickerState();
}

class _StationDayPickerState extends State<StationDayPicker> {
  late final DateTime _today = _day(DateTime.now());
  late DateTime _picked = widget.feed.day ?? _today;
  late bool? _keep = widget.keepPast;

  @override
  void initState() {
    super.initState();
    widget.feed.archive?.markMonth(_picked);
  }

  @override
  Widget build(BuildContext context) {
    final since = widget.feed.since;
    final first = since == null ? DateTime(_today.year - 2, _today.month, _today.day) : _day(since);
    final archive = widget.feed.archive;
    final screen = MediaQuery.sizeOf(context);
    const small = TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 15, color: sepia);
    final shown = _picked.isBefore(first) ? first : _picked;
    return Dialog(
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: screen.width * .04, vertical: screen.height * .04),
      shape: const RoundedRectangleBorder(side: BorderSide(color: sepia)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 400, maxHeight: screen.height * .92),
        child: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: DecoratedBox(decoration: BoxDecoration(border: Border.fromBorderSide(BorderSide(color: rule)))),
                ),
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
              child: ListenableBuilder(
                listenable: archive ?? widget.feed,
                builder: (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.feed.station.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontFamily: caps, fontSize: 18, letterSpacing: 1.1, color: ink)),
                    SizedBox(
                      height: 352,
                      child: CalendarDatePicker(
                        initialDate: shown,
                        firstDate: first,
                        lastDate: _today,
                        currentDate: _today,
                        // a day known to have heard nothing can't be picked
                        // (the one picked always can)
                        selectableDayPredicate: (d) {
                          final k = archive?.dayOf(d);
                          return k == null || k.calls > 0 || _day(d) == shown;
                        },
                        onDisplayedMonthChanged: (m) => archive?.markMonth(m),
                        onDateChanged: (d) => setState(() => _picked = _day(d)),
                      ),
                    ),
                    const Divider(color: rule, height: 1),
                    const SizedBox(height: 8),
                    _row(shown, archive?.dayOf(shown)),
                    if (archive != null && _keep == null && widget.onKeepPast != null)
                      _ask(archive)
                    else if (archive != null) ...[
                      const SizedBox(height: 6),
                      Text(_kept(archive), textAlign: TextAlign.center, style: small.copyWith(fontSize: 13)),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.of(context).pop(shown), child: const Text('OK')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The day as one of Listen's session rows: "Sat 21 Nov  ·  17 species,
  /// 412 calls", in madder when it is the day on show; a tap shows it.
  Widget _row(DateTime d, StationDay? k) {
    final on = widget.feed.day == d || (widget.feed.day == null && d == _today && widget.feed.span == Span.today);
    final what = k == null
        ? 'asking…'
        : k.calls == 0
            ? 'nothing heard'
            : '${k.species == 1 ? '1 species' : '${k.species} species'}, '
                '${k.calls == 1 ? '1 call' : '${thousands(k.calls)} calls'}';
    return InkWell(
      onTap: () => Navigator.of(context).pop(d),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: rule))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(d == _today ? 'Today' : dayWords(d),
                  style: TextStyle(fontFamily: serif, fontSize: 17, color: on ? madder : ink)),
            ),
            if (k != null && k.saved)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.download_done, size: 15, color: sepia),
              ),
            Text(what, style: const TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 15, color: sepia)),
          ],
        ),
      ),
    );
  }

  /// A phone asks once before filling in a station's past days: each is a
  /// request to the station and a little room on the phone.
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
            style: const TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 14, color: sepia),
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

  /// How many of the station's days are kept on this device.
  String _kept(StationArchive a) {
    if (a.unsupported) return "This station can't list a day's calls, so only its counts are kept.";
    final n = a.days.values.where((k) => k.saved && k.calls > 0).length;
    final past = _keep == true ? '' : ' Its past days are kept as you open them.';
    return n == 0
        ? 'Keeping its days on this device as they are shown.'
        : '${thousands(n)} ${n == 1 ? 'day' : 'days'} kept on this device.$past';
  }
}
