# Where things are

Updated 22 Nov 2026. Line counts are rough: the big files should be read in
parts (use the `scout` agent to find the lines).

## The plate: `lib/native/`

| File | Lines | Holds |
|---|---|---|
| `walk_map.dart` | 2,080 | The map: layers, marks, labels, taps, search, full screen, layers panel, all the painters |
| `native_plate.dart` | 1,510 | The plate itself: heading, collage, index, buttons, views, full-screen map route |
| `station_feed.dart` | 960 | Remote stations (BirdNET-Go, BirdWeather): fetching, periods, day/night |
| `landmarks.dart` | 950 | Lookups (Historic England, Natural England, NatureScot, NRW, Wikipedia), `Landmarks`, "Passed on the way", reserves from tiles, geometry |
| `bird_card.dart` | 820 | A bird's card: facts, trend bars, recordings |
| `collage_view.dart` | 720 | The collage layout and drawing |
| `plate_library.dart` | 560 | Bird plates from Wikimedia Commons, scored |
| `map_style.dart` | | Vector tile styles (paper, woods, water), sprites |
| `walk_names.dart` | | Where a walk went: reserve from tiles, else OS wood or heath |
| `antiquities.dart` | | Sorts scheduled monuments into prehistoric kinds by name |
| `day_picker.dart` | | The calendar dialog |
| `station_archive.dart` | | A station's past days kept as session folders |
| `mvt.dart`, `contours.dart`, `place_search.dart`, `bird_records.dart`, `passed_view.dart`, `index_view.dart` | | Tile decoder; contours from elevation; Photon search; GBIF density; the Passed list; the index |
| `wildlife.dart`, `engravings.dart`, `cutout.dart` | | Wildlife pictures (switched off) |

## The rest of `lib/`

- `settings.dart` (515): every setting, `fromJson` / `toJson`. Plate:
  `native*`, `webPlate`. Map: `mapExtras` (master switch), `mapShow*`,
  `mapRecordsSci`, `mapPassedAbout`, `mapDebugReadout`, `mapWildlife`.
- `ui/settings_screen.dart` (770): the Settings screen.
- `ui/home_shell.dart`: chooses the Flutter plate or the web plate.
- `ui/plate_view.dart`, `server/`: the old web plate and the local server
  that feeds it (the fallback).
- `ui/plate_buttons.dart`: shared buttons. `ui/format.dart`: dates, places.
- `engine/`: listening (classifier, models, resampler), `place_names.dart`
  (Nominatim), `weather.dart`.
- `store/detection_store.dart`: sessions, detections, tracks on disk.
- `main.dart`: the colours (`paper`, `ink`, `sepia`, `madder`, `rule`) and
  fonts (`serif`, `caps`).

## Elsewhere

- `test/`: one file per area, plain-sentence test names.
- `assets/web/`: the old web page. `assets/places/os_woods.tsv.gz`: OS
  woods and heaths. `tool/os_woods.py` rebuilds it.
- `site/`: Astro splash page (`site/src/pages/index.astro`), shots in
  `site/public/shots/`, fonts in `site/public/fonts/`. `Preview splash
  page.command` opens it at http://localhost:4321/birdsongs.ai/.
- `site.yml`: GitHub Pages workflow (dopeytree.github.io/birdsongs.ai).
- Scripts: `Build on Mac.command`, `Run plate lab.command`,
  `Update web page.command`, `Publish to GitHub.command`.
- `tool/sync_web.py`, `tool/web_contract.json`: checks on the web page copy.
