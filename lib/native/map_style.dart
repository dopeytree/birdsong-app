// The walk map's look: the web plate's map style (assets/app/map-mode.js,
// mapStyle()), layer for layer, for flutter_map_vector_tiles. It is split
// in two so the contours, drawn by Flutter, sit between the land and the
// names, as they do on the web map. The little hand-drawn pictures the
// style uses (trees, reeds, peaks) are drawn here into a sprite sheet.

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;

import '../main.dart' show ink, paper, sepia;

const _fontIt = ['Noto Sans Italic'];

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// The land, water, woods and ways: everything below the contours.
Map<String, Object?> baseStyle(String source) => {
      'version': 8,
      'sources': {source: {'type': 'vector'}},
      'layers': [
        {'id': 'paper', 'type': 'background', 'paint': {'background-color': _hex(paper)}},
        // nature: washes, little trees, reeds, water
        {
          'id': 'grass', 'type': 'fill', 'source': source, 'source-layer': 'landcover',
          'filter': ['in', ['get', 'class'], ['literal', ['grass', 'farmland']]],
          'paint': {'fill-color': '#e3dcbc', 'fill-opacity': 0.55},
        },
        {
          'id': 'wetland', 'type': 'fill', 'source': source, 'source-layer': 'landcover',
          'filter': ['==', ['get', 'class'], 'wetland'],
          'paint': {'fill-color': '#d6dcc6', 'fill-opacity': 0.7},
        },
        {
          'id': 'wetland-reeds', 'type': 'fill', 'source': source, 'source-layer': 'landcover',
          'filter': ['==', ['get', 'class'], 'wetland'],
          'paint': {'fill-pattern': 'reeds', 'fill-opacity': 0.8},
        },
        {
          'id': 'wood-bleed', 'type': 'line', 'source': source, 'source-layer': 'landcover',
          'filter': ['==', ['get', 'class'], 'wood'],
          'paint': {'line-color': '#a9b98a', 'line-width': 6, 'line-blur': 6, 'line-opacity': 0.45},
        },
        {
          'id': 'wood', 'type': 'fill', 'source': source, 'source-layer': 'landcover',
          'filter': ['==', ['get', 'class'], 'wood'],
          'paint': {'fill-color': '#c2cc9f', 'fill-opacity': 0.75},
        },
        {
          'id': 'wood-trees', 'type': 'fill', 'source': source, 'source-layer': 'landcover',
          'filter': ['==', ['get', 'class'], 'wood'],
          'paint': {'fill-pattern': 'trees'},
        },
        {
          'id': 'park', 'type': 'fill', 'source': source, 'source-layer': 'park',
          'paint': {'fill-color': '#d3d8b3', 'fill-opacity': 0.5},
        },
        {
          'id': 'water-bleed', 'type': 'line', 'source': source, 'source-layer': 'water',
          'paint': {'line-color': '#8fb0b0', 'line-width': 7, 'line-blur': 7, 'line-opacity': 0.4},
        },
        {
          'id': 'water', 'type': 'fill', 'source': source, 'source-layer': 'water',
          'paint': {'fill-color': '#bccfca', 'fill-opacity': 0.9},
        },
        {
          'id': 'waterway', 'type': 'line', 'source': source, 'source-layer': 'waterway',
          'layout': {'line-cap': 'round', 'line-join': 'round'},
          'paint': {
            'line-color': '#7fa3a4', 'line-opacity': 0.85,
            'line-width': [
              'interpolate', ['linear'], ['zoom'],
              11, ['match', ['get', 'class'], 'river', 1.2, 0.4],
              16, ['match', ['get', 'class'], 'river', 3.5, 1.3],
            ],
          },
        },
        // people: quiet, in the paper's own browns
        {
          'id': 'buildings', 'type': 'fill', 'source': source, 'source-layer': 'building', 'minzoom': 13.5,
          'paint': {
            'fill-color': '#e0d3b6', 'fill-outline-color': '#cbbb9b',
            'fill-opacity': ['interpolate', ['linear'], ['zoom'], 13.5, 0, 15, 0.85],
          },
        },
        {
          'id': 'rail', 'type': 'line', 'source': source, 'source-layer': 'transportation', 'minzoom': 11,
          'filter': ['==', ['get', 'class'], 'rail'],
          'paint': {'line-color': '#b9a888', 'line-width': 1, 'line-dasharray': [5, 3], 'line-opacity': 0.8},
        },
        {
          'id': 'roads', 'type': 'line', 'source': source, 'source-layer': 'transportation',
          'filter': ['in', ['get', 'class'], ['literal', ['motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'minor', 'service']]],
          'layout': {'line-cap': 'round', 'line-join': 'round'},
          'paint': {
            'line-color': ['match', ['get', 'class'], ['motorway', 'trunk', 'primary'], '#c9b28b', ['secondary', 'tertiary'], '#d1bd9a', '#d9c9ab'],
            'line-width': [
              'interpolate', ['linear'], ['zoom'],
              10, ['match', ['get', 'class'], ['motorway', 'trunk', 'primary'], 0.8, ['secondary', 'tertiary'], 0.5, 0],
              13, ['match', ['get', 'class'], ['motorway', 'trunk', 'primary'], 1.8, ['secondary', 'tertiary'], 1.2, 'service', 0.3, 0.6],
              16, ['match', ['get', 'class'], ['motorway', 'trunk', 'primary'], 4, ['secondary', 'tertiary'], 3, 'service', 1, 2],
            ],
            'line-opacity': 0.9,
          },
        },
        {
          'id': 'tracks', 'type': 'line', 'source': source, 'source-layer': 'transportation', 'minzoom': 12.5,
          'filter': ['==', ['get', 'class'], 'track'],
          'layout': {'line-cap': 'round'},
          'paint': {
            'line-color': '#bba580',
            'line-width': ['interpolate', ['linear'], ['zoom'], 12.5, 0.6, 16, 1.3],
            'line-dasharray': [3, 2],
          },
        },
        {
          'id': 'paths', 'type': 'line', 'source': source, 'source-layer': 'transportation', 'minzoom': 13,
          'filter': ['==', ['get', 'class'], 'path'],
          'layout': {'line-cap': 'round'},
          'paint': {
            'line-color': '#b09870',
            'line-width': ['interpolate', ['linear'], ['zoom'], 13, 0.6, 16, 1.2],
            'line-dasharray': [0.8, 2],
          },
        },
      ],
    };

/// The kinds of OpenStreetMap park drawn as reserves, and what each is
/// called in a label.
const reserveKinds = {
  'nature_reserve': 'Nature reserve',
  'protected_area': 'Protected area',
  'national_park': 'National park',
};

/// Nature reserves from OpenStreetMap (the tiles' park layer: RSPB, Wildlife
/// Trust and other reserves, protected areas, national parks), with the
/// map's extras: a faint wash, a fine dashed edge in moss, the name from
/// zoom 12. Above the contours, below the place names.
Map<String, Object?> reservesStyle(String source) {
  final kinds = ['in', ['get', 'class'], ['literal', reserveKinds.keys.toList()]];
  const moss = '#56743f';
  return {
    'version': 8,
    'sources': {source: {'type': 'vector'}},
    'layers': [
      {
        'id': 'reserve-fill', 'type': 'fill', 'source': source, 'source-layer': 'park', 'filter': kinds,
        'paint': {'fill-color': moss, 'fill-opacity': 0.05},
      },
      {
        'id': 'reserve-edge', 'type': 'line', 'source': source, 'source-layer': 'park', 'filter': kinds,
        'layout': {'line-join': 'round'},
        'paint': {'line-color': moss, 'line-opacity': 0.75, 'line-width': 0.9, 'line-dasharray': [2, 1.5]},
      },
      {
        'id': 'reserve-label', 'type': 'symbol', 'source': source, 'source-layer': 'park', 'minzoom': 12,
        'filter': ['all', kinds, ['has', 'name']],
        'layout': {'text-field': ['get', 'name'], 'text-font': _fontIt, 'text-size': 10, 'text-max-width': 9},
        'paint': {'text-color': moss, 'text-halo-color': _hex(paper), 'text-halo-width': 1.5},
      },
    ],
  };
}

/// The names of places and peaks: above the contours.
Map<String, Object?> labelStyle(String source) => {
      'version': 8,
      'sources': {source: {'type': 'vector'}},
      'layers': [
        {
          'id': 'place-label', 'type': 'symbol', 'source': source, 'source-layer': 'place',
          'filter': ['in', ['get', 'class'], ['literal', ['town', 'village', 'hamlet']]],
          'layout': {
            'text-field': ['get', 'name'], 'text-font': _fontIt,
            'text-size': ['match', ['get', 'class'], 'town', 15, 12],
            'text-letter-spacing': 0.14, 'text-transform': 'uppercase',
          },
          'paint': {'text-color': _hex(sepia), 'text-halo-color': _hex(paper), 'text-halo-width': 2},
        },
        // peaks come with the base tiles, so they are always shown
        {
          'id': 'peaks', 'type': 'symbol', 'source': source, 'source-layer': 'mountain_peak',
          'filter': ['all', ['==', ['get', 'class'], 'peak'], ['has', 'name']],
          'layout': {
            'icon-image': 'peak', 'icon-allow-overlap': true, 'icon-anchor': 'bottom',
            'text-field': ['case', ['has', 'ele'], ['concat', ['get', 'name'], '\n', ['to-string', ['get', 'ele']], ' m'], ['get', 'name']],
            'text-font': _fontIt, 'text-size': 11, 'text-anchor': 'top', 'text-offset': [0, 0.3], 'text-optional': true,
          },
          'paint': {'text-color': _hex(ink), 'text-halo-color': _hex(paper), 'text-halo-width': 1.8},
        },
      ],
    };

/// The style's pictures, drawn as map-mode.js draws them (its PICS), at
/// twice the size they are shown.
Future<vt.SpriteAtlas> mapSprites() async {
  final sizes = {'trees': 64, 'reeds': 48, 'peak': 40};
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final sprites = <String, vt.Sprite>{};
  var x = 0.0;
  for (final e in sizes.entries) {
    c.save();
    c.translate(x, 0);
    switch (e.key) {
      case 'trees':
        _trees(c);
      case 'reeds':
        _reeds(c);
      case 'peak':
        _peak(c);
    }
    c.restore();
    final s = e.value.toDouble();
    sprites[e.key] = vt.Sprite(x: x, y: 0, width: s, height: s, pixelRatio: 2);
    x += s;
  }
  final image = await rec.endRecording().toImage(x.ceil(), 64);
  return vt.SpriteAtlas(image: image, sprites: sprites, pixelRatio: 2, cacheKey: 'birdsong-map-sprites-1');
}

Paint _line(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

void _trees(Canvas g) {
  void tree(double x, double y, double r) {
    final stroke = _line(const Color(0xFF5F7146), 1.6);
    g.drawLine(Offset(x, y + r * .6), Offset(x, y + r * 1.9), stroke);
    final crown = Rect.fromCenter(center: Offset(x, y), width: r * 2, height: r * 2.1);
    g.drawOval(crown, Paint()..color = const Color(0x8C7A915C)); // rgba(122,145,92,.55)
    g.drawOval(crown, stroke);
  }

  tree(14, 14, 6);
  tree(44, 22, 5);
  tree(26, 44, 6.5);
  tree(56, 52, 4.5);
  tree(6, 52, 4);
}

void _reeds(Canvas g) {
  final p = _line(const Color(0xFF7B8C63), 1.3);
  void tuft(double x, double y) {
    g
      ..drawLine(Offset(x - 4, y - 5), Offset(x - 1, y), p)
      ..drawLine(Offset(x, y - 7), Offset(x, y), p)
      ..drawLine(Offset(x + 4, y - 5), Offset(x + 1, y), p)
      ..drawLine(Offset(x - 6, y), Offset(x + 6, y), p);
  }

  tuft(12, 16);
  tuft(36, 30);
  tuft(18, 42);
}

void _peak(Canvas g) {
  final hill = Path()
    ..moveTo(6, 34)
    ..lineTo(19.5, 7)
    ..lineTo(21, 8)
    ..lineTo(34, 34)
    ..close();
  g.drawPath(hill, Paint()..color = paper);
  g.drawPath(hill, _line(ink, 2.2));
  final shade = _line(ink, 1.2);
  g
    ..drawLine(const Offset(21, 13), const Offset(13, 30), shade)
    ..drawLine(const Offset(24, 19), const Offset(18, 32), shade)
    ..drawLine(const Offset(27, 25), const Offset(23, 33), shade);
}
