---
name: build-check
description: Read build-log.txt after Ed runs "Build on Mac.command" to say whether the build worked and which commit it built. Use when Ed says he has built or that the app looks wrong.
---
# Checking Ed's build

Ed builds with `Build on Mac.command`. It bootstraps, analyzes, runs the
tests, builds macOS, opens the app and writes `build-log.txt`.

**A failed build still opens the previous app.** Never trust what Ed sees
until the log says the build worked.

Do not read the whole log (about 180 lines, mostly passing tests). Run:

```bash
grep -n "STATUS\|error •\|Failing tests\|^=== " build-log.txt
git reflog --date=format:%H:%M:%S -5
git status --short
```

- Every stage should say `STATUS: …-ok` (bootstrap, analyze, test, build),
  then `STATUS: opened`.
- Compare the log's start time (`=== …`) with the reflog to name the commit
  that was built. If HEAD moved after that time, Ed is not looking at the
  latest code: say so.
- 22 `info •` lines are expected (the `material.dart` deprecation and a few
  lints). Only a new kind matters.
- "settings: could not save (PathNotFoundException…)" in the test output is
  harmless: a test's temporary folder was removed before a last save.

Prefer the `build-log` agent for this: it is cheap and returns a few lines.

The log proves it compiles and the tests pass. It does not prove the app
looks or behaves right: that needs Ed's eyes. Say which is which.
