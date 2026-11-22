# How we work (Ed's rules)

Updated 22 Nov 2026. See also `cost.md` and `decisions.md`.

- **Ed is the designer.** Ask before large or visual decisions; show an
  idea or a small test first (`render-painter` skill, or a mock-up). The
  look is vintage natural history: paper, sepia ink, serif (IM Fell
  English), engraved plates. Never modern or cartoon.
- **Ask before starting the next piece of the refactor.**
- **Ed is cost-sensitive.** Measure before guessing; don't redo work; keep
  replies short and in plain English.
- **Commit on the current branch and push every branch** so nothing clashes
  locally. `git add` files by name.
- **No iPhone builds** until the app is complete, unless Ed asks.
- **Never commit** secrets, `.env`, signing files, `.harness/`,
  `build-log.txt` or the app's user data. The repo is public.

## Builds

Ed runs `Build on Mac.command`: it bootstraps, analyzes, runs the tests,
builds macOS and opens the app, writing `build-log.txt`.
**A failed build still opens the previous app.** Check the log before
trusting what Ed sees (`build-check` skill, `build-log` agent).

Locally, run `flutter analyze` and `flutter test` before saying it's done.

The app is sandboxed: its data (fill logs, `stations/`) is under
`~/Library/Containers/…`. Ask Ed to paste what's needed.

## Traps that have bitten

- **Don't trust the analyzer alone.** It has missed real compile errors: a
  const `StrokePattern.dashed(...)` (never make it const on flutter_map
  8.3), and a missing import (`CustomPainter` is in
  `package:flutter/rendering.dart`, not `painting.dart`). Run the tests
  and read changed code by eye.
- **Isolates:** call `Isolate.run` from a top-level function, never from a
  closure inside a widget's async method (it drags the State along and
  fails to send).
- **Errors:** no `catch (_) {}`; `debugPrint` them.
- **Dashed polygon borders** on flutter_map are worked out along the whole
  outline on the screen's thread (11.5 s frames in Falmouth). Draw edges as
  polylines cut to the view (`clipLine`, `_edgeLines`).
- **Never run `dart format` on a whole file:** it rewrote all of
  `native_plate.dart` (1,700 changed lines).
- **Editing with scripts:** assert each replacement matched once.
- **Saved settings:** a changed default doesn't reach installs that have
  the old value saved. Rename the key if every install must change.
- **macOS text fields** lose focus before a tap lands: wrap in
  `TextFieldTapRegion`.
- `latlong2` exports `Path`: use `ui.Path`.

## Versions

Flutter 3.50 (`material.dart` deprecated in favour of `material_ui`: infos
only), Dart SDK lower bound 3.7, flutter_map 8.3.2,
flutter_map_vector_tiles 2.12 (supports `fill-pattern`, symbol icons,
`global-state`; its MVT decoder isn't exported, so `lib/native/mvt.dart` is
ours), latlong2 0.9.1.

## Git through Claude's Cowork bridge (not Claude Code)

Ask for delete permission before committing so git can remove `.lock` and
`tmp_obj_*` files; that shell has no network, so Ed pushes from his
terminal. Commits need an identity: `git -c user.name=… -c user.email=…`
(copy them from `git log -1`).
