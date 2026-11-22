# Data sources: what we use, what was measured, dead ends

Updated 22 Nov 2026. Every source in use is credited on the map or in
Settings. Measure before building on a new one (`measure-data-source`
skill).

## In use

| Source | Used for | Licence |
|---|---|---|
| OpenFreeMap tiles (OpenMapTiles schema, OpenStreetMap data) | The map; reserves, hides, place names from the tiles | ODbL |
| Mapzen Terrain Tiles (terrarium) | Contours | Open |
| Historic England, National Heritage List (ArcGIS `ZOdPfBS3aqqDYPUQ`) | Listed buildings, monuments, parks, battlefields, World Heritage Sites | OGL v3 |
| Natural England (ArcGIS `JJzESW51TqeY9uat`) | SSSI, SPA, NNR, LNR; `Ancient_Woodland_England` (field `NAME`) | OGL v3 |
| NatureScot (ArcGIS `LM9GyVFsughzHdbO`) | Scottish sites | OGL v3 |
| Natural Resources Wales (DataMap Wales WFS) | Welsh SSSI, NNR | OGL v3 |
| OS Open Names | Woods and heaths, shipped as `assets/places/os_woods.tsv.gz` | OGL v3: "Contains OS data © Crown copyright and database right 2026" |
| Wikipedia | Places and their descriptions | CC BY-SA |
| Nominatim | A session's town or village | ODbL; one request a second, identifying User-Agent |
| Photon (komoot) | Map search | Public instance, light use only |
| GBIF | Bird record density tiles | Attribution; some records CC BY-NC (check before commercial use) |
| MET Norway | Weather | CC BY 4.0 |
| Wellcome Collection IIIF (Bewick) | Engravings (switched off) | Public Domain Mark |

**Not used: RSPB data.** Their licence is non-commercial and needs written
permission for public maps. Reserves come from OpenStreetMap instead.

## Naming where a walk went (measured 22 Nov)

- **Map tiles (z14):** name reserves (park layer: RSPB Ham Wall, Shapwick
  Heath NNR, Shapwick Moor), lakes and hills. No woods: `landcover` has no
  names.
- **Nominatim reverse with `layer=natural`:** names Loxley Wood (51.134,
  -2.847), but at Ham Wall gives "South Drain". Without `layer` it gives
  the nearest road. Loxley Wood's village is Shapwick, not Ashcott.
- **Stockhill** (Mendip, near Priddy): no name in OpenStreetMap at all (17
  woods round Priddy, one named: Bendalls Grove).
- **Forestry England open data** (ArcGIS `mHXjwgl3OARRqqD4`, OGL): no layer
  names its woods. Subcompartments have no name; Ownership has legal titles
  ("CHEWTON MENDIP WALDEGRAVE"); only Recreation Points say "Stockhill 011"
  (benches, signs), and at Beechenhurst, Haldon and Wyre they say nothing
  useful. Dead end.
- **Ancient Woodland Inventory:** names LOXLEY WOOD, EARNWOOD COPSE (Wyre),
  BUDDLES WOOD; some blank. Stockhill is a plantation, not in it.
- **OS Open Names has it.** GB CSV zip 103 MB: 98,551 "Woodland Or Forest"
  names plus other landcover, as points (British National Grid) with a box.
  Stockhill (355447, 151271), Mendip Forest, Buddle's Wood, Loxley Wood
  (340879, 137501). `tool/os_woods.py` pulls out 116,244 places into
  1.9 MB. Great Britain only.

## Ancient sites (measured 22 Nov)

Historic England has 20,006 scheduled monuments; names say what they are.
Counts by word: barrow 5,487 (long barrow 373), cairn 1,574, enclosure 778,
camp 580, hillfort 370, stone circle 143, standing stone 124, henge 77,
cursus 49, stone row 10. Round Stonehenge: 109 records, mostly "Bowl barrow
230m west of…". The tiles' park layer (class `historic`) carries many of
the same sites. Calanais is in Scotland: placed by its known position.

## Sizes worth knowing

- Ancient woods per view: Mendip 62 woods / 60 KB; the Weald 1,430 / 1.3 MB.
- Cornwall's mining World Heritage Site outline is hundreds of thousands of
  pixels round at street zoom (the Falmouth slowdown).

## Station fill timings (Ed's BirdNET-Go station, 21–22 Nov 2026)

From Settings → Station history, 48 days kept.
- **A past day:** 0–2,253 calls; asked 9–262 ms, weather 12–53 ms, total
  28–303 ms. About 0.1 ms a call.
- **Today, so far** (asked again about every 10 min): ~2,000–3,000 calls
  asked in 170–740 ms. Weather once slowed to 83–225 ms, otherwise 9–112.
- **One stall:** 21:03, 34,841 ms for 2,919 calls; the next ask took
  504 ms. The station or the network, not the size.
- **Filling 39 days took 54 s:** the 1.2 s rest between days
  (`station_archive.dart`), not the station.
- So the station's own API is fast enough; a companion server isn't needed
  for speed. A time limit on one ask is worth adding.
