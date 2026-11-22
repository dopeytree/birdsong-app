# The Flutter refactor: where it stands

Read this first in any new session. Then open only the doc the task needs
(`docs/README.md` says which). Updated 22 Nov 2026.

Branch: `flutter-plate-default` (from `flutter-plate-lab`, which holds the
map work). The full plan and its Progress table:
[Birdsong Flutter plate plan](https://claude.ai/artifact/XfdX9oyxDrxf5y6g9TDnxr)
(claude.ai artifact; may not be reachable from Claude Code).

## What the refactor is

The app's plate (the collage of bird plates, index, heading, buttons, map,
bird card) was a web page (`assets/web/index.html`, from dopeytree/birdsong)
shown in a web view. It has been rebuilt as native Flutter in `lib/native/`,
so the app (and later Flutter web) no longer needs the page.

**A faithful port:** "you are refactoring the old code into flutter. this
doesn't mean you are removing functions or design choices." Every behaviour
and look of the old plate carries over, then is improved on with Ed's say-so.

## State

- **Everything is ported:** collage, index, heading, buttons, views, bird
  card, share/save, settings, calendar, remote stations, the map.
- **The Flutter plate is the default** (22 Nov) for Listen here and remote
  stations. The old web page stays as a fallback: Settings → Experimental →
  Use the old web plate (`webPlate`; the old `nativePlate` key is no longer
  read, so every install switched once). Settings → Display shows the
  Flutter plate's options, plus Title and Date switches (`nativeShowTitle`,
  `nativeShowDate`); with the web plate on, it shows the page's own.
- **Remote stations** (BirdNET-Go, BirdWeather): name, dates, weather;
  Today/Week/Month/All; day/night; each day kept as a session folder
  (`stations/<id>/<day>/`), filled in automatically on a computer, after
  asking on a phone; Settings → Station history shows the log.
- **Wildlife pictures on the map are switched off** (see `map.md`).

## Built but not yet seen by Ed (all 22 Nov)

Ed needs to run `Build on Mac.command` and look at:
1. The app opening on the Flutter plate; Settings → Display.
2. Calendar sessions named by where the walk went ("Ashcott – RSPB Ham
   Wall", "Shapwick – Loxley Wood").
3. Ancient woods a shade deeper on the map (layers panel → Ancient woods).
   The shade is a first guess.
4. Standing stones' slight mark; Stonehenge and Calanais drawn (search
   "Stonehenge", Heritage on).
5. The map's timing readout off by default (Settings → Map, debug builds);
   no "Passed on the way" under the full-screen map.

Details of 2 to 4 are in `map.md`.

## Next steps

**Ask Ed before starting each piece** (his rule, 22 Nov).

1. Ed builds and checks the list above; tune what he asks for.
2. Later: achievements kept on the phone. Ed is weighing an age question
   and a safe mode for young people (UK Children's Code).
3. The app as Flutter web.
4. **Parked (Ed, 22 Nov):** the Birdsong companion server (Docker, reads
   `birdnet.db`). The station's own API is fast enough: see "Station fill
   timings" in `data-sources.md`.

## Offered, not yet answered

- Restyle the calendar grid.
- A time limit on one station ask (one stalled for 35 s).
- Ancient woods for Scotland and Wales; ancient sites from Historic
  Environment Scotland and Cadw.
- Write to RSPB about their data.
- A pull request for `flutter-plate-lab`; prune merged branches; remove the
  map's debug readout when done with it.
- Delete the web plate once Ed is happy without it.
