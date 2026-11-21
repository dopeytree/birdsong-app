# Birdsong app: notes for Claude

Flutter app (macOS first, iPhone later) that listens for birds and shows
them as a vintage natural-history plate. Owner and designer: Ed.

**Start here:** `docs/flutter-refactor.md` (state of the Flutter refactor,
how we work, next steps, licences, where things are).

Rules in brief:
- Work on branch `flutter-plate-lab`; commit there; push every branch.
- Ask Ed before large or visual decisions; show ideas or a small test first.
  The look is vintage: paper, sepia ink, serif, engraved plates. Never
  modern or cartoon.
- Be token-efficient: measure, don't guess; read only what you need.
- Ed builds with `Build on Mac.command` (writes `build-log.txt`). A failed
  build still opens the previous app, so read the log first.
- Locally, run `flutter analyze` and `flutter test` before saying it's done;
  the analyzer alone has missed compile errors here.
- No iPhone builds unless Ed asks.
- Never commit secrets, `.env`, signing files or the app's user data.
