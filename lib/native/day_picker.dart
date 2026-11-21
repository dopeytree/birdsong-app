import 'package:flutter/material.dart';

import '../main.dart' show caps, ink, madder, paper, rule, sepia, serif;
import '../engine/place_names.dart';
import 'index_view.dart' show thousands;
import 'station_archive.dart';
import 'station_feed.dart';
import '../store/detection_store.dart';
import '../ui/format.dart';

/// The calendar button's dialog: a month with only the days that have a
/// session to pick, and under it that day's sessions, grouped under the
/// nearest town or village (named from OpenStreetMap, saved with each
/// session; sessions not yet named are named while it is open), each with
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
  List<Session> get _sessions => widget.store.sessions;
  late final Set<DateTime> _days = {for (final x in _sessions) _day(x.start)};
  late DateTime _picked = _day(widget.shown?.start ?? _sessions.last.start);

  List<Session> get _that => [for (final x in _sessions) if (sameDay(x.start, _picked)) x];

  @override
  void initState() {
    super.initState();
    // name the places of sessions that have none yet; the list follows
    widget.store.namePlaces(nearestPlace);
  }

  @override
  Widget build(BuildContext context) {
    final first = _days.reduce((a, b) => a.isBefore(b) ? a : b);
    final last = _days.reduce((a, b) => a.isAfter(b) ? a : b);
    final that = _that;
    final screen = MediaQuery.sizeOf(context);
    const small = TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 15, color: sepia);
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
      final name = !x.hasPlace
          ? 'Place unknown'
          : x.placeName == null
              ? place(x.lat!, x.lon!) // being named
              : x.placeName!.isEmpty
                  ? place(x.lat!, x.lon!)
                  : x.placeName!;
      (groups[name] ??= []).add(x);
    }
    return [for (final e in groups.entries) (e.key, e.value)];
  }

  /// "#3  07:42 for 38m  ·  12 species", the one on show in madder.
  Widget _session(Session x) {
    final i = _sessions.indexOf(x);
    final on = widget.shown?.id == x.id;
    final when = x.live ? '${clock(x.start)}, listening now' : '${clock(x.start)} for ${lasting(x.end!.difference(x.start))}';
    final n = widget.speciesIn(x);
    return InkWell(
      onTap: () => Navigator.of(context).pop(x),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: rule))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
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
  const StationDayPicker({super.key, required this.feed});

  final StationFeed feed;

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
                    if (archive != null) ...[
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

  /// How many of the station's days are kept on the phone.
  String _kept(StationArchive a) {
    if (a.unsupported) return "This station can't list a day's calls, so only its counts are kept.";
    final n = a.days.values.where((k) => k.saved && k.calls > 0).length;
    return n == 0 ? 'Keeping its days on this phone as they are shown.' : '${thousands(n)} ${n == 1 ? 'day' : 'days'} kept on this phone.';
  }
}
