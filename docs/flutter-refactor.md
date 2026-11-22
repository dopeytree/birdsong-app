# The Flutter refactor: where it stands

Read this first in any new session about the refactor (Claude Code or chat).
Branch: `flutter-plate-lab`. Updated 21 Nov 2026, late evening.
The full plan and its Progress table: [Birdsong Flutter plate plan](https://claude.ai/artifact/XfdX9oyxDrxf5y6g9TDnxr)
(claude.ai artifact; may not be reachable from Claude Code).

## What the refactor is

The app's plate (the collage of bird plates, index, heading, buttons, map,
bird card) was a web page (`assets/web/index.html`, from dopeytree/birdsong)
shown in a web view. It is being rebuilt as native Flutter in `lib/native/`,
so the app (and later Flutter web) no longer needs the page.

**A faithful port:** "you are refactoring the old code into flutter. this
doesn't mean you are removing functions or design choices." Every behaviour
and look of the old plate carries over, then is improved on with Ed's say-so.

The Flutter plate is behind Settings → Experimental → Flutter plate
(`nativePlate`, off by default). It shows both Listen here and remote stations.

## How we work (Ed's rules)

- **Ed is the designer.** Ask before large or visual decisions; show ideas
  or a small test first. The look is vintage natural history: paper, sepia
  ink, serif (IM Fell English), engraved plates. Never modern or cartoon.
- **Ed is cost-sensitive.** Measure before guessing (the debug readout on
  the map exists for this); don't redo work; keep replies short.
- **Commit on our branch and push every branch** so nothing clashes locally.
- **No iPhone builds** until the app is complete, unless Ed asks.
- **Builds:** Ed runs `Build on Mac.command`, which bootstraps, analyzes,
  runs the tests, builds macOS and opens the app, writing `build-log.txt`.
  Read it: grep `STATUS`, `error •`, `Failing tests`;
  `git reflog --date=format:%H:%M:%S` shows which commit was built.
  **A failed build still opens the previous app.** Check the log before
  trusting what Ed sees.
- **Don't trust the analyzer alone.** It has missed real compile errors:
  a const `StrokePattern.dashed(...)` (never make it const on flutter_map
  8.3), and a missing import (`CustomPainter` is in
  `package:flutter/rendering.dart`, not `painting.dart`). Read changed code
  by eye.
- **Isolates:** call `Isolate.run` from a top-level function, never from a
  closure inside a widget's async method (it drags the State along and
  fails to send). Don't swallow errors with `catch (_) {}`; `debugPrint` them.
- When editing with scripts, assert each replacement matched.
- **Git on the Mac via Claude's Cowork bridge** (if you're in that setup,
  not Claude Code): ask for delete permission before committing so git can
  remove `.lock` and `tmp_obj_*` files; that shell has no network, so Ed
  pushes from his terminal. Commits need an identity:
  `git -c user.name=… -c user.email=…` (copy them from `git log -1`).
- The app is sandboxed: its data (fill logs, stations/) is under
  `~/Library/Containers/…`. Ask Ed to paste what's needed.

## Versions

Flutter 3.50 (material.dart deprecated in favour of material_ui: infos only),
Dart SDK lower bound 3.7, flutter_map 8.3.2, flutter_map_vector_tiles 2.12
(supports `fill-pattern`, symbol icons, `global-state`; its MVT decoder isn't
exported, so `lib/native/mvt.dart` is ours), latlong2 (exports `Path`: use
`ui.Path`).

## Done

- **Collage, index, heading, buttons, views, bird card, share/save,
  settings:** all ported (see the plan's Progress table).
- **Calendar:** sessions under place names (Nominatim, cached).
- **Remote stations** (BirdNET-Go, BirdWeather): name, dates, weather;
  Today/Week/Month/All; day/night; each day kept as a session folder
  (`stations/<id>/<day>/`), filled in automatically on a computer, after
  asking on a phone; Settings → Station history shows the log.
- **Map, part one:** flutter_map, OpenFreeMap vector tiles, contours from
  terrarium elevation, trail and crosses, the station's spot.
- **Map, part two:** Landmarks (Settings → Map): Historic England listed
  buildings and monuments, Natural England sites, Wikipedia places, as the
  web page's map-mode.js did (`landmarks.dart`, `passed_view.dart`).
- **Map, part three:**
  - Landmarks follow the view (zoom ≥ 12; Grade II from 15).
  - Historic England parks and gardens, battlefields, World Heritage Sites.
  - Nature reserves from OpenStreetMap tiles (not RSPB data: their licence
    is non-commercial and needs written permission for public maps).
  - Search box top right (Photon), deduped, `TextFieldTapRegion` (macOS
    unfocuses before the tap lands otherwise).
  - Reset button (↻) under + and −.
  - The walk knows its reserve (`reservesAlong` reads the z14 park layer):
    "Passed on the way" leads with "RSPB Ham Wall, walked through".
  - Taps decided in one place, most particular first (`_tapped`).
- **Map, part four:**
  - Full-screen map (⛶); a bird card opens over it; Escape closes.
  - "Passed on the way" above the map, only when something was passed;
    3 + "and N more" on phones; not on the full-screen map (Ed, 22 Nov;
    `PassedStrip` kept, unused); choose a
    line to see it on the map, then its label links to Wikipedia, Historic
    England or a web search. Setting: "Descriptions in Passed on the way".
  - **Speed (Falmouth):** the real cause was flutter_map computing dashed
    outlines along whole polygons on the UI thread (an 11.5 s frame). Edges
    are now polylines cut to the view (`clipLine`); label points cached;
    lookups on an isolate; no building footprints; contours ≥ 10 m; outlines
    no finer than z13; ≤ 150 marks. Debug readout (debug builds, top left of
    the map) showed 20–47 ms after.
  - Islands and cities labelled (Isle of Mull, not just Tobermory).
- **Map, part five: layers button** (built and in use): "On the map" panel
  with Heritage, Nature sites (now also NatureScot and NRW, each asked only
  for its own country), Reserves, Hides & viewpoints (OSM poi), Wikipedia,
  and Bird records (GBIF density tiles for a chosen species,
  `bird_records.dart`).
- **Wildlife pictures: switched OFF** (`wildlifePicturesOn = false` in
  `wildlife.dart`; the code stays for later):
  - Drawn silhouettes per habitat from the map tiles: Ed rejected the look
    ("vintage illustrations, not modern cartoon"), and they popped in and
    jumped on zoom.
  - `engravings.dart`: Thomas Bewick's woodcuts fetched from the Wellcome
    Collection's IIIF scans (Public Domain Mark): Quadrupeds b33281294,
    British Birds b29333131_0001 (land) / _0002 (water). Found by heading
    via the IIIF search API, cut out with `cutout.dart`, toned to the map's
    ink. Committed (`b167cc5`) but never built or seen. No Bewick whale.
  - Better plan, agreed in principle: put pictures in the map style itself
    (symbol layers with sprite icons, and `fill-pattern` textures), so they
    arrive with the tiles and never jump. Optionally place animals only
    where GBIF has records. Show Ed real engravings before building.

## Next steps

1. Done 22 Nov: build clean, map checked by Ed. Since then: the map's
   debug readout is a setting, off by default; no Passed on the way under
   the full-screen map.
2. Calendar sessions named by where the walk went, after the town:
   "Ashcott – RSPB Ham Wall", "Ashcott – Loxley Wood" (Ed, 22 Nov).
   Measured 22 Nov: the map's z14 tiles name reserves (park layer: RSPB
   Ham Wall, Shapwick Heath NNR, Shapwick Moor), lakes and hills, but no
   woods. Nominatim's reverse with `layer=natural` names the wood
   (51.134, -2.847 → Loxley Wood, natural=wood) but at Ham Wall gives
   "South Drain" (a waterway), so: reserve from the tiles first, else
   Nominatim's natural layer, waterways left out. Loxley Wood's village
   is Shapwick, not Ashcott.
   Stockhill (Mendip, near Priddy): no name in OpenStreetMap at all (its
   woods are unnamed natural=wood), so neither source has it; the tiles
   give the Priddy Mineries reserve beside it, Nominatim's natural layer
   only nearby peaks (Niver Hill). Would need Forestry England's National
   Forest Estate data (OGL) or a name added to OSM.
3. Later: achievements kept on the phone. Ed is weighing an age question
   and a safe mode for young people (UK Children's Code).
4. The app as Flutter web.
5. **Parked (Ed, 22 Nov):** the Birdsong companion server (Docker, reads
   `birdnet.db`). See "Station fill timings" below for what sizes it.

## Station fill timings (Ed's BirdNET-Go station, 21–22 Nov 2026)

From Settings → Station history, 48 days kept.
- **A past day:** 0–2,253 calls; asked 9–262 ms, weather 12–53 ms, total
  28–303 ms. The ask grows with the calls, about 0.1 ms a call.
- **Today, so far** (asked again about every 10 min): grows through the
  day; ~2,000–3,000 calls asked in 170–740 ms. Weather once slowed to
  83–225 ms (14:03–14:36), otherwise 9–112 ms.
- **One stall:** 21:03, asked 34,841 ms for 2,919 calls; the next ask, a
  minute later, took 504 ms. The station or the network, not the size.
- **Filling 39 days took 54 s** (12:09:51–12:10:45): the 1.2 s rest
  between days (`station_archive.dart`), not the station.
- So the station's own API is fast enough for the app as it is; a
  companion server isn't needed for speed. A time limit on one ask (the
  stall) is worth adding.

## Offered, not yet answered

- Make the Flutter plate the default.
- Restyle the calendar grid; move Experimental options into Display.
- Write to RSPB about their data.
- Quick fixes: commit `pubspec.lock`; ignore `android/`, `ios/`, `macos/`,
  `.bootstrap/`; a pull request for `flutter-plate-lab`; prune merged
  branches; remove the map's debug readout when done with it.

## Licences (see the project's licence audit)

OGL v3: Historic England, Natural England, NatureScot, NRW. ODbL:
OpenStreetMap (tiles by OpenFreeMap / OpenMapTiles). Wikipedia CC BY-SA.
Photon: public instance, light use only. GBIF: attribution; some records
CC BY-NC (check before commercial use). Bewick scans: Public Domain Mark.
RSPB data: not used. Every source is credited on the map.

## Where things are

- **Plate:** `lib/native/` — native_plate, collage_view, index_view,
  bird_card, day_picker, walk_map (the map), map_style (vector styles,
  sprites), landmarks (lookups, Passed on the way), mvt, passed_view,
  place_search, contours, bird_records, wildlife, engravings, cutout,
  plate_library (bird plates from Wikimedia Commons), station_feed,
  station_archive.
- **Shared buttons:** `lib/ui/plate_buttons.dart`.
- **Settings:** `lib/settings.dart` (`native*`, `mapExtras` master switch,
  `mapShow*`, `mapRecordsSci`, `mapPassedAbout`, `mapWildlife`), screen in
  `lib/ui/settings_screen.dart`.
- **Tests:** `test/` (landmarks, mvt, place_search, bird_records, wildlife,
  engravings, contours, and the rest).
- **Scripts:** `Build on Mac.command`, `Run plate lab.command`,
  `Update web page.command`, `Publish to GitHub.command`.

## Skills that help

Built-in Claude Code skill packs used or worth loading:
- `flutter:flutter-performance` (rebuild scope, isolates, measuring).
- `flutter:widget-composition`, `flutter:custom-canvas-and-gestures`.
- `flutter:async-safety` (mounted checks, no swallowed errors).
- `superpowers:systematic-debugging` (measure first: it found Falmouth).
- `zizi-skills:git-sync` (own branch, push every branch).
- `anthropic-skills:birdsong-web-sync` (Ed's own skill: moving features
  between the web page dopeytree/birdsong and this app). If it isn't
  installed in Claude Code, ask Ed for it.
