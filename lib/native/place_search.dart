import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:latlong2/latlong.dart' hide Path;

import '../main.dart' show ink, paper, paperDeep, sepia, serif;

/// A place found by the map's search: its name, a line saying where it is,
/// its point, and its extent when it has one.
class FoundPlace {
  const FoundPlace(this.name, this.where, this.at, {this.south, this.west, this.north, this.east});

  final String name;

  /// "Glastonbury, Somerset, England".
  final String where;
  final LatLng at;
  final double? south, west, north, east;

  bool get hasExtent => south != null && west != null && north != null && east != null && north! > south! && east! > west!;
}

/// Shops, streets and other built things. Not a place to walk to.
const _builtKeys = {
  'amenity',
  'shop',
  'office',
  'craft',
  'healthcare',
  'building',
  'highway',
  'railway',
  'public_transport',
  'aeroway',
  'emergency',
  'man_made',
  'power',
  'club',
};

/// Nature and land, shown after a named place and before the rest.
const _natureKeys = {
  'natural',
  'water',
  'waterway',
  'leisure',
  'boundary',
  'landuse',
  'historic',
  'mountain_pass',
};

/// 0 a named place, 1 nature (including a viewpoint), 2 anything else kept.
/// -1 is a shop, a street, a house number, or other built thing, dropped.
int _rankOf(Map<String, dynamic> p) {
  if (p.containsKey('housenumber')) return -1;
  final key = p['osm_key'];
  if (key is! String) return 2;
  if (key == 'place') return 0;
  if (key == 'tourism') return p['osm_value'] == 'viewpoint' ? 1 : -1;
  if (_natureKeys.contains(key)) return 1;
  if (_builtKeys.contains(key)) return -1;
  return 2;
}

/// Photon's answer as places. Its extent is two corners, in no stated
/// order, so it is read as the smallest and largest of each. One place of
/// each name and where: Photon gives a town's point, its boundary and its
/// parish separately, which read the same; the first (its best) is kept.
///
/// Results are nature and places, not shops. Dropped: an `osm_key` of
/// amenity, shop, office, craft, healthcare, building, highway, railway,
/// public_transport, aeroway, emergency, man_made, power, club, or tourism
/// (except tourism=viewpoint), and any feature with a house number. What
/// remains is ranked, Photon's own order kept within each rank: `place`
/// first (isles, islands, towns, villages, cities, hamlets, localities —
/// every place value), then nature (natural, water, waterway, leisure,
/// boundary, landuse, historic, mountain_pass, a viewpoint), then anything
/// else not dropped.
List<FoundPlace> placesOf(Map<String, dynamic> j) {
  // 0 named places, 1 nature, 2 the rest.
  final bands = [<FoundPlace>[], <FoundPlace>[], <FoundPlace>[]];
  final seen = <String>{};
  for (final f in (j['features'] as List?) ?? const []) {
    final m = f as Map<String, dynamic>;
    final p = (m['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rank = _rankOf(p);
    if (rank < 0) continue;
    final c = ((m['geometry'] as Map?)?['coordinates'] as List?)?.cast<num>();
    if (c == null || c.length < 2) continue;
    final name = (p['name'] ?? p['street'] ?? '') as String;
    if (name.isEmpty) continue;
    final parts = <String>[];
    for (final k in ['city', 'county', 'state', 'country']) {
      final v = p[k];
      if (v is String && v.isNotEmpty && v != name && !parts.contains(v)) parts.add(v);
    }
    if (!seen.add('${name.toLowerCase()}|${parts.join(', ').toLowerCase()}')) continue;
    final e = (p['extent'] as List?)?.cast<num>();
    bands[rank].add(FoundPlace(
      name,
      parts.join(', '),
      LatLng(c[1].toDouble(), c[0].toDouble()),
      west: e != null && e.length == 4 ? math.min(e[0], e[2]).toDouble() : null,
      east: e != null && e.length == 4 ? math.max(e[0], e[2]).toDouble() : null,
      south: e != null && e.length == 4 ? math.min(e[1], e[3]).toDouble() : null,
      north: e != null && e.length == 4 ? math.max(e[1], e[3]).toDouble() : null,
    ));
  }
  return [...bands[0], ...bands[1], ...bands[2]];
}

/// Ask Photon (komoot, OpenStreetMap data) for [q], nearest [near] first.
/// Twenty-five are asked for, so dropping shops still leaves enough; the
/// list shows 6.
Future<List<FoundPlace>> searchPlaces(String q, LatLng near) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.https('photon.komoot.io', '/api', {
      'q': q,
      'limit': '25',
      'lang': 'en',
      'lat': near.latitude.toStringAsFixed(4),
      'lon': near.longitude.toStringAsFixed(4),
    }));
    req.headers.set(HttpHeaders.userAgentHeader, 'Birdsong/0.1 github.com/dopeytree/birdsong');
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw HttpException('${res.statusCode}');
    return placesOf(jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>);
  } finally {
    client.close();
  }
}

/// The map's search, floating at its top right: suggestions as you type
/// (from three letters, after a pause), Enter takes the first, Escape or ×
/// clears. [near] is where to look first; [onPick] moves the map.
class PlaceSearch extends StatefulWidget {
  const PlaceSearch({super.key, required this.width, required this.near, required this.onPick});

  final double width;
  final LatLng Function() near;
  final ValueChanged<FoundPlace> onPick;

  @override
  State<PlaceSearch> createState() => _PlaceSearchState();
}

class _PlaceSearchState extends State<PlaceSearch> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  Timer? _wait;
  int _run = 0;
  List<FoundPlace> _found = const [];
  String? _note;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && mounted) setState(() => _found = const []);
    });
  }

  @override
  void dispose() {
    _wait?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _typed(String q) {
    _wait?.cancel();
    if (q.trim().length < 3) {
      _run++;
      setState(() {
        _found = const [];
        _note = null;
      });
      return;
    }
    _wait = Timer(const Duration(milliseconds: 350), () => _ask(q.trim()));
  }

  Future<void> _ask(String q) async {
    final run = ++_run;
    try {
      final found = await searchPlaces(q, widget.near());
      if (!mounted || run != _run) return;
      setState(() {
        _found = found;
        _note = found.isEmpty ? 'Nowhere of that name.' : null;
      });
    } catch (_) {
      if (!mounted || run != _run) return;
      setState(() {
        _found = const [];
        _note = "Search couldn't be reached.";
      });
    }
  }

  void _pick(FoundPlace p) {
    _text.text = p.name;
    _focus.unfocus();
    setState(() => _found = const []);
    widget.onPick(p);
  }

  void _clear() {
    _wait?.cancel();
    _run++;
    _text.clear();
    setState(() {
      _found = const [];
      _note = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Engraved label: warm grey, a paper hairline inset, no hard outer border.
    // The list below stays paper, with the same slight radius.
    const bar = BoxDecoration(
      color: Color(0xFF8C877D),
      borderRadius: BorderRadius.all(Radius.circular(4)),
      boxShadow: [BoxShadow(color: Color(0x6B3C280A), offset: Offset(0, 3), blurRadius: 10)],
    );
    const box = BoxDecoration(
      color: paper,
      borderRadius: BorderRadius.all(Radius.circular(4)),
      border: Border.fromBorderSide(BorderSide(color: paperDeep)),
    );
    // TextFieldTapRegion: a click on a suggestion counts as inside the field,
    // so the field keeps its focus (and the list stays) until the tap lands.
    return TextFieldTapRegion(
      child: SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 31,
            decoration: bar,
            child: Stack(fit: StackFit.expand, children: [
            Row(children: [
              const Padding(
                padding: EdgeInsetsDirectional.only(start: 7, end: 4),
                child: Icon(Icons.search, size: 16, color: paper),
              ),
              Expanded(
                child: CallbackShortcuts(
                  bindings: {const SingleActivator(LogicalKeyboardKey.escape): _clear},
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    // A tap that focuses the field clears the last place, so
                    // typing starts fresh. A tap while it already has focus
                    // (moving the cursor) leaves the text.
                    onTap: () {
                      if (!_focus.hasFocus) _clear();
                    },
                    onChanged: _typed,
                    onSubmitted: (_) {
                      if (_found.isNotEmpty) _pick(_found.first);
                    },
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontFamily: serif, fontSize: 15, color: paper, height: 1.2),
                    cursorColor: paper,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Search for a place',
                      hintStyle: TextStyle(
                        fontFamily: serif,
                        fontStyle: FontStyle.italic,
                        fontSize: 15,
                        letterSpacing: 0.3,
                        color: paper.withValues(alpha: 0.85),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 7),
                    ),
                  ),
                ),
              ),
              if (_text.text.isNotEmpty)
                Semantics(
                  button: true,
                  label: 'Clear the search',
                  child: InkResponse(
                    radius: 16,
                    onTap: _clear,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('×', style: TextStyle(fontSize: 18, height: 1, color: paper)),
                    ),
                  ),
                ),
            ]),
            const Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.all(2),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(3)),
                      border: Border.fromBorderSide(BorderSide(color: Color(0x8CEEE5CE), width: 0.8)),
                    ),
                    child: SizedBox.expand(),
                  ),
                ),
              ),
            ),
            ]),
          ),
          if (_found.isNotEmpty || (_note != null && _focus.hasFocus))
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: box.copyWith(boxShadow: const [BoxShadow(color: Color(0x2E3C280A), offset: Offset(0, 6), blurRadius: 18)]),
              margin: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_found.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                      child: Text(_note!,
                          style: const TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 14, color: sepia)),
                    ),
                  for (final p in _found.take(6))
                    InkWell(
                      onTap: () => _pick(p),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 5, 10, 6),
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: p.name, style: const TextStyle(color: ink)),
                            if (p.where.isNotEmpty)
                              TextSpan(
                                  text: '  ${p.where}',
                                  style: const TextStyle(color: sepia, fontStyle: FontStyle.italic, fontSize: 13)),
                          ]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: serif, fontSize: 15, height: 1.3),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
      ),
    );
  }
}
