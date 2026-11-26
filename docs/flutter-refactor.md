# The Flutter refactor: where it stands

Read this first in any new session. Then open only the doc the task needs
(`docs/README.md` says which). Updated 25 Nov 2026.

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

## Built, awaiting Ed's next check (25 Nov)

Ed checked the 22–23 Nov items (Flutter plate, walk names, model updates,
song scribble all good) and asked for these refinements, now built:
1. Ancient woods lightened (`#3F5A2A` at 32%, down from 60%).
2. Map search bar and full-screen button match the clean zoom buttons on
   the left (no extra inner hairline).
3. Song scribble mode setting (`Settings → Display → Song scribble`):
   `Pencil scribble (default)`, `Simple wave (black, lighter)` (single-pass
   black waveform at 30 fps for slower devices), or `Off`. Also shown on
   remote stations as the matching resting line with the station's latest
   detected bird held in the gap until the next update.
4. Remote mode stations button uses `±` instead of `+`; BirdWeather station
   parser ignores `#` in numbers or URLs.
5. Settings screen uses `✕` top right instead of `<` top left.
6. Customisable ignored species list (`Settings → Listening → Ignored
   species`), defaulting to Human, Humans, Dog, Engine, Domestic sounds,
   Home sounds, Harbor Seal — filtered everywhere (listening, plates, index
   of species, maps, calendar counts, both local and remote).

Details in `map.md` and `decisions.md`.

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
- Bat models (need an ultrasonic mic at 192 kHz or more).
- Rename the local folder `birdsong-app` → `birdsongs.ai` (the GitHub repo
  already is); check `Build on Mac.command` and `.claude/` for the old path.

## Recent work (23 Nov)

- `site/`: Astro splash page with IM Fell English fonts, CSS-drawn iPhone
  and iPad frames, shots in `site/public/shots/`. GitHub Pages workflow
  (`site.yml`) publishes to https://birdsongs.ai/ (live since 23 Nov 2026; custom domain, dopeytree.github.io/birdsongs.ai redirects) whenever `site/` changes on `main`.
