# claude-plugins-jp

Personal Claude Code plugin marketplace.

## Structure

- `.claude-plugin/marketplace.json` — Marketplace registry listing all plugins
- `plugins/` — Each plugin lives in its own subdirectory

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
├── .mcp.json              # MCP server config (optional)
└── CLAUDE.md              # Plugin-level instructions (optional)
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
| dev-orchestrator | 0.3.0 | Multi-phase development workflow: goal definition, autonomy selection, context collection (interactive or batch), roadmap generation, phased implementation, batch acceptance review, final review. Speed/efficiency/one-shot execution modes with cluster-based delegation, contract-affecting deviation detection via Affects annotations, per-phase or deferred acceptance. 6 agents, 1 skill, PreCompact hook. |

## Validation

- Validate plugin structure: use `plugin-dev:plugin-validator` agent on the plugin directory
- Review skill quality: use `plugin-dev:skill-reviewer` agent on any SKILL.md
- Validate hooks: check `hooks/hooks.json` matches Claude Code hook schema

## Marketplace plugin entry format

```json
{
  "name": "plugin-name",
  "description": "Brief description",
  "version": "0.1.0",
  "source": "plugin-name"
}
```

## Conventions

- Plugin names: kebab-case
- Versions: semver
- Source paths in marketplace.json use `./plugins/<name>` format (relative to pluginRoot, so just `"<name>"` works)
    
## Plugin development workflow

- Use `/plugin-dev:create-plugin`, `/skill-creator`, `/plugin-dev:agent-development` skills for best-practice structure
- Always validate after changes (see Validation section)

## Style rules

- Skills: description uses third-person ("This skill should be used when..."), body uses imperative form
- Agents: description starts with "Use this agent when...", includes 2-4 `<example>` blocks, system prompt uses second person
- Agent colors: blue=analysis, cyan=review, green=generation, yellow=input, magenta=orchestration, red=critical
- Agent model options: `inherit` (recommended default), `sonnet`, `opus`, `haiku`
- Agent effort options: `low`, `medium`, `high`, `xhigh`, `max` (model-dependent availability). Match to the agent's role: planning/judgment-heavy → `xhigh` or `max`; execution → `high`; read-only reporting → `low`.
- Tools: apply principle of least privilege per agent role

## Versioning policy

- **Major version 0 plugins are pre-release**: only the author has used them. While `version` in `plugin.json` and `marketplace.json` is still `0.x.y`, do NOT write legacy notes, backwards-compatibility shims, "treat absent field as X for older workflows", schema-version changelog narration, or migration guides. Drop or remove such language on sight — the plugin's authoritative spec is its current state, not its history.
- **Bumping to 1.0.0 is the shared/released milestone**: from `1.0.0` onward, legacy docs and backwards-compat become relevant (other users may have state files from prior versions). Schema-evolution notes, "absent = legacy default" handling, and migration guides start being written at the `1.0.0` boundary.
- **Prompt the user about the version bump after edits**: when a working session modifies a skill, agent, or schema in a plugin whose current `version` major is `0`, after the edits are complete ask the user explicitly: *"Should these changes bump <plugin> to v1.0.0 (released/shared milestone), or stay on 0.x?"* Frame the question by listing what changed. Do not auto-bump to 1.0.0 without asking. Routine 0.x → 0.(x+1).0 minor bumps remain a judgment call inside the session and do not require this prompt.

## Gotchas

- PreCompact IS a valid hook event despite some validators not recognizing it
- `*-workspace/` directories under plugins are gitignored eval/test artifacts from skill-creator runs

## Environment notes

- Windows (Git Bash): use Unix paths in shell, `chmod +x` works but may not persist
- Shell scripts: use `#!/usr/bin/env bash`, `set -euo pipefail`, check for tool availability (e.g., `jq`)
- `${CLAUDE_PLUGIN_ROOT}` for portable paths in hooks and scripts
- `.claude.local.md` files are for personal preferences — add to `.gitignore` if used
