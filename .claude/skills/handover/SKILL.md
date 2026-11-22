---
name: handover
description: Finish a piece of work: checks, docs, commit, push, and a short report to Ed. Use when a change is complete, before saying it is done.
---
# Finishing a piece of work

1. **Check.** `flutter analyze` and `flutter test` (the `checker` agent).
   The analyzer alone has missed compile errors here. Read the diff by eye
   (the `reviewer` agent for more than a few lines).
2. **Docs** (the `doc-keeper` agent, given a short list of what changed):
   - `docs/flutter-refactor.md`: state and next steps. Keep it under about
     80 lines: it is read at the start of every session.
   - The topic doc for the detail (`map.md`, `data-sources.md`).
   - `docs/decisions.md` for anything Ed approved or rejected.
   - Mark anything Ed hasn't seen in the app as "not yet seen".
3. **Commit** on the current branch, only your own files (`git add` by
   name, never `-A` at the root: `.harness/`, `build-log.txt` and signing
   files must stay out). One subject line saying what changed for the
   user, a short body, the attribution line.
4. **Push** the branch.
5. **Tell Ed**, briefly: what changed, where to find it in the app, that
   the checks pass, and that it isn't seen until he runs
   `Build on Mac.command`. No iPhone builds unless he asks.
6. **Ask before the next piece.** Ed decides what comes next.
