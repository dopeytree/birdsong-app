---
name: new-map-layer
description: Checklist for adding a new kind of place or area to the map (a new Historic England, Natural England, OpenStreetMap or other layer). Use after the data source has been measured and Ed has agreed the look.
---
# Adding a layer to the map

Before any code: measure the source (`measure-data-source`), and show Ed
the look (`render-painter` or a mock-up). Then, in order:

1. **Lookup** (`lib/native/landmarks.dart`)
   - Add the kind to `allLayers` if it has its own switch.
   - Fetch it in `lookUpFrame` beside the others, with `touches(frame,
     region)` so a service is asked only for its own country, and a
     `catchError` that adds a readable name to `unreached`.
   - Add a field to `Landmarks`: constructor, `merge`, the `Landmarks(...)`
     built in `lookUpFrame`, and the copy in `LandmarkLookup.want`.
     Missing one of the four drops the layer silently.
   - Simplify with `maxAllowableOffset` (`simplify:`): areas are heavy.
2. **Setting** (`lib/settings.dart`): a `mapShow…` bool with its doc line,
   in `fromJson` (with a default) and in `toJson`.
3. **Drawing** (`lib/native/walk_map.dart`)
   - Add the kind to the `kinds` set built from the settings.
   - Fills and edges go through `_areas`. Never give a `Polygon` a dashed
     border: flutter_map works out every dash along the whole outline on
     the screen's thread (11 s frames in Falmouth). Use `_edgeLines`.
   - Marks go in the memo's `spots`, capped to the nearest the middle.
   - Anything that depends on zoom must be in `_zoomStep`, or the memo
     won't rebuild.
4. **Layers panel** (`_LayersPanel` in `walk_map.dart`): a `row(...)`, and
   the new bool in `_set`'s `mapExtras` line and both "switch one on alone"
   blocks.
5. **Credit and licence:** the map's credit line (`_extrasCredit`) or
   Settings' credits; add the source to `docs/data-sources.md`.
6. **Test:** `merge` keeps each once (`test/landmarks_test.dart`); any name
   parsing against real names.
7. **Measure:** note the count and bytes for a busy place in
   `docs/data-sources.md`. The map's timing readout (Settings → Map, debug
   builds) shows the cost.
8. `flutter analyze`, `flutter test`, read the diff by eye, `handover`.
