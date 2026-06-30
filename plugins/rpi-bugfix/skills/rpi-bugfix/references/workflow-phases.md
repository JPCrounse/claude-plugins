# Workflow Phases — Detail

Full entry/exit criteria, error handling, resumption, and context management for the rpi-bugfix workflow. The SKILL.md body is the summary; this file is the depth behind it.

## Contents
- Phase-by-phase entry/exit/error
- The three hard gates
- Session Resumption Protocol
- Context Management (PreCompact, bounded reads)
- Delegation mechanics & why the interview stays in the main thread

---

## Phase-by-phase

### Phase 1 — Research
**Entry:** a Jira key, no existing state dir (or a resumed one at `currentPhase: research`).
**Steps:** seed from `jira_get_issue` → create `state.json` → interview (main thread) → delegate `bug-researcher` → resolve open questions.
**Exit:** `spec.md` exists with an empty Open Questions section; gate G1 reached.
**Errors:**
- *Jira key not found / auth fails* → fail fast. Surface PAT-regeneration guidance (regenerate the token, update `JIRA_PAT`). Do not create a state dir for a bad key.
- *Issue is thin (no Bugsnag link, sparse body)* → the interview is where you ask for a stack trace, logs, or screenshots; `bug-researcher` then uses the generic error-shape path.
- *Research returns open questions* → re-interview and re-invoke; do not approach G1 with open questions outstanding.

### Phase 2 — Impact Analysis
**Entry:** `gates.specApproved == true`.
**Steps:** delegate `codegraph-validator` (reads only `spec.md`) → present verdicts.
**Exit:** `impact-analysis.md` exists; `currentPhase: plan`.
**Errors:**
- *No `.codegraph/` index* → Explore+Grep fallback, header stamped; never run `codegraph init`.
- *Suspected source refuted* → not an error; surface it prominently. The plan builds on the verified view.

### Phase 3 — Plan
**Entry:** `impact-analysis.md` exists.
**Steps:** delegate `bug-planner` (reads `spec.md` + `impact-analysis.md`) → copy `regressionTest` into `state.json` → present plan.
**Exit:** `plan.md` exists; gate G2 reached.

### Phase 4 — Implementation
**Entry:** `gates.reproConfirmed` is `confirmed` or `waived`.
**Steps:** create `fix/<JIRA-KEY>-slug` branch → delegate `bug-implementer` → handle `blockingIssue` → Phase 4b self-review.
**Exit:** code edited, regression test handled, checks run; gate G3 reached.
**Errors:**
- *`blockingIssue: true`* → pause, re-delegate `bug-planner` with the new constraint, re-implement. Never push a fix built on a refuted assumption.
- *Checks fail after the implementer's retry cap (2)* → surface the failure; the user decides (fix forward, or re-plan). Do not loop.
- *`self-review` not installed* → inline light diff check + note; never hard-fail.

### Phase 5 — PR + Retrospective
**Entry:** `gates.postFixReproPassed == true` (or both G2 and G3 explicitly waived).
**Steps:** draft PR → **confirm with user** → commit/push/open PR → CI (pr-ci-fixer if red+installed) → retrospective (session-notes + proposed memory entries) → `currentPhase: complete` → offer cleanup.
**Errors:**
- *PR creation declined by user* → stop at the draft; leave the branch and state intact for a later attempt.
- *CI red, `pr-ci-fixer` not installed* → surface the failing job; the user fixes manually.

---

## The three hard gates

A **hard gate** blocks all downstream work until the user acts. The skill never advances past a gate autonomously.

- **G1 — Spec Approval** (before Phase 2). The user reviews/edits `spec.md`. No code graph, no branch, no code until approved. This is the single most important gate: everything downstream trusts the spec.
- **G2 — Reproduction Confirmed** (before Phase 4 code). The user reproduces the bug from `spec.md`'s steps. **Waivable** for heisenbugs: record `reproConfirmed: "waived"` + reason; the fix proceeds but is flagged unverified, and G3 is consequently waived.
- **G3 — Post-Fix Reproduction Passes** (before Phase 5 PR). The user re-runs the reproduction steps against the fix and confirms it no longer occurs. If G2 was waived, G3 cannot be satisfied by reproduction — the PR body must flag the fix as unverified.

Gate state lives in `state.json.gates` so a resumed session re-presents the correct gate rather than re-doing work.

---

## Session Resumption Protocol

1. Locate the bug dir (named by the user's key, or chosen from `.rpi-bugfix/`).
2. Read `state.json`. Append a new `sessions` entry (timestamp + current phase).
3. Read the **tail** of `session-notes.md` (recent entries + any open blocker) — not the whole log.
4. Resume at `currentPhase`, but first honor gate state: present the earliest unsatisfied gate at or before the current phase before doing new work. Example: if `currentPhase: impact` but `gates.specApproved` is false, re-present G1.
5. The distilled artifacts (`spec.md`, `impact-analysis.md`, `plan.md`) are the durable inputs — re-read the one the current phase needs; do not reconstruct from conversation history.

The workflow never depends on conversation history. After auto-compaction it resumes purely from the state dir.

---

## Context Management

**PreCompact hook.** Before the harness compacts context, `scripts/pre-compact-save.sh` runs: for each active bug under `.rpi-bugfix/<JIRA-KEY>/` it bumps the compaction counter in `state.json` (when `jq` is available) and appends a `### <timestamp> [COMPACTION]` marker to `session-notes.md`. The marker is purely informational — it tells a resuming agent that the system compacted and state files should be re-read. The hook exits silently (no-op) when no `.rpi-bugfix/` dir exists, and guards every `jq` call so it is safe on a Git-Bash install without `jq`.

**Bounded reads.** See `state-file-formats.md` — resuming contexts read `state.json` + the last 2–3 `session-notes.md` entries, never the full append-only log. This keeps per-invocation cost flat regardless of how long the workflow ran.

**Distilled-artifact flow (no double context load).** The heavy raw context of each phase — Jira/Bugsnag payloads, `codegraph_explore` dumps, full grep output — lives and dies inside the agent that produced it. Only the distilled `.md` artifact crosses to the next phase, and only a ~1–2K-token handoff returns to the main thread. The implementer JIT-reads only the files `plan.md` names. No downstream context re-loads upstream raw data.

---

## Delegation mechanics & why the interview stays in the main thread

Agents launched via the Agent tool are **autonomous, non-interactive subprocesses** — they cannot ask the user live follow-up questions. The interview (which needs screenshots, repro clarifications, project confirmation, and Figma links) and all three hard gates therefore run in the **main thread**, which has full user-interaction and full session tool access. The agents receive a complete, assembled brief and run to completion.

Likewise, this skill invokes the delegated **skills** (`self-review`, `pr-ci-fixer`) from the **main thread** — agents are not granted the `Skill` tool. The diagnostic *methodology* of `debug-error`/`bugsnag-triage` is delegated differently: it is baked into `bug-researcher` via the bundled `references/diagnostic-heuristics.md`, so the research runs inside one isolated agent context without depending on those skills being installed at runtime.
