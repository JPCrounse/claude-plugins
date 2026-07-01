# State File Formats

All state lives under `.rpi-bugfix/<JIRA-KEY>/` in the project working directory — one directory per bug. The workflow is single-bug and supervised, so there is no central manifest across bugs; each bug's directory is self-describing.

## Contents
`state.json` · `spec.md` · `impact-analysis.md` · `plan.md` · `session-notes.md` · `session-feedback.md` · Bounded reads · Agent handoff formats · Naming conventions

## Directory Structure

```
.rpi-bugfix/
└── <JIRA-KEY>/                # e.g. NEXTHP-123 (exact Jira key, used verbatim)
    ├── state.json             # workflow metadata, gate state, metrics, session history
    ├── spec.md                # Phase 1 output — approved problem definition (gate G1 artifact)
    ├── impact-analysis.md     # Phase 2 output — code-graph-validated blast radius
    ├── plan.md                # Phase 3 output — ordered fix plan
    ├── session-notes.md       # append-only running log + retrospective; PreCompact appends [COMPACTION]
    └── session-feedback.md    # rapid-mode only — append-only skill-improvement feedback (see below)
```

---

## state.json

Per-bug metadata, gate status, cost metrics, and session history.

```json
{
  "version": "1.0",
  "jiraKey": "NEXTHP-123",
  "jiraIssueType": "Bug",
  "title": "Export button throws on click",
  "bugsnagErrorId": "5f3a...c12 | null",
  "branch": "fix/NEXTHP-123-null-selection-in-export",
  "created": "2026-06-30T09:00:00Z",
  "updated": "2026-06-30T11:20:00Z",
  "currentPhase": "implement",
  "mode": "standard",
  "intensity": "high",
  "gates": {
    "specApproved": true,
    "reproConfirmed": "confirmed",
    "postFixReproPassed": false
  },
  "feedback": {
    "pending": 0,
    "awaitingImplementation": false,
    "resumePhase": null
  },
  "regressionTest": "required",
  "sessionModelWarning": "WARNED: session on Sonnet; research/plan agents pinned to Opus regardless.",
  "metrics": {
    "agentInvocations": 3,
    "subAgentSpawns": 1
  },
  "sessions": [
    { "started": "2026-06-30T09:00:00Z", "lastActive": "2026-06-30T11:20:00Z", "phase": "implement", "compactions": 0 }
  ]
}
```

**Fields:**
- `version` — schema version of this file.
- `jiraKey` — the exact Jira key; also the directory name.
- `jiraIssueType` — the fetched issue type (`Bug`, `Story`, `Task`, …). Informational; the branch/PR type is always `fix` for this workflow.
- `title` — short issue title; the branch slug is derived from it.
- `bugsnagErrorId` — the linked Bugsnag error id (or dashboard URL), or `null` if the bug arrived without one.
- `branch` — `fix/<JIRA-KEY>-slug`, set at the start of Phase 4.
- `created` / `updated` — ISO 8601 timestamps.
- `currentPhase` — one of `research`, `impact`, `plan`, `implement`, `pr`, `complete`. Drives resumption.
- `mode` — `standard` (default) | `rapid`. `rapid` enables the per-phase feedback checkpoint and the abort→implement→rewind loop; `standard` behaves exactly as the base workflow. Set at session start, changeable on resume.
- `intensity` — `high` (default) | `medium` | `low`. Controls how much investigative breadth the delegated agents apply (candidate-cause count, Explore fan-out, correlation depth, retry cap); models stay pinned at every level. `high` == the base workflow. Never weakens correctness, the regression-test decision, evidence standard, or any gate — it trims breadth and latency only. See the Intensity mapping table in `workflow-phases.md`.
- `gates` — the three hard gates: `specApproved` (bool), `reproConfirmed` (`pending` | `confirmed` | `waived`), `postFixReproPassed` (bool). A resumed workflow re-presents the first unsatisfied gate at or before `currentPhase`.
- `feedback` — rapid-mode bookkeeping for `session-feedback.md`. `pending` (int): count of un-implemented feedback entries. `awaitingImplementation` (bool): set `true` when a session is aborted at a checkpoint to implement its feedback; Session Detection routes such a bug to implement-then-offer-rewind before any other work. `resumePhase` (`null` | a phase name): the phase to rewind to after the feedback is implemented, so the critiqued phase re-runs first. In `standard` mode this block stays at its defaults.
- `regressionTest` — the planner's decision: `required` | `documented-no-harness` | `null` (before planning).
- `sessionModelWarning` — the one-time model advisory note, or `null`.
- `metrics` — cost proxies (the harness has no token meter). `agentInvocations`: top-level delegations. `subAgentSpawns`: nested sub-agents rolled up from handoffs.
- `sessions` — append-only log of session starts; each carries `compactions` (auto-compaction count this session, bumped by the PreCompact hook).

---

## spec.md

Phase 1 output and the gate-G1 contract. **Fixed sections** — `bug-researcher` always writes these, shaped like a `debug-error` Step-5 report so the validator and planner can parse them mechanically.

```markdown
# Spec: NEXTHP-123 — Export button throws on click
Source: Jira NEXTHP-123 · Bugsnag https://app.bugsnag.com/.../errors/5f3a (or "none") · collected 2026-06-30T09:30:00Z

## Problem
What is broken, the user impact, and — if from Bugsnag — volume (events ÷ users), first/last seen, and release stage.

## Reproduction
1. Numbered, concrete steps.
2. ...
(or the single line: `HEISENBUG — could not establish deterministic steps; see waiver in session-notes.md`)

## Involved projects
Which project(s) from the config the fix touches (e.g. Front-end / html-player-angular).

## Suspected source
`services/export.ts:142` — `exportItems()` dereferences `selection` without a null check. Introduced in build 4.12.0 (commit a1b2c3d).

## Candidate causes
1. Null `selection` when no rows are checked — top candidate (matches the TypeError frame and breadcrumb "click:export").
2. Race with the async grid load — lower likelihood (no timing evidence).

## Existing test coverage
Is there a test that should have caught this? (e.g. "export.spec.ts covers happy path only; no empty-selection case.")

## Open questions
Must be EMPTY to pass gate G1. Any remaining gap here blocks approval and triggers a re-interview.
```

---

## impact-analysis.md

Phase 2 output. Validates the spec against the code and quantifies the blast radius.

```markdown
# Impact Analysis: NEXTHP-123
Validated against: spec.md · code graph present  (or: "absent — Explore+Grep fallback used")
Generated: 2026-06-30T10:05:00Z

## Spec-claim verdicts
- Suspected source `services/export.ts:142` — **confirmed** (on the failing path; single caller).
- Candidate cause 1 (null selection) — **confirmed** (reachable when grid selection is empty).
- Candidate cause 2 (async race) — **refuted** (selection is read synchronously on click).

## Affected symbols
- `exportItems()` → `services/export.ts:142`
- `ExportButtonComponent.onClick()` → `components/export-button.ts:55`

## Call sites / callers
- `exportItems()` has 1 caller (`onClick`); single call path — not intermittent by routing.

## Data flow
- `selection: Row[] | null` flows from the grid store; no schema change required by the fix.

## Risk areas
- The empty-selection branch is also hit by the keyboard shortcut path — verify both. Regression test should sit in `export.spec.ts`.
```

---

## plan.md

Phase 3 output. Ordered, dependency-annotated fix steps, with the regression-test decision stated up front.

```markdown
# Plan: NEXTHP-123
Based on: spec.md + impact-analysis.md
regressionTest: required  (export.spec.ts harness exists for this area)

## Fix steps (ordered)
1. Guard `exportItems()` against a null/empty `selection` at services/export.ts:142 — early-return with a user-facing "nothing selected" notice.
   Affects: 2
2. Add a regression test in export.spec.ts: empty-selection export shows the notice and does not throw (fails before step 1, passes after).
   Affects: none

## Risk areas / out-of-scope
- Do NOT refactor the grid selection store (out of scope; tempting but unrelated).
- Verify the keyboard-shortcut export path also hits the new guard.
```

The `Affects:` line after each step lists downstream steps that step would invalidate if its contract changed (comma-separated step numbers, or `none`). `bug-implementer` uses it to detect contract-affecting deviations: a deviation that changes something a listed step relies on is a `blockingIssue`.

---

## session-notes.md

Append-only running log across the whole workflow: gotchas during implementation, the retrospective summary, and `[COMPACTION]` markers from the PreCompact hook. This is the searchable per-bug index.

```markdown
# Session Notes: NEXTHP-123

### 2026-06-30T09:30:00Z [RESEARCH]
- Root cause: null selection on export with no rows checked. Suspected services/export.ts:142.

### 2026-06-30T11:05:00Z [IMPLEMENT]
- Gotcha: the keyboard-shortcut path calls exportItems() too — guard covers both; verified.
- checksCommand `npm run checks` passed.

### 2026-06-30T11:20:00Z [COMPACTION]
- Context compacted. Progress preserved in .rpi-bugfix state files; re-read state.json and the tail of this log to resume.

### 2026-06-30T11:40:00Z [RETROSPECTIVE]
- Fix shipped in PR #482. Lesson candidate: empty-collection guards are a recurring class in the export/share paths.
```

**Bounded reads (token discipline):** a resuming agent or the main thread reads `state.json` plus only the **most recent 2–3 `session-notes.md` entries** (and any unresolved blocker) — never the whole log. The full log stays on disk for forensics; injecting it wholesale into every context makes per-invocation cost grow with workflow length.

---

## session-feedback.md

**Rapid mode only.** Append-only log of **skill-improvement** feedback captured at the per-phase checkpoints — notes on how a phase behaved or how its output could be better. This is feedback about the *rpi-bugfix skill itself* (its SKILL.md / agents / references), not about the bug's artifacts (the hard gates already let the user edit `spec.md`/`plan.md` directly). "Implementing" an entry means editing the plugin source; the disposition then flips `pending` → `implemented`.

```markdown
# Session Feedback: NEXTHP-123  (rapid mode — feedback for improving the rpi-bugfix skill)

### 2026-07-01T10:00:00Z — phase: plan — intensity: medium — disposition: pending
Planner over-scoped: added a refactor step not tied to the root cause. The plan step should
enforce "smallest change" harder and explicitly reject adjacent refactors.

### 2026-07-01T10:40:00Z — phase: research — intensity: medium — disposition: implemented
(edited bug-researcher: capped ranked candidate causes to the intensity, tightened the
evidence-tie rule so every candidate cites a frame/breadcrumb)
```

**Entry fields:** ISO 8601 timestamp · `phase` (the phase being critiqued) · `intensity` (active at capture) · `disposition` (`pending` | `implemented`). An `implemented` entry carries a one-line note of what changed in the plugin source. `state.json.feedback.pending` mirrors the count of `pending` entries.

**Where feedback is applied:** the plugin source. If the bug's working tree is a different repo than `claude-plugins-jp`, the main thread does not edit blindly — it surfaces the pending list and points at the plugin repo (see the deferred/abort paths in `workflow-phases.md`).

---

## Agent handoff formats

Each agent returns a bounded (~1–2K token) handoff; the main thread logs the `Compact context:` line to `session-notes.md` and uses the rest to drive the next gate. The exact per-agent shapes are defined in each agent file (`agents/bug-researcher.md`, `agents/codegraph-validator.md`, `agents/bug-planner.md`, `agents/bug-implementer.md`). The invariant across all of them: **distilled facts only — never raw Bugsnag events, `codegraph_explore` dumps, or full grep output.**

---

## Naming Conventions

- Bug directory: the exact Jira key (e.g. `NEXTHP-123`).
- Branch slug: kebab-case derived from the issue title.
- Timestamps: ISO 8601 with timezone (UTC preferred).
- File encoding: UTF-8. Line endings: LF.
