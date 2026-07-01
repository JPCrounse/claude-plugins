# rpi-bugfix

A gated **Research → Plan → Implement** workflow that takes a single bug from a **Jira issue key** to a **verified pull request**. It is a *thin orchestrator*: it owns the ceremony and the human gates, and delegates the heavy lifting to tools you already have.

Trigger it with a Jira key — "fix NEXTHP-123", "research, plan and implement this bug ticket", "take NEXTCMS-88 from ticket to PR" — or resume one in progress — "continue the fix for NEXTHP-123".

## Workflow

```
 Jira key
    │
    ▼
 [ RESEARCH ]   bug-researcher (Opus/xhigh) ──────────► spec.md
    │           (interview runs in the main thread)
   G1 ── Spec approval ........................ HARD gate ◄── you
    │
    ▼
 [ IMPACT ]     codegraph-validator (Opus/xhigh) ─────► impact-analysis.md
    │           (validates the spec; Explore+Grep fallback if no code graph)
    ▼
 [ PLAN ]       bug-planner (Opus/max) ───────────────► plan.md  (+ regression-test decision)
    │
   G2 ── Reproduction confirmed ...... HARD gate (waivable) ◄── you
    │
    ▼
 [ IMPLEMENT ]  bug-implementer (Sonnet/high) ────────► code + regression test
    │           then self-review (delegated)
   G3 ── Post-fix reproduction passes ........ HARD gate ◄── you
    │
    ▼
 [ PR ]         main thread ──► commit fix(KEY): …  ──► PR  (pr-ci-fixer if CI red)
    │
    ▼
 complete + retrospective (session-notes.md + proposed Claude-memory lessons)
```

The three **hard gates** are the safety story: an agent never ships an unverified prod-bug fix. You approve the spec before any code, confirm the bug reproduces before implementation, and confirm it no longer reproduces before the PR.

## Agents

| Agent | Model / effort | Role |
|---|---|---|
| `bug-researcher` | Opus / xhigh | Fetch the Bugsnag error, locate the source, correlate git/release, write `spec.md`. Root-cause is the hardest judgment, so it runs at top effort. |
| `codegraph-validator` | Opus / xhigh | Validate each spec claim against the code graph (confirmed/refuted/unverifiable), map the blast radius, write `impact-analysis.md`. |
| `bug-planner` | Opus / max | Synthesize spec + impact into an ordered, risk-annotated `plan.md`; decide the regression-test policy. |
| `bug-implementer` | Sonnet / high | Execute the plan on the `fix/` branch, add the regression test, run checks. Edits and verifies only — it never pushes. |

Models are pinned per phase regardless of your session model. The main thread (the skill) runs the interview, the gates, the branch/commit/PR, and fires the delegated skills.

## What it delegates (and does not reimplement)

- **Diagnosis** — the `debug-error` / `bugsnag-triage` methodology, baked into `bug-researcher` via the bundled `references/diagnostic-heuristics.md` (so it works even if those plugins aren't installed).
- **Pre-push audit** — the `self-review` skill (inline fallback if absent).
- **CI failures** — the `pr-ci-fixer` skill (surfaces the failing job if absent).

## Prerequisites

- **Required:** the **`bugsnag-triage`** plugin — it provides the Jira and Bugsnag MCP servers this workflow's research agent uses, plus the shared config below.
- **Optional:** a `.codegraph/` index (richer impact analysis; Explore+Grep fallback otherwise); the `self-review` and `pr-ci-fixer` skills; the Figma MCP (UI bugs only).

## Configuration

rpi-bugfix reuses `bugsnag-triage`'s repo config — create `.claude/bugsnag-triage.config.json` once per repo. The fields rpi-bugfix reads:

- `bugsnagProjects[]` — project names/ids and `sources` paths (where to grep for the bug).
- `jira.projectByPath[]` — maps source paths to Jira project keys.
- `integrationBranch` — the branch to cut `fix/<KEY>-slug` from (defaults via branch detection if absent).
- `checksCommand` — the command the implementer runs to verify the fix (e.g. `npm run checks`).

If the config is missing, the workflow degrades: it asks you to confirm the project(s)/paths during the interview, detects the default branch, and asks for or skips the checks command. See `bugsnag-triage`'s own README for the full config schema.

## Modes & intensity

Two per-session settings; the defaults reproduce the base workflow exactly.

- **Mode** — `standard` (default) or `rapid`. **Rapid-iteration mode** is for tightening *this skill* while you dogfood it: after every phase it asks whether you want to leave feedback on how that phase behaved. You can **bank** the feedback and keep going (it collects in `session-feedback.md` and is applied to the plugin source when the run completes), or **end the session now** to implement the feedback immediately — after which you can resume the same bug **rewound to the phase you critiqued**, so you see the effect of the change right away. Every hard gate stays in place; the feedback prompts are purely additive.
- **Intensity** — `high` (default) / `medium` / `low`. It dials how much investigative breadth the agents apply (candidate-cause count, Explore fan-out, git/release correlation depth, retry cap). Models stay pinned at every level. `high` is today's behavior; `medium`/`low` trade thoroughness and latency for faster, cheaper loops. Intensity only trims breadth — it never weakens the fix's correctness, the regression-test decision, the evidence bar, or any gate.

Set them at the start ("fix NEXTHP-123 in rapid mode at medium intensity") or change them on resume ("switch to rapid", "set intensity low"); both persist in `state.json`. You can also restart a bug from any phase in either mode ("restart NEXTHP-123 from the plan phase").

## State & resumption

Everything persists to `.rpi-bugfix/<JIRA-KEY>/` (`state.json`, `spec.md`, `impact-analysis.md`, `plan.md`, `session-notes.md`, and — in rapid mode — `session-feedback.md`). The workflow survives context compaction (a `PreCompact` hook marks the notes) and resumes across sessions — re-trigger with the Jira key and it picks up at the right phase and gate.

## Design notes

Built as a layered, token-efficient adaptation of `dev-orchestrator`: each phase's raw context (Bugsnag blobs, code-graph dumps) stays isolated inside its agent, and only distilled `.md` artifacts flow forward — so no phase re-loads another's heavy context. See `CLAUDE.md` for the maintainer invariants.
