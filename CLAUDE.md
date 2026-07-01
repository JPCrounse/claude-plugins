# claude-plugins-jp

Personal Claude Code plugin marketplace. The repository directory is `claude-plugins-jp`; the marketplace's registered name (in `.claude-plugin/marketplace.json`) is `jpcrounse-plugins` — install via `claude plugin install <plugin>@jpcrounse-plugins`.

## Structure

- `.claude-plugin/marketplace.json` — Marketplace registry listing all plugins
- `plugins/` — Each plugin lives in its own subdirectory
- `docs/` — Repo-level reference docs not tied to one plugin (e.g. `ai-token-optimization-guidance.md`, the token-cost rubric used when designing agents/skills)

## Plugin layout

Each plugin under `plugins/<name>/` follows standard Claude Code plugin structure:

```
plugins/<name>/
├── .claude-plugin/
│   └── plugin.json        # Plugin manifest
├── skills/                # Skills (SKILL.md per skill)
├── agents/                # Agent definitions (.md)
├── hooks/                 # Event hooks (hooks.json)
├── commands/              # Slash commands (.md, legacy)
├── scripts/               # Shell scripts invoked by hooks or commands
├── .mcp.json              # MCP server config (optional)
├── README.md              # Human-facing plugin overview (optional, recommended)
└── CLAUDE.md              # Plugin-level instructions for Claude (optional)
```

## Adding a plugin

1. Create the plugin directory under `plugins/`
2. Add `.claude-plugin/plugin.json` manifest
3. Add components (skills, agents, hooks, etc.)
4. Validate (see Validation section below)
5. Register in `.claude-plugin/marketplace.json` with a relative source path

## Current plugins

| Plugin | Version | Description |
|--------|---------|-------------|
| dev-orchestrator | 0.5.0 | Multi-phase development workflow: goal definition, autonomy selection, context collection (interactive or batch), roadmap generation, phased implementation, batch acceptance review, final review. Speed/efficiency/one-shot execution modes with cluster-based delegation, contract-affecting deviation detection via Affects annotations, per-phase or deferred acceptance. Token-efficiency design: subagent isolation, prompt-cache preservation, bounded handoffs, and cost-metric observability (agent-spawn proxies + one-shot spawn ceiling). 6 agents, 1 skill, PreCompact hook. |
| rpi-bugfix | 0.3.0 | Gated Research→Plan→Implement workflow taking a single bug from a Jira issue key to a verified PR. Thin orchestrator: delegates diagnosis (debug-error/bugsnag-triage methodology, bundled as a self-contained heuristics doc) and PR steps (self-review/pr-ci-fixer); three hard human gates (spec approval, reproduction confirmed, post-fix reproduction passes); per-phase pinned models (Opus research/validate/plan, Sonnet implement); code-graph impact validation feeding planning; resumable `.rpi-bugfix/<JIRA-KEY>/` state. Optional rapid-iteration mode (per-phase skill-improvement feedback loop with abort→implement→rewind) and a high/medium/low intensity dial (breadth-only; gates preserved). Requires bugsnag-triage (Jira+Bugsnag MCP + shared config). 4 agents, 1 skill, PreCompact hook. |

## Validation

- Validate plugin structure: use `plugin-dev:plugin-validator` agent on the plugin directory
- Review skill quality: use `plugin-dev:skill-reviewer` agent on any SKILL.md
- Validate hooks: check `hooks/hooks.json` matches Claude Code hook schema
- Validate JSON parses (no test runner here) after editing `marketplace.json` or any `plugin.json`:
  ```bash
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" .claude-plugin/marketplace.json && echo OK
  ```
  (`jq empty <file>` works too when `jq` is available.)

## Marketplace plugin entry format

```json
{
  "name": "plugin-name",
  "description": "Brief description",
  "version": "0.1.0",
  "source": "./plugins/plugin-name"
}
```

Both `"plugin-name"` and `"./plugins/plugin-name"` work because `pluginRoot` is set to `./plugins` in the marketplace metadata, but the explicit relative path is preferred for clarity and matches existing entries.

## Conventions

- Plugin names: kebab-case
- Versions: semver
- A plugin's version is duplicated in four hand-maintained places — keep them in sync on every bump: the plugin's `plugin.json`, its `marketplace.json` entry, the "Current plugins" table here, and the root `README.md` "Available plugins" table. (A plugin's own `README.md` should avoid hardcoding its version to reduce drift.)
- Source paths in marketplace.json use `./plugins/<name>` format (relative to pluginRoot, so just `"<name>"` works)
- Plugin READMEs: each plugin should have a human-readable `README.md` at its root for team-facing docs (workflow diagrams, mode tables, etc.). CLAUDE.md inside a plugin (optional) is for agent-facing instructions; README.md is for human readers. Don't duplicate content between them.
    
## Plugin development workflow

- Use these skills for best-practice structure:
  - `plugin-dev:create-plugin` — guided end-to-end plugin scaffolding
  - `plugin-dev:skill-development` — skill authoring (frontmatter, progressive disclosure)
  - `plugin-dev:agent-development` — agent authoring (description, examples, frontmatter)
  - `example-skills:skill-creator` — generic skill creation outside the plugin-dev workflow
- Always validate after changes (see Validation section)
- Test a plugin locally before registering it: `claude plugin install ./plugins/<name>` (from the repo root), or invoke its skills/agents directly in a session run from this directory.

## Style rules

- Skills: description uses third-person ("This skill should be used when..."), body uses imperative form
- Agents: description starts with "Use this agent when...", includes 2-4 `<example>` blocks, system prompt uses second person
- Agent colors: blue=analysis, cyan=review, green=generation, yellow=input, magenta=orchestration, red=critical
- Agent model options: `inherit` (recommended default), `sonnet`, `opus`, `haiku`
- Agent effort options: `low`, `medium`, `high`, `xhigh`, `max` (model-dependent availability). Match to the agent's role: planning/judgment-heavy → `xhigh` or `max`; execution → `high`; read-only reporting → `low`.
- Agent `maxTurns` (optional): caps the agent's internal tool-call iterations; set it for long-running or delegating agents (this repo: `phase-implementer` 50, `cluster-implementer` 100) and omit it for short or read-only ones.
- Tools: apply principle of least privilege per agent role
- Token efficiency: keep agent system prompts and standard task-brief templates **static** (no timestamps, run IDs, or dynamically-built tool/context lists in the prefix) so repeated invocations hit the prompt cache; design handoffs to be compact (~1–2K tokens). Rationale: `docs/ai-token-optimization-guidance.md`.
- Agent `disallowedTools` (optional): a denylist subtracted from the granted (or inherited) `tools`; use it when blocking a few tools reads cleaner than enumerating an allowlist, but keep the `tools` allowlist as the primary least-privilege lever.

## Versioning policy

- **Major version 0 plugins are pre-release**: only the author has used them. While `version` in `plugin.json` and `marketplace.json` is still `0.x.y`, do NOT write legacy notes, backwards-compatibility shims, "treat absent field as X for older workflows", schema-version changelog narration, or migration guides. Drop or remove such language on sight — the plugin's authoritative spec is its current state, not its history.
- **Bumping to 1.0.0 is the shared/released milestone**: from `1.0.0` onward, legacy docs and backwards-compat become relevant (other users may have state files from prior versions). Schema-evolution notes, "absent = legacy default" handling, and migration guides start being written at the `1.0.0` boundary.
- **Prompt the user about the version bump after edits**: when a working session modifies a skill, agent, or schema in a plugin whose current `version` major is `0`, after the edits are complete ask the user explicitly: *"Should these changes bump <plugin> to v1.0.0 (released/shared milestone), or stay on 0.x?"* Frame the question by listing what changed. Do not auto-bump to 1.0.0 without asking. Routine 0.x → 0.(x+1).0 minor bumps remain a judgment call inside the session and do not require this prompt.

## Gotchas

- PreCompact IS a valid hook event despite some validators not recognizing it
- `*-workspace/` directories under any plugin are gitignored (`plugins/*/*-workspace/`) — runtime/eval artifacts (e.g. `orchestrate-workspace/` from the orchestrate skill, eval dirs from skill-creator runs)

## Environment notes

- Windows (Git Bash): use Unix paths in shell, `chmod +x` works but may not persist
- Shell scripts: use `#!/usr/bin/env bash`, `set -euo pipefail`, check for tool availability (e.g., `jq`)
- `${CLAUDE_PLUGIN_ROOT}` for portable paths in hooks and scripts
- `.claude.local.md` files are for personal preferences — add to `.gitignore` if used
