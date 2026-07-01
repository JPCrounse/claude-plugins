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

## Rapid-iteration mode & intensity (invariants)
- **Rapid mode is additive, never a gate-relaxation.** The per-phase feedback checkpoint fires *after* each phase's gate/handoff, never before — it cannot front-run G1/G2/G3. Do not let "rapid" become a fast-path that skips a gate.
- **Rapid-mode feedback targets the skill, not the bug.** `session-feedback.md` collects notes for improving *this plugin's* source (SKILL.md/agents/references). "Implementing" feedback edits the plugin — not `spec.md`/`plan.md` (the gates already let the user edit those directly). If the working tree isn't the plugin repo, surface the list; do not edit blindly.
- **Intensity trims breadth only.** `high`/`medium`/`low` scale candidate-cause count, Explore fan-out, correlation depth, and the retry cap — delivered as an Intensity block in the task-brief *suffix* (never the cacheable prefix). It must never lower fix correctness, the regression-test decision, the evidence standard, or any gate. Per-spawn effort override is **not** relied on: the agents' `model`/`effort` frontmatter stays pinned as the `high` baseline. If you add intensity levers, keep them breadth/latency-only.
- **Rewind is not auto-git.** Rewinding through `implement` must warn about the prior fix's branch edits and let the user reset — never run destructive git automatically.

## Versioning
Pre-release (`0.x`). Per the repo policy, write no legacy/back-compat/migration notes while major version is 0. The plugin's own README must not hardcode the version (the four synced version locations are in the root `CLAUDE.md`).
