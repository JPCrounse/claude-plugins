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
| dev-orchestrator | 0.1.0 | 5-phase development workflow: goal definition, context collection, roadmap generation, phased implementation, final review. 5 agents, 1 skill, PreCompact hook. |

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
- Tools: apply principle of least privilege per agent role

## Gotchas

- PreCompact IS a valid hook event despite some validators not recognizing it
- `*-workspace/` directories under plugins are gitignored eval/test artifacts from skill-creator runs

## Environment notes

- Windows (Git Bash): use Unix paths in shell, `chmod +x` works but may not persist
- Shell scripts: use `#!/usr/bin/env bash`, `set -euo pipefail`, check for tool availability (e.g., `jq`)
- `${CLAUDE_PLUGIN_ROOT}` for portable paths in hooks and scripts
- `.claude.local.md` files are for personal preferences — add to `.gitignore` if used
