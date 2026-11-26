import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:latlong2/latlong.dart' hide Path;
import 'package:material_symbols_icons/symbols.dart';

import '../main.dart' show caps, ink, madder, paper, paperDeep, sepia, serif;
import '../ui/paper_surface.dart';

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

/// Photon's answer as places.
List<FoundPlace> placesOf(Map<String, dynamic> j) {
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

/// The map's search bar: hand-drawn black pencil border, right-aligned "Search"
/// text, frosted-paper results dropdown that collapses immediately once a
/// result is selected.
class PlaceSearch extends StatefulWidget {
  const PlaceSearch({
    super.key,
    required this.width,
    required this.near,
    required this.onPick,
    this.style = 'ink',
  });

  final double width;
  final LatLng Function() near;
  final ValueChanged<FoundPlace> onPick;
  final String style;

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
      if (!_focus.hasFocus && mounted) {
        setState(() {
          _found = const [];
          _note = null;
        });
      }
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
    // Cancel any in-flight query and collapse the search results immediately.
    _wait?.cancel();
    _run++;
    hapticTap();
    _text.text = p.name;
    _focus.unfocus();
    setState(() {
      _found = const [];
      _note = null;
    });
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
    final isMadder = widget.style == 'madder';
    final isInk = widget.style == 'ink';
    final bg = isMadder
        ? madder
        : isInk
            ? paper.withValues(alpha: 0.80)
            : paper.withValues(alpha: 0.94);
    final fg = isMadder ? paper : (isInk ? ink : madder);
    final radius = BorderRadius.all(Radius.circular(isMadder ? 4 : 16));
    return TextFieldTapRegion(
      child: SizedBox(
        width: widget.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              foregroundPainter: isInk ? const _PencilBorderPainter(radius: 16, color: ink) : null,
              child: Container(
                height: 34,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: radius,
                  border: isMadder || isInk ? null : Border.all(color: paperDeep),
                  boxShadow: isInk
                      ? null
                      : const [BoxShadow(color: Color(0x4D3C280A), offset: Offset(0, 2), blurRadius: 8)],
                ),
                child: Row(children: [
                  if (_text.text.isNotEmpty)
                    Semantics(
                      button: true,
                      label: 'Clear the search',
                      child: InkResponse(
                        radius: 16,
                        onTap: _clear,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(start: 8, end: 2),
                          child: Icon(Symbols.close, size: 17, color: fg),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 10),
                  Expanded(
                    child: CallbackShortcuts(
                      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _clear},
                      child: TextField(
                        controller: _text,
                        focusNode: _focus,
                        textAlign: TextAlign.right,
                        onTap: () {
                          if (!_focus.hasFocus) _clear();
                        },
                        onChanged: _typed,
                        onSubmitted: (_) {
                          if (_found.isNotEmpty) _pick(_found.first);
                        },
                        textInputAction: TextInputAction.search,
                        style: TextStyle(fontFamily: caps, fontSize: 14, letterSpacing: 0.6, color: fg, height: 1.2),
                        cursorColor: fg,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: 'Search',
                          hintStyle: TextStyle(
                            fontFamily: caps,
                            fontSize: 14,
                            letterSpacing: 0.8,
                            color: fg.withValues(alpha: 0.72),
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 6, end: 10),
                    child: Icon(Symbols.search, size: 17, color: fg),
                  ),
                ]),
              ),
            ),
            if (_found.isNotEmpty || (_note != null && _focus.hasFocus))
              PaperSurface(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(4),
                borderRadius: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_found.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                        child: Text(_note!,
                            style: const TextStyle(
                                fontFamily: serif, fontStyle: FontStyle.italic, fontSize: 14, color: sepia)),
                      ),
                    for (final p in _found.take(6))
                      Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          hoverColor: ink.withValues(alpha: 0.08),
                          highlightColor: ink.withValues(alpha: 0.12),
                          onTap: () => _pick(p),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
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

/// Subtle hand-drawn black pencil border around the search bar, echoing the
/// organic graphite character of [SongScribblePainter].
class _PencilBorderPainter extends CustomPainter {
  const _PencilBorderPainter({required this.radius, required this.color});

  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0.8, 0.8, size.width - 1.6, size.height - 1.6);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final base = Path()..addRRect(rrect);
    final metrics = base.computeMetrics().toList();
    if (metrics.isEmpty) return;

    void strokePass(double seed, double strokeW, double alpha, double amp) {
      final path = Path();
      final m = metrics.first;
      final total = m.length;
      const step = 4.0;
      var first = true;
      for (var d = 0.0; d <= total + step; d += step) {
        final t = m.getTangentForOffset(math.min(d, total));
        if (t == null) continue;
        // Normal perpendicular to the border
        final nx = -t.vector.dy;
        final ny = t.vector.dx;
        final w = (math.sin(d * 0.23 + seed) * 0.6 + math.sin(d * 0.61 + seed * 1.7) * 0.4) * amp;
        final px = t.position.dx + nx * w;
        final py = t.position.dy + ny * w;
        if (first) {
          path.moveTo(px, py);
          first = false;
        } else {
          path.lineTo(px, py);
        }
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    strokePass(0.0, 1.15, 0.85, 0.45);
    strokePass(19.4, 0.65, 0.32, 0.65);
  }

  @override
  bool shouldRepaint(_PencilBorderPainter old) => old.radius != radius || old.color != color;
}
