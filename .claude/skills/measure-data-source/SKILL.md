---
name: measure-data-source
description: How to check what an open data source really contains (fields, names, counts, size, licence) before building on it. Use for any "can the map show X?" or "is there a dataset of Y?" question.
---
# Measure first

Ed's rule: measure, don't guess. Three sources looked right for naming
woods and were wrong (the map tiles, Nominatim, Forestry England) before OS
Open Names turned out to have it. Each check took a minute.

## Rules

- Ask the source, not a blog about it.
- Test with real places Ed knows: RSPB Ham Wall (51.153, -2.787), Loxley
  Wood (51.134, -2.847), Stockhill (51.262, -2.640), Stonehenge (51.179,
  -1.826). Then one dense place (Falmouth, the Weald) for size.
- Nothing personal in any request. User-Agent
  `Birdsong/0.1 github.com/dopeytree/birdsong`.
- Nominatim: one request at a time, more than a second apart.
- Downloads: the scratchpad, each in its own folder, never the repo. Ask
  Ed before anything over about 20 MB.
- Record the result in `docs/data-sources.md`, including dead ends.

## Recipes

ArcGIS layer (Historic England, Natural England, NatureScot, Forestry):

```bash
L=<layer url ending /FeatureServer/0>
curl -s "$L?f=json" | python3 -c "import json,sys; j=json.load(sys.stdin); print([f['name'] for f in j['fields']]); print(j.get('copyrightText'))"
curl -s "$L/query?where=1%3D1&returnCountOnly=true&f=json"
curl -s "$L/query?geometry=<w>,<s>,<e>,<n>&geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects&returnGeometry=false&outFields=*&f=json"
```

Finding a layer: `https://hub.arcgis.com/api/search/v1/collections/dataset/items?q=<words>&limit=10`
(or the publisher's own hub, e.g. `data-forestry.opendata.arcgis.com`).

Map tiles (OpenFreeMap, OpenMapTiles schema): the tile URL comes from
`https://tiles.openfreemap.org/planet`. Decode a layer with
`readMvtLayer` from `lib/native/mvt.dart` in a small Dart script run with
`dart run --packages=.dart_tool/package_config.json <script>`. Named
features are in `park`, `place`, `poi`, `water_name`, `mountain_peak`;
`landcover` (woods) has no names.

Nominatim reverse: add `layer=natural` for woods, heaths and peaks; without
it you get the nearest road.

Overpass (what OpenStreetMap itself holds): `https://overpass-api.de/api/interpreter`
with `[out:json];(way["natural"="wood"](s,w,n,e););out tags center;`.

## Report

The URL asked, its fields, its licence line, what came back for each test
place, the size for a dense place, and a one-line verdict with the catch.
