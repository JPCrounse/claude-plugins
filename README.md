# claude-plugins-jp

Personal Claude Code plugin marketplace by JPCrounse.

## Installation

Add the marketplace, then install plugins from it:

```bash
claude plugin marketplace add <git-url-or-local-path>
claude plugin install <plugin-name>@jpcrounse-plugins
```

The marketplace's registered name is `jpcrounse-plugins` (see `.claude-plugin/marketplace.json`).

## Available plugins

| Plugin | Version | Description |
|---|---|---|
| [dev-orchestrator](plugins/dev-orchestrator/README.md) | 0.4.0 | Multi-phase development workflow with cross-session state. Supervised or one-shot autonomy; speed or efficiency execution; per-phase or deferred acceptance; interactive or batch guidance collection. Contract-affecting deviation detection via per-item `Affects:` annotations. |

See each plugin's own `README.md` (linked above) for usage details.

## Repository layout

```
claude-plugins-jp/
├── .claude-plugin/
│   └── marketplace.json        # Marketplace registry
├── plugins/
│   └── <plugin-name>/
│       ├── .claude-plugin/plugin.json
│       ├── skills/             # Skills (SKILL.md per skill)
│       ├── agents/             # Agent definitions (.md)
│       ├── hooks/              # Event hooks (hooks.json)
│       ├── commands/           # Slash commands (.md)
│       ├── scripts/            # Shell scripts for hooks etc.
│       ├── .mcp.json           # MCP server config (optional)
│       └── README.md           # Plugin-level documentation
├── CLAUDE.md                   # Repo-wide guidance for Claude Code
└── README.md                   # This file
```

## Adding a plugin

1. Create the plugin directory under `plugins/<your-plugin>/`.
2. Add `.claude-plugin/plugin.json` with `name`, `version`, `description`.
3. Add components (skills, agents, hooks, commands, MCP servers as needed).
4. Validate the plugin (see Validation below).
5. Register it in `.claude-plugin/marketplace.json` with a relative source path (`"source": "./plugins/<your-plugin>"`).

## Validation

- Plugin structure: spawn the `plugin-dev:plugin-validator` agent against the plugin directory.
- Skill quality: spawn the `plugin-dev:skill-reviewer` agent against any `SKILL.md`.
- Manual sanity-check: confirm `hooks/hooks.json` matches the Claude Code hook schema and that every agent's frontmatter has `name`, `description`, `model`, `tools`.

## Conventions

- Plugin names: kebab-case (e.g. `dev-orchestrator`).
- Versions: semver. **Major version 0 is pre-release** — no legacy docs or backwards-compatibility shims are written while a plugin is at `0.x`. Bumping to `1.0.0` is the released/shared milestone (see `CLAUDE.md` for the full policy).
- Source paths in `marketplace.json`: `./plugins/<name>` relative to repository root.
- Agent style: see `CLAUDE.md` for description format, model/effort options, and color conventions.

## Further reading

- `CLAUDE.md` — full author conventions, gotchas, versioning policy, and environment notes
- `plugins/dev-orchestrator/README.md` — the dev-orchestrator plugin overview and workflow diagram
