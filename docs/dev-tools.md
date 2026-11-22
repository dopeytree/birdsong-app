# Other coding tools on Ed's Mac (researched 22 Nov 2026)

For cutting cost by mixing Claude, Grok and local models. Nothing here is
set up for this repo yet: it is what was found, and a proposed setup.

## What is installed (M3, 18 GB)

| Tool | Version | What it is | State |
|---|---|---|---|
| Claude Code | | Anthropic's coding agent; reads `CLAUDE.md`, `.claude/agents`, `.claude/skills` | In use |
| opencode | 2.3.2 | Open-source coding agent (terminal, desktop app, VS Code extension). Any provider; each agent can have its own model | Claude and xAI signed in; five agents defined, all on one model |
| Grok Build (`grok`) | 1.0.92 | xAI's coding agent CLI. `grok -p "…"` runs one prompt and exits | Installed |
| Locals | 0.2.2 | Runs local models (MLX) for agents; OpenAI-compatible at `http://127.0.0.1:8321/v1` | Running, serving Qwen3.5-2B |
| OMO (`omo`) | 5.1.81 | Oh My OpenAgent: orchestration on top (a main agent hands tasks to worker categories, each with its own model). Source-available (SUL-1.0) | Binary installed, not set up |
| Ollama | | Another local model runner | No models |

## Problems found

- opencode's default model is **Inkling 2 Mini**, but Locals is serving
  **Qwen3.5-2B**. Inkling 2 Mini is a 16 GB build needing a 24 GB Mac, so it
  can't run here.
- opencode's agents (orchestrator, coder, researcher, tester, reviewer) all
  inherit that one model: no cheap/dear split yet.

## What works across tools already

- opencode reads `CLAUDE.md` when there is no `AGENTS.md`, and reads
  `.claude/skills/*/SKILL.md`. So this repo's rules and five project skills
  apply there unchanged.
- opencode does not read `.claude/agents`. Its agents live in
  `.opencode/agents/<name>.md` with `mode` and `model` in the frontmatter.
- The Flutter plugin skills are on Ed's claude.ai account, not on disk, so
  opencode can't see them. Skill files would need to be in
  `~/.config/opencode/skills/`.

## Proposed setup (not built)

One tool, opencode, with three tiers in `.opencode/agents/`:
- **orchestrator:** Claude (`claude-agent/opus` or a Sonnet): talks to Ed,
  plans, writes briefs, judges.
- **coder, tester-writer:** Grok (`xai/grok-4.7` or the cheapest that
  copes).
- **scout, checker, doc-keeper:** local (`locals/…`), free.

All-local trial: switch Locals to Qwen3.5-4B (2.8 GB, its default for Macs
over 12 GB). A 2B or 4B model suits finding code, running checks and small
edits; expect it to struggle with changes inside the 2,000-line files.

## Not verified

- Whether opencode's Claude sign-in draws on the Pro plan or on usage
  credits, and whether Anthropic's terms allow a subscription login there.
- Whether Grok through opencode is covered by SuperGrok or billed to an xAI
  API key (sources disagree; Grok Build itself is covered).
- OMO's docs don't cover local models or xAI setup.

## The oh-my-openagent install guide (read, not run)

It needs Bun (not installed), adds a plugin to the global opencode config,
writes `~/.omo/omo.jsonc`, asks which subscriptions you have, signs opencode
in to Claude Pro/Max, sends anonymous usage telemetry to PostHog in the US
(off with `OMO_DISABLE_TELEMETRY=1`), and `omo setup` copies opencode's API
keys into `~/.omo/agent/auth.json`.
