# Keeping development cheap

Updated 22 Nov 2026. Development cost about £200 in 48 hours. These are
the habits that bring it down, biggest saving first.

## 1. One task, one session

A long session re-sends its whole history on every turn. The 21–22 Nov
session ran the map fixes, walk names, ancient woods, ancient sites and
the default-plate switch in one conversation, so late turns carried all of
it. Start a new session for each piece of work. The docs here are what
carries the context over, not the chat.

## 2. Pick the model for the job

API list prices per million tokens (3 Nov 2026), input / output:

| Model | Price | Use for |
|---|---|---|
| Fable 5.2 | $8 / $40 | Almost never here. On the Pro plan it is paid from usage credits, not the subscription |
| Opus 5.5 | $4 / $20 | The main session when the work needs judgement: design with Ed, planning, hard bugs |
| Sonnet 5.5 | $2 / $10 | The main session for routine, well-specified work; the `implementer`, `test-writer`, `reviewer` agents |
| Haiku 5.5 | $0.10 / $0.50 | Finding code, reading logs, running checks, probing data, updating docs |

Haiku is about 40 times cheaper than Opus 5.5. `/model` changes the main
session's model.

## 3. Hand the reading to cheap agents

The agents in `.claude/agents/` each run on the cheapest model that does
the job well, and return a few lines instead of filling the main session
with file contents and tool output.

| Agent | Model | Does |
|---|---|---|
| `scout` | Haiku | Finds where something is; returns `file:line` |
| `build-log` | Haiku | Reads `build-log.txt`; says worked or failed, and which commit |
| `checker` | Haiku | Runs `flutter analyze` and `flutter test`; returns only failures |
| `data-prober` | Haiku | Measures what an open data source holds |
| `doc-keeper` | Haiku | Updates the docs after a piece of work |
| `implementer` | Sonnet | Makes one decided, well-specified change and proves it |
| `test-writer` | Sonnet | Writes tests for named behaviour |
| `reviewer` | Sonnet | Reads a diff for what the analyzer misses |

The main session keeps: talking to Ed, design, deciding what to build,
writing the brief, and judging the result.

**When not to delegate.** An agent starts cold and costs its own tokens.
A two-line edit, or a change that needs everything already in the main
session's head, is cheaper done directly. Delegate reading-heavy and
mechanical work; a brief should name the files and what done looks like.

## 4. Read less

- `docs/flutter-refactor.md` first, then only the doc the task needs.
- Never read a 2,000-line file whole: find the lines (`scout`, or `grep
  -n`), then read that range.
- Filter command output: `grep` for errors, `tail` the test run.
- Don't load a skill "just in case". Loading `claude-api` by mistake cost
  tens of thousands of tokens for nothing.

## 5. Decide before building

The dearest work on 21–22 Nov was built and then undone (the blackletter
font and site symbols). A mock-up or a rendered PNG first (`render-painter`
skill) costs little; Ed's verdict then goes in `decisions.md`.

## 6. Fewer plugins

Every enabled plugin adds its skills, agents and connectors to every
session's opening context. They are enabled on Ed's claude.ai account (for
every project, not per repo), so only Ed can switch them off, in the Claude
app's plugin settings. Checked 22 Nov 2026: eleven are on.

Keep (used here):
- Flutter engineering skills (`flutter:*`)
- The official Dart and Flutter plugin (`dart-flutter:*`, Dart MCP server)
- `zizi-skills` (git-sync, handoff)
- Ed's own `birdsong-web-sync`

Switch off (not used by this app):
- Engineering workflows (`engineering:*`): also brings seven connectors
  that wait for sign-in (Asana, Atlassian, Datadog, GitHub, Linear,
  Notion, PagerDuty, Slack)
- Data (`data:*`): Amplitude, BigQuery, Definite, Hex connectors
- Design workflows (`design:*`): Figma, Intercom connectors
- Claude Security (`claude-security`): seven agents
- Frontend design, Skill creator
- The second Flutter pack (`flutter-skills:*`): Riverpod, Freezed,
  go_router, Flame, none of which this app uses

Ed's call: `superpowers`. We use one skill from it
(`systematic-debugging`), but its start-of-session rule tells Claude to
load a skill whenever one might apply, which is how `claude-api` got
loaded. Off is cheaper; on keeps that debugging skill.
