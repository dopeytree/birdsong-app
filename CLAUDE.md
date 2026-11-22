# Birdsong app: notes for Claude

Flutter app (macOS first, iPhone later) that listens for birds and shows
them as a vintage natural-history plate. Owner and designer: Ed.

**Start here:** `docs/flutter-refactor.md` (short: where things stand and
what's next). Then open only the doc the task needs; `docs/README.md` says
which. Don't read them all.

Rules in brief:
- Commit on the current branch; push every branch. `git add` by name.
- Ask Ed before large or visual decisions, and before starting the next
  piece of the refactor. Show an idea or a small test first. The look is
  vintage: paper, sepia ink, serif, engraved plates. Never modern or
  cartoon. Check `docs/decisions.md` before proposing a look.
- A faithful port: never remove a function or a design choice.
- Ed builds with `Build on Mac.command` (writes `build-log.txt`). A failed
  build still opens the previous app, so read the log first.
- Run `flutter analyze` and `flutter test` before saying it's done; the
  analyzer alone has missed compile errors here.
- No iPhone builds unless Ed asks.
- Never commit secrets, `.env`, signing files or the app's user data. The
  repo is public.
- Replies: short, plain British English.

## Cost (Ed's standing instruction: `docs/cost.md`)

Development has cost too much. So:
- **Delegate reading and routine work to the agents in `.claude/agents/`**,
  which run on cheaper models. Ed asks for this: use them without being
  asked again. `scout` (find code), `build-log` (read the build log),
  `checker` (analyze and test), `data-prober` (measure a data source),
  `doc-keeper` (update docs) are Haiku; `implementer`, `test-writer`,
  `reviewer` are Sonnet.
- The main session keeps: talking to Ed, design, the brief, the verdict.
  Do a small edit directly; an agent starts cold and costs its own tokens.
- Never read a large file whole (`walk_map.dart`, `native_plate.dart`):
  find the lines, then read the range. Filter command output.
- Don't load a skill unless the task needs it. This app makes no Claude API
  calls: never load `claude-api` here.
- When a piece of work is done, say so and suggest a new session for the
  next one: long sessions re-send their whole history every turn.
