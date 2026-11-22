# The map: what is built and how

Updated 22 Nov 2026. Code: `lib/native/walk_map.dart` and friends (see
`code-map.md`). Sources and licences: `data-sources.md`.

## Base

flutter_map with OpenFreeMap vector tiles, contours traced from terrarium
elevation (≥ 10 m), the walk's trail, a cross where each bird was heard,
the station's spot. Islands and cities labelled (Isle of Mull, not just
Tobermory).

## Controls

- Search box top right (Photon), deduped.
- + and −, and reset (↻).
- Full screen (⛶): a bird card opens over it; Escape closes. No "Passed on
  the way" under it (Ed, 22 Nov; `PassedStrip` kept, unused).
- Layers button: the "On the map" panel.
- Taps are decided in one place, most particular first (`_tapped`).

## Layers ("On the map" panel; master switch `mapExtras`)

| Layer | Setting | From |
|---|---|---|
| Heritage: listed buildings, monuments, parks and gardens, battlefields, World Heritage Sites | `mapShowHeritage` | Historic England |
| Nature sites: SSSI, SPA, NNR, LNR, Ramsar | `mapShowNature` | Natural England, NatureScot, NRW (each asked only for its own country) |
| Ancient woods | `mapShowAncient` | Natural England's Ancient Woodland Inventory |
| Reserves | `mapShowReserves` | OpenStreetMap, from the map tiles |
| Hides & viewpoints | `mapShowHides` | OpenStreetMap poi |
| Wikipedia places | `mapShowWiki` | Wikipedia |
| Bird records for a chosen species | `mapRecordsSci` | GBIF density tiles (`bird_records.dart`) |

Landmarks follow the view (zoom ≥ 12; Grade II from 15).

## Passed on the way

Above the map, only when something was passed; 3 + "and N more" on phones.
Choose a line to see it on the map; its label then links to Wikipedia,
Historic England or a web search. The walk knows its reserve
(`reservesAlong` reads the z14 park layer): "RSPB Ham Wall, walked
through" leads. Setting: "Descriptions in Passed on the way"
(`mapPassedAbout`).

## Speed (the Falmouth lesson)

The cause was flutter_map computing dashed outlines along whole polygons on
the UI thread (an 11.5 s frame). Now: edges are polylines cut to the view
(`clipLine`); label points cached; lookups on an isolate; no building
footprints; contours ≥ 10 m; outlines no finer than z13; ≤ 150 marks. The
timing readout (Settings → Map → Timing readout, debug builds, off by
default) showed 20–47 ms after.

## Ancient woods (22 Nov, not yet seen)

A fill a shade deeper over the map's own woods (`_ancient`, `#4F6B35` at
18%, no edge, no name). England only. Stockhill is a plantation, so not
tinted; Buddle's Wood and Loxley Wood are. Ed may want the shade tuned.
Heavy in dense places (the Weald: 1,430 woods, 1.3 MB a view).

## Ancient sites (22 Nov, not yet seen)

- A slight sepia upright for each of Historic England's standing stones
  (`_StonePainter`, from z12). `antiquities.dart` picks them out of the
  scheduled monuments by the first kind word in the name.
- Small engravings of **Stonehenge** and **Calanais**, where they stand
  (`_drawnSites`, `_SitePainter`, from z9, with Heritage on). Stonehenge's
  long record name is no longer printed as its label.
- Other monuments keep their dotted edge, hatching and name from z13.5.
- Tried and rejected: see `decisions.md`.

## Walk names in the calendar (22 Nov, not yet seen)

"Ashcott – RSPB Ham Wall", "Shapwick – Loxley Wood". `walk_names.dart`
(`areaOfWalk`): the OpenStreetMap reserve the walk was most inside (z14
park layer, tiles fetched directly, kept for the run); else the OS Open
Names wood or heath, each point of the walk going to the box with the
nearest middle (boxes overlap: Swayne's Jumps Plantation and King's Sedge
Moor both cover Loxley Wood). Saved per session as `placeArea` ('' none,
null not yet; offline leaves it null). Asked when the calendar opens, for
ended walks only. Not shown when it repeats the town.

## Wildlife pictures: switched off

`wildlifePicturesOn = false` in `wildlife.dart`; the code stays.
- Drawn silhouettes per habitat: Ed rejected the look, and they popped in
  and jumped on zoom.
- `engravings.dart`: Thomas Bewick's woodcuts from the Wellcome
  Collection's IIIF scans (Quadrupeds b33281294, British Birds
  b29333131_0001 land / _0002 water), found by heading via the IIIF search API, cut out with `cutout.dart`,
  toned to the map's ink. Committed (`b167cc5`), never built or seen. No
  Bewick whale.
- Better plan, agreed in principle: put pictures in the map style itself
  (symbol layers with sprite icons, `fill-pattern` textures), so they
  arrive with the tiles and never jump. Optionally place animals only where
  GBIF has records. Show Ed real engravings before building.
