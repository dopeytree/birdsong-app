# Skills for this repo

Two kinds.

## Project skills (in this folder, loaded by Claude Code automatically)

| Skill | Use it when |
|---|---|
| `build-check` | Ed has run `Build on Mac.command`, or reports something odd in the app |
| `render-painter` | A drawn thing (a `CustomPainter`) needs looking at before Ed builds |
| `new-map-layer` | Adding a kind of place or area to the map |
| `measure-data-source` | Before building on any open data source |
| `handover` | A piece of work is finished: update the docs, commit, push |

## Plugin skills we use (installed on Ed's machine, not copied here)

They belong to their plugins, and this repo is public, so they are listed,
not copied. Load one only when the task needs it: each costs tokens.

| Skill | For |
|---|---|
| `flutter:flutter-performance` | Slow frames, rebuild scope, isolates, measuring |
| `flutter:custom-canvas-and-gestures` | `CustomPainter`, hit-testing, gestures on the map |
| `flutter:widget-composition` | Splitting large build methods |
| `flutter:async-safety` | Mounted checks, no swallowed errors |
| `superpowers:systematic-debugging` | A bug with no obvious cause: measure first (it found Falmouth) |
| `zizi-skills:git-sync` | Own branch, push every branch |
| `birdsong-web-sync:birdsong-web-sync` | Ed's own: moving features between the web page (dopeytree/birdsong) and this app |

Not needed here, and expensive when loaded by mistake: `claude-api`
(this app makes no Claude API calls), the `data:*` and `engineering:*` packs.
