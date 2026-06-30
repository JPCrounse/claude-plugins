# rpi-bugfix — maintainer notes (agent-facing)

Invariants to preserve when editing this plugin. (Human-facing overview is in `README.md`; do not duplicate it here.)

## Core principle: thin orchestrator
rpi-bugfix orchestrates a gated Research→Plan→Implement ceremony and **delegates** the work. Do not reimplement diagnosis, pre-push review, or CI fixing here — delegate to the `debug-error`/`bugsnag-triage` methodology (bundled as `references/diagnostic-heuristics.md`), `self-review`, and `pr-ci-fixer`. If you find yourself adding triage logic, stop and delegate instead.

## Delegation mechanics (do not break these)
- **No agent is granted the `Skill` tool.** Agents are autonomous, non-interactive leaves. The main thread (SKILL.md) is the only place that invokes skills (`self-review`, `pr-ci-fixer`) and the only place that interacts with the user.
- **The interview and all three hard gates live in the main thread** — agents cannot do live user Q&A. Pass agents a fully-assembled brief.
- **The four agents form the layered context-isolation chain:** raw Jira/Bugsnag payloads die in `bug-researcher`; `codegraph_explore` dumps die in `codegraph-validator`. Only distilled `.md` artifacts cross phase boundaries (`spec.md` → `impact-analysis.md` → `plan.md`), and only ~1–2K-token handoffs return to the main thread. Never let a downstream agent re-load upstream raw context.

## Prompt-cache hygiene
Keep every agent system prompt and task-brief template **static**. Never put the `<JIRA-KEY>`, branch name, timestamps, or a dynamically-assembled tool list in a prompt **prefix** — per-invocation variables go in the task-brief **suffix**. `bug-researcher` and `bug-implementer` are re-invoked within a run (open-question loop, re-plan loop); a stray key in the prefix forfeits the cache discount on every call.

## Hard dependency
The Jira/Bugsnag MCP tools in `bug-researcher`'s allowlist are provided by the **`bugsnag-triage`** plugin (`mcp__plugin_bugsnag-triage_*`). rpi-bugfix does **not** ship its own `.mcp.json` — adding one would double-register those servers. If you change the MCP coupling, update the README prerequisite and the researcher's `tools`.

## Gates are non-negotiable
The three hard gates (spec approval, reproduction confirmed, post-fix reproduction passes) are the product's safety guarantee. Do not add a mode that skips them. G2 is waivable for heisenbugs (which forces G3 to be waived and the PR to be flagged unverified) — that is the only relaxation.

## Versioning
Pre-release (`0.x`). Per the repo policy, write no legacy/back-compat/migration notes while major version is 0. The plugin's own README must not hardcode the version (the four synced version locations are in the root `CLAUDE.md`).
