# The Flutter refactor: where it stands

Read this first in any new chat about the refactor. Branch: `flutter-plate-lab`.
The full plan and its Progress table: [Birdsong Flutter plate plan](https://claude.ai/artifact/XfdX9oyxDrxf5y6g9TDnxr).
Updated 21 Nov 2026.

## What the refactor is

The app's plate (the collage of bird plates, index, heading, buttons, map, bird
card) was a web page (`assets/web/index.html`, from dopeytree/birdsong) shown
in a web view. It is being rebuilt as native Flutter, in `lib/native/`, so the
app (and later Flutter web) no longer needs the page.

**A faithful port:** "you are refactoring the old code into flutter. this
doesn't mean you are removing functions or design choices." Every behaviour
and look of the old plate carries over (hover grow, fades, marks, paper, fit,
the 60 cap, etc.), then is improved on with Ed's say-so.

The Flutter plate is behind Settings → Experimental → Flutter plate
(`nativePlate`, off by default). It shows both Listen here and remote stations.

## How we work

- **Ask before large decisions;** check in for input. Ed is the designer.
- **Always push work on our branches,** so a new branch never clashes locally.
- **Tick progress off** in the task list and in the plan doc's Progress table.
- **No iPhone builds** until the app is complete, unless Ed asks.
- **Ed builds after each change** with `Build on Mac.command`, which writes
  `build-log.txt`. Read it yourself: grep `STATUS`, `error •`,
  `Failing tests`; `git reflog --date=format:%H:%M:%S` shows which commit it built.
- **Getting commits to the Mac** (`/Users/ed/birdsong-app`, which the cloud
  can't push to directly): `git bundle create` the new commits, copy the bundle
  into `build/`, then on the Mac `git fetch build/X.bundle
  flutter-plate-lab:refs/remotes/origin/flutter-plate-lab && git merge
  --ff-only origin/flutter-plate-lab` and delete the bundle. Git on the
  Mac needs permission to delete files, or it leaves `.lock` files behind.
- When editing with scripts, assert each replacement matched; a silent
  miss broke a test once.
- Flutter 3.50 on the Mac; Dart SDK lower bound 3.7 (no null-aware map
  elements). `RenderRepaintBoundary` comes from `package:flutter/rendering.dart`;
  latlong2 exports `Path`, so use `ui.Path`.

## Done (all built and passing on the Mac)

- **Collage:** hover grow, fade, latest mark, glow, oval, paper, fit to
  screen, 60 cap, pinch zoom.
- **Index:** folded inline above the buttons, reading "Index of Species | 123";
  ‹ › to flip sessions or days.
- **Heading:** title in small capitals (setting), #n/n, date, coordinates,
  weather icon and °C; Heading lines black by default; totals off by default.
- **Buttons:** view and map bottom-left, calendar and share bottom-right;
  record, source pill, stations (+) and menu top-right.
- **Views:** in this order: recent ramblings (opens on it, index folded), latest, most calls, index
  alone, collage alone (no heading), and two more.
- **Bird card:** with audioplayers (clips, recordings, spectrograms).
- **Share/save, caption, limit species, skulls/wings/eggs.**
- **Map, part one:** flutter_map, OpenFreeMap tiles, contours from terrarium
  elevation, trail and crosses; the station's spot.
- **Calendar:** sessions under place names (OpenStreetMap Nominatim, cached).
- **Remote stations** (BirdNET-Go and BirdWeather):
  - Name beside the title (#garden); dates under it; coordinates; the day's
    weather when one day is showing.
  - Today, Week, Month, All: top centre on wide screens, under the buttons
    on phones. Opens on Today.
  - Day/night/all toggle (sunrise to sunset).
  - The calendar treats each day as a session and greys days with nothing heard.
  - Each day is kept as a session folder (`stations/<id>/<day>/`); past days
    are filled in automatically on a computer, and only after asking on a
    phone. Settings → Station history shows the log.
- **Settings:** the same full menu in both modes.

## Next steps, in order

1. **Check the latest build** of `b800b3b` (Station history) and Ed's fill-log
   timings. The companion server depends on how long filling in takes.
2. **Map, part two:** heritage, nature sites, Wikipedia, "Passed on the way".
3. **The app as Flutter web.**
4. **Then:** the Birdsong companion server (Docker, reads `birdnet.db`; plan:
   https://claude.ai/artifact/1KUPP1PLKcwMLGw2NDADWz).

## Offered, not yet answered

- Make the Flutter plate the default (and switch it on for existing installs).
- Restyle the calendar grid.
- Move the Experimental options into Display.
- Quick fixes:
  - Commit `pubspec.lock`.
  - Ignore `android/`, `ios/`, `macos/`, `.bootstrap/`.
  - A pull request for `flutter-plate-lab` (69+ commits ahead of main).
  - Prune merged branches.

## Where things are

- **Plate:** `lib/native/` (native_plate, collage_view, index_view, bird_card,
  day_picker, walk_map, contours, station_feed, station_archive,
  plate_library).
- **Shared buttons:** `lib/ui/plate_buttons.dart`.
- **Settings:** `lib/settings.dart` (`native*` fields), with the screen in
  `lib/ui/settings_screen.dart`.
- **Tests:** `test/`.
