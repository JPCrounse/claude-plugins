# Workflow Phases — Detail

Full entry/exit criteria, error handling, resumption, and context management for the rpi-bugfix workflow. The SKILL.md body is the summary; this file is the depth behind it.

## Contents
- Phase-by-phase entry/exit/error
- The three hard gates
- Session Resumption Protocol
- Context Management (PreCompact, bounded reads)
- Delegation mechanics & why the interview stays in the main thread
- Intensity
- Rapid-Iteration Mode — protocols

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
- *Checks fail after the implementer's active retry cap (2 at `high`, 1 at `medium`/`low`)* → surface the failure; the user decides (fix forward, or re-plan). Do not loop.
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
2. Read `state.json` (including `mode`, `intensity`, `feedback`). Append a new `sessions` entry (timestamp + current phase).
2a. **(Rapid mode) If `feedback.awaitingImplementation == true`**, divert to the Abort→Implement→Rewind Protocol (below) before steps 3–5 — the previous session was intentionally stopped to implement feedback.
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

---

## Intensity

`state.json.intensity` (`high` default | `medium` | `low`) scales investigative breadth per delegation. On each agent invocation, append the row-appropriate directives as an **Intensity block** in the task-brief *suffix* (never the cacheable prefix). `high` is the base behavior and the block may be omitted.

| Lever | high (default) | medium | low |
|---|---|---|---|
| Ranked candidate causes (`bug-researcher`) | up to 3–4 | up to 2 | top 1 |
| Explore sub-agent fan-out (`bug-researcher`, `codegraph-validator`) | as needed | broad searches only | avoid — direct Grep |
| Release/git correlation (`bug-researcher`) | full | only if a release is clearly implicated | skip unless trivially available |
| Blast-radius depth (`codegraph-validator`) | callers + data flow | callers only | suspected symbol + immediate callers |
| Retry cap (all agents) | 2 | 1 | 1 |

Models stay **pinned** at every intensity (Opus for research/impact/plan, Sonnet for implement) — intensity never downgrades a model, because a weaker model lowers reasoning/evidence quality, which the invariant below forbids. The only levers are the breadth/latency rows above.

**Hard invariant:** intensity trims *investigative breadth and latency only*. It never lowers the fix's correctness, the regression-test decision, the evidence standard for a claim, or any of the three gates. A `low` brief is not license to cut corners on safety — the same gates and the same "fix the root cause, with evidence" bar apply. Each agent's system prompt states this so a trimmed brief can't be misread.

---

## Rapid-Iteration Mode — protocols

Active only when `state.json.mode == "rapid"`. Layers a **skill-improvement** feedback loop on the base workflow; every gate is preserved. The feedback targets the rpi-bugfix plugin source (SKILL.md/agents/references), not the bug's artifacts. The SKILL.md body summarizes; this is the operational detail.

### Feedback Checkpoint Protocol
Runs at each phase boundary, **after** that phase's gate/handoff is fully processed and **before** advancing `currentPhase`:

1. Prompt: "Rapid mode — feedback on the **\<phase\>** phase? (skip / add feedback)."
2. **Skip** → advance to the next phase unchanged.
3. **Add feedback** → append a `pending` entry to `session-feedback.md`:
   `### <ISO8601> — phase: <phase> — intensity: <level> — disposition: pending` followed by the note. Increment `state.json.feedback.pending`. Then prompt: "Continue this session (feedback deferred to session end), or end now to implement this feedback?"
   - **Continue** → advance to the next phase; the entry stays `pending`.
   - **End now** → set `feedback.awaitingImplementation = true`, `feedback.resumePhase = <phase>`; append `### <ISO8601> [FEEDBACK-ABORT]` to `session-notes.md` naming the phase; **stop** the session with a report of the pending items and how to resume. Do not advance `currentPhase`.

The checkpoint is additive and gate-safe: it runs only *after* the current phase's own gate is satisfied, never displacing or front-running that gate, so it cannot interfere with G1/G2/G3. In rapid mode, treat the `currentPhase` advance bundled into a phase's gate step as **deferred until the checkpoint completes** — so an *End now* abort leaves `currentPhase` at the just-finished phase (its gate state already recorded), with `resumePhase` tracked independently.

### Deferred Implementation (banked path)
On reaching `currentPhase == complete` with `feedback.pending > 0` and no pending abort: list every `pending` entry, then implement them against the **plugin source**. Flip each to `disposition: implemented` with a one-line note of what changed; set `feedback.pending = 0`. The bug is already shipped, so this batch improves future runs — there is no rewind. Then continue to the cleanup offer.

### Abort→Implement→Rewind Protocol
Entered from Session Detection when a resumed bug has `feedback.awaitingImplementation == true`, **before** any normal resumption:

1. **Implement.** Read the `pending` entries in `session-feedback.md` and apply them to the plugin source. Flip each to `implemented` with a note; set `feedback.pending = 0`, `feedback.awaitingImplementation = false`.
2. **Offer rewind.** Ask: "Feedback implemented. Resume \<KEY\> from the start of the **\<resumePhase\>** phase to evaluate the change?"
   - **Yes** → `rewind(resumePhase)` (below), then re-run from there.
   - **No** → resume normally at `currentPhase`, honoring gate state. Leave `resumePhase` recorded for reference.

### Rewind mechanics
`rewind(P)` — reused by the abort path and by an explicit "restart \<KEY\> from the \<phase\> phase" request in either mode:

1. Set `currentPhase = P`.
2. Invalidate the artifact of *P* and every later phase — they will be regenerated: `spec.md` (P = research), `impact-analysis.md` (P ≤ impact), `plan.md` (P ≤ plan).
3. Reset the gates at or after *P* to their pending values (`specApproved → false` for P = research; `reproConfirmed → "pending"` for P ≤ plan; `postFixReproPassed → false` for P ≤ implement) so they re-present rather than being assumed satisfied.
4. Re-run from *P*.

**Branch caveat (no auto-git):** rewinding to or through `implement` leaves the previous fix's edits on the `fix/<KEY>-slug` branch, and the re-run may re-edit the same files. Warn the user and offer to let them reset/stash the branch first. Never run `git reset` / `git checkout --` automatically — destructive git is the user's call.

**PR-phase caveat:** once the PR has been opened, the PR checkpoint does not offer *End now* / rewind — "re-running" an opened PR is undefined. Route PR-phase feedback through the banked/deferred path instead (implement at session end, improving future runs).

**Where feedback lands:** always the plugin source (`claude-plugins-jp`), never the bug's repo. If the working tree is a different repo, do not edit blindly — surface the pending list and point at the plugin repo so the user applies it there; optionally validate with the `plugin-dev` skills.
