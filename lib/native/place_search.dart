import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:latlong2/latlong.dart' hide Path;

import '../main.dart' show ink, madder, paper, paperDeep, sepia, serif;

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

/// Photon's answer as places. Its extent is two corners, in no stated
/// order, so it is read as the smallest and largest of each.
List<FoundPlace> placesOf(Map<String, dynamic> j) {
  final out = <FoundPlace>[];
  for (final f in (j['features'] as List?) ?? const []) {
    final m = f as Map<String, dynamic>;
    final p = (m['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
    final c = ((m['geometry'] as Map?)?['coordinates'] as List?)?.cast<num>();
    if (c == null || c.length < 2) continue;
    final name = (p['name'] ?? p['street'] ?? '') as String;
    if (name.isEmpty) continue;
    final parts = <String>[];
    for (final k in ['city', 'county', 'state', 'country']) {
      final v = p[k];
      if (v is String && v.isNotEmpty && v != name && !parts.contains(v)) parts.add(v);
    }
    final e = (p['extent'] as List?)?.cast<num>();
    out.add(FoundPlace(
      name,
      parts.join(', '),
      LatLng(c[1].toDouble(), c[0].toDouble()),
      west: e != null && e.length == 4 ? math.min(e[0], e[2]).toDouble() : null,
      east: e != null && e.length == 4 ? math.max(e[0], e[2]).toDouble() : null,
      south: e != null && e.length == 4 ? math.min(e[1], e[3]).toDouble() : null,
      north: e != null && e.length == 4 ? math.max(e[1], e[3]).toDouble() : null,
    ));
  }
  return out;
}

/// Ask Photon (komoot, OpenStreetMap data) for [q], nearest [near] first.
Future<List<FoundPlace>> searchPlaces(String q, LatLng near) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.https('photon.komoot.io', '/api', {
      'q': q,
      'limit': '6',
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
    const box = BoxDecoration(color: paper, border: Border.fromBorderSide(BorderSide(color: paperDeep)));
    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 31,
            decoration: box,
            child: Row(children: [
              const Padding(
                padding: EdgeInsetsDirectional.only(start: 7, end: 4),
                child: Icon(Icons.search, size: 16, color: sepia),
              ),
              Expanded(
                child: CallbackShortcuts(
                  bindings: {const SingleActivator(LogicalKeyboardKey.escape): _clear},
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    onChanged: _typed,
                    onSubmitted: (_) {
                      if (_found.isNotEmpty) _pick(_found.first);
                    },
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontFamily: serif, fontSize: 15, color: ink, height: 1.2),
                    cursorColor: madder,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Search for a place',
                      hintStyle: TextStyle(fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 15, color: sepia),
                      contentPadding: EdgeInsets.symmetric(vertical: 7),
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
                      child: Text('×', style: TextStyle(fontSize: 18, height: 1, color: sepia)),
                    ),
                  ),
                ),
            ]),
          ),
          if (_found.isNotEmpty || (_note != null && _focus.hasFocus))
            Container(
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
                  for (final p in _found)
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
    );
  }
}
