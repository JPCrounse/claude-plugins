---
name: orchestrate
description: This skill should be used when the user wants to "start a development workflow", "break down a large story", "plan and implement a feature", "orchestrate development phases", "create a development roadmap", "implement in phases", "break this into manageable pieces", "help me implement this large task", "implement this epic", or "plan this sprint work". Also use when the user wants to resume an existing workflow with phrases like "continue where I left off", "pick up where we stopped", "where are we", "what's the status", "show me the progress", or "resume the implementation". Apply proactively only for genuinely large efforts — work spanning multiple subsystems, likely to exceed ~10 implementation steps, or expected to run across multiple sessions — even if the user doesn't explicitly ask for "orchestration". Do NOT use for simple single-file fixes, small tasks that fit comfortably in one session, code reviews, or code explanation requests.
---

# Dev Orchestrator

Manage large development stories through a structured 5-phase workflow: goal definition, context collection, roadmap generation, phased implementation, and final review. All progress persists to `.dev-orchestrator/` files for cross-session continuity.

The protocols below are summaries. For full entry/exit criteria, error handling, the one-shot-mode cheat sheet, and handoff formats, read `references/workflow-phases.md`. For state file schemas, read `references/state-file-formats.md`.

## Session Detection

Before starting any phase, check whether `.dev-orchestrator/manifest.json` exists in the current working directory.

- **Found:** Read it and resume per the Session Resumption Protocol in `references/workflow-phases.md`. Branch on `executionMode`:
  - **Not yet set** (interrupted between Phase 1 and Phase 1.5, before autonomy was chosen): no status files exist yet — skip the status summary and resume at Phase 1.5.
  - Supervised modes (`speed`, `efficiency`, `deferred`) support full resumption — offer Continue / Status report (delegate to `status-reviewer`) / Skip / Archive-and-restart (rename existing directory to `.dev-orchestrator.archived-YYYY-MM-DD/`).
  - One-shot mode does not support resumption — offer only Proceed to Phase 5 (if `currentPhase` is `final-review`), Status report, or Archive-and-restart.
- **Not found:** Begin Phase 1.

When resuming, append a new entry to `manifest.json`'s `sessions` array with the current ISO 8601 timestamp and current phase.

## Phase 1: Goal Definition

Run inline in the main thread. No agent delegation.

1. Ask for the **main topic** — name and brief description.
2. Ask whether to split into subtopics. Recommend splitting when the story spans multiple distinct concerns or would produce 10+ checklist items.
3. Convert topic names to kebab-case slugs and create the directory structure under `.dev-orchestrator/`.
4. Write `manifest.json` with topics, timestamps, and `currentPhase: "context-collection"`. Schema: `references/state-file-formats.md`. Do not yet set `executionMode`, `acceptanceMode`, or `guidanceCollectionMode` — those are set in Phase 1.5 and Phase 2.
5. Use TaskCreate to create a tracking task per topic.
6. Run Phase 1.5 to set `executionMode` and `acceptanceMode`, then transition to Phase 2.

## Phase 1.5: Autonomy Selection

Inline. One question: **supervised** or **one-shot**?

- **Supervised** — Workflow pauses at meaningful decision points (roadmap review, Phase 3.5 mode choice, acceptance review). Resumable. Speed-vs-efficiency choice is deferred to Phase 3.5.
- **One-shot** — Fully autonomous end-to-end. No status files, no per-phase reviews, no resumption.

Persist to `manifest.json`:
- Supervised → `executionMode: "deferred"`, `acceptanceMode: "deferred"`
- One-shot → `executionMode: "one-shot"`, `acceptanceMode: "deferred"` (locked)

Default recommendation: supervised. One-shot is appropriate when guidance is known to be complete and unambiguous.

## Phase 2: Context Collection

Branch on `executionMode`:

- **One-shot mode:** Skip the user prompt. Auto-set `guidanceCollectionMode: "batch"` — one-shot is non-interactive past Phase 1.5. Pre-supplied per-topic inputs are expected; if guidance is unclear, batch collectors surface this in the "Open Questions" section of `guidance.md` but no mid-Phase-2 prompt fires.
- **Supervised modes:** Ask for the **collection mode**:
  - **Interactive (default)** — `guidance-collector` runs serially per topic, asking follow-up questions and scanning the codebase. Best when specs are being discovered.
  - **Batch** — Pre-supplied inputs from the user, collectors run in parallel to structure them. Best when material is pre-assembled.

Persist as `guidanceCollectionMode`.

**Interactive:** for each topic in order, delegate to `guidance-collector` with directive *"collectionMode: interactive"*. After return, confirm `guidance.md` exists and present the collection summary. Repeat.

**Batch:**
1. Collect inputs serially in a tight loop. For each topic ask: *"Paste all guidance for topic <name>: documentation, specs, file references, examples. When done, just say 'next'."* Capture the response per topic.
2. Spawn `guidance-collector` agents in parallel — one per topic in a single message, each receiving directive *"collectionMode: batch"* and the user's pre-supplied input for that topic.
3. Wait for all returns. Present the aggregate summary (N topics, total sources, total open questions).
4. Surface open questions grouped by topic. The user may resolve them now (triggers a second targeted invocation of `guidance-collector` for that topic) or defer to Phase 3 roadmap review.

Skipping a topic: write a minimal `guidance.md` noting that general best practices should be used.

After all topics have `guidance.md`, set `currentPhase: "roadmap-generation"` and transition to Phase 3.

Full process and error handling: `references/workflow-phases.md` Phase 2.

## Phase 3: Roadmap Generation

Delegate to `roadmap-generator` with the `manifest.json` path. The agent:

- Reads each `guidance.md` as the authoritative source.
- Decomposes work into phases with concurrency groups and per-item `Affects:` annotations.
- Identifies **context clusters** per topic (sets of phases sharing enough context to benefit from a single outer agent in efficiency mode).
- Writes `roadmap.md` per topic (with cluster registry), `status.md` per topic (skipped in one-shot), and `status-overview.md` at the root if multiple topics.
- Returns a summary with phase, item, group, and cluster counts.

After return:
- Present the roadmap summary including the cluster breakdown.
- In one-shot mode: present but do not invite modification. To change the plan, the user must abort and restart in a supervised mode.
- (Supervised) If the user wants to modify the roadmap: instruct them to edit `roadmap.md` directly, then sync `status.md` before continuing. If clusters are edited, ensure every phase still has exactly one `Cluster:` line and the top-of-file `## Clusters` registry remains consistent.
- Set `currentPhase: "implementation"` (this write must complete before continuing). Set it *before* Phase 3.5 — that way an interruption during mode selection resumes into the Phase 4 entry guard, which re-runs Phase 3.5, instead of resuming at `roadmap-generation` and regenerating the roadmap.
- Run Phase 3.5 **only if `executionMode == "deferred"`**. Otherwise skip it. Then proceed to Phase 4. Context management is automatic — see Token Optimization Protocol below.

## Phase 3.5: Mode Selection (supervised only)

Runs only when `executionMode == "deferred"`. Skipped in one-shot or if already `speed`/`efficiency`. Inline.

Surface the cluster numbers from the roadmap-generator's summary (total phases, total clusters, multi-phase vs. singleton split). Ask the user to choose:

- **Speed mode** — One `phase-implementer` per phase; `[concurrent]` groups may spawn parallel inner sub-agents. Max wall-clock speed; shared context re-loaded per phase.
- **Efficiency mode** — One `cluster-implementer` per **multi-phase** cluster only (singletons short-circuit to `phase-implementer`). Inner phase-implementers serialize `[concurrent]` groups. Max token savings.

Default recommendation: efficiency when at least one multi-phase cluster exists; speed otherwise.

Rewrite `manifest.json`'s `executionMode` from `"deferred"` to `"speed"` or `"efficiency"`.

## Phase 4: Implementation

Read `manifest.json` for `executionMode` and `acceptanceMode`. If `executionMode == "deferred"`, Phase 3.5 was incorrectly skipped — go back and run it.

Find the next actionable unit and delegate:

- **Speed mode** — Next phase with non-`done` items → delegate to `phase-implementer` with topic slug, phase number, directory path.
- **Efficiency mode** — Next cluster containing the lowest-numbered unfinished phase. **Singleton cluster** → delegate directly to `phase-implementer` (skip the wrapper — no setup-share benefit). **Multi-phase cluster** → delegate to `cluster-implementer` with topic slug, cluster ID, ordered phase list, and directory path.
- **One-shot mode** — Same cluster-based dispatch as efficiency, but pass a one-shot directive to the inner agent (logs to `one-shot-log.md`, parallelizes `[concurrent]` groups). Emit a one-line status message at each phase/cluster start and end — the only user-visible signal mid-Phase-4. For the full per-aspect one-shot delta, see the One-Shot Mode Cheat Sheet in `references/workflow-phases.md`.

After each return:
- **Supervised modes:** run Post-Phase Handling below.
- **One-shot mode:** check the handoff's `blockingDeviation` flag. If `true`, append `[WORKFLOW ABORTED]` to `one-shot-log.md`, set `currentPhase: "final-review"`, stop. If `false`, continue to the next phase or cluster — no Post-Phase Handling, no acceptance review mid-flight.

Repeat until all items reach `acceptance` or `done` (supervised), or all phases complete without abort (one-shot).

Full per-mode procedures, concurrency-group behavior, and error handling: `references/workflow-phases.md` Phase 4.

### Post-Phase Handling (supervised modes only)

After each phase or cluster returns:

1. Update `status-overview.md` if it exists.
2. Present the handoff summary. For cluster returns, surface each phase's per-phase summary individually.
3. Branch on `acceptanceMode`:
   - **`per-phase`:** run acceptance review now. Mark approved items `(done)`, rejected items back to `(todo)` with feedback in the session log. Shortcut: "approve all" marks all acceptance items done.
   - **`deferred`:** items stay in `acceptance` for Phase 4.5. **Exception — if `blockingDeviation: true`:** run an immediate targeted review of the blocking item only (with the affected downstream items from its `Affects:` list). Accept → mark `(done)`, remove `[BLOCKING]` tag, log approval, continue. Reject → mark back to `(todo)`, log feedback, optionally update `guidance.md`, re-delegate the affected phase.
4. Proceed to the next phase or cluster.

When all items reach `acceptance` or `done`:
- `per-phase`: all items are already `done` → proceed to Phase 5.
- `deferred`: items still in `acceptance` need batch review → set `currentPhase: "acceptance-review"` and proceed to Phase 4.5.

When all phases complete in one-shot mode with no blocking deviation: set `currentPhase: "final-review"` and proceed to Phase 5.

## Phase 4.5: Batch Acceptance Review (deferred-acceptance supervised modes only)

Runs only when `executionMode` is `speed` or `efficiency` AND `acceptanceMode: "deferred"` AND `currentPhase: "acceptance-review"`. Skipped in one-shot (Phase 5 handles acceptance there) and in per-phase (every item was already reviewed during Phase 4).

1. Collect every item still in `acceptance` from each topic's `status.md`. Group by topic → phase → group.
2. Present the entire backlog as one structured review with per-item implementation summaries. Highlight any items still tagged `[BLOCKING]` — Phase 4's blocking-deviation handler should have resolved these, so any remaining are anomalies worth flagging.
3. Accept per-item input or bulk shortcuts ("approve all" / "reject all").
4. For rejections, prompt per item: re-implement (mark `(todo)`), or override-accept with a written rationale (mark `(done)` + `User accepted despite concerns: <reason>` note in the session log).
5. After the review:
   - Any items now `todo` → re-enter Phase 4, only re-delegating phases containing `todo` items.
   - All items `done` → set `currentPhase: "final-review"` and proceed to Phase 5.

## Phase 5: Final Review

Triggered when supervised-mode items are all `done`, OR when one-shot completes successfully, OR when one-shot aborts on a blocking deviation (final-reviewer surfaces the abort to the user).

Delegate to `final-reviewer` with the `manifest.json` path. The agent reads `executionMode` and branches its input-set and stages accordingly:

- **Stage 0 (one-shot only) — Acceptance Walkthrough.** Since one-shot deferred all acceptance to here, the agent walks every roadmap item across all topics, presenting implementation evidence from the working tree. User accepts or rejects per item, grouped by topic and phase.
- **Stage 1 — Guidance Compliance.** Cross-references implementation against each topic's `guidance.md`. Produces a deviation report covering documented deviations (logged during implementation), `[BLOCKING DEVIATION]` events, undocumented deviations (more common in one-shot), and unaddressed guidance items. User resolves each.
- **Stage 2 — Project Standards.** Reviews implemented code against CLAUDE.md, linting configs, conventions, test coverage requirements. User approves or requests fixes.
- **Stage 3 — Finalization.** Offers documentation integration (README, API docs, ADRs, changelog) and `.dev-orchestrator/` cleanup (keep, archive, or remove).

After both review stages are approved, set `currentPhase: "complete"` and present the final summary.

## Token Optimization Protocol

Context management is automatic and requires no user intervention. **`/compact` is a user-only slash command — the assistant cannot invoke it and must not prompt the user to run it as part of the normal workflow.**

Three mechanisms keep the orchestrator thread lean:

1. **Subagent delegation (primary).** Heavy work (file reads, edits, sub-sub-agents) runs inside `guidance-collector`, `roadmap-generator`, `phase-implementer`, `cluster-implementer`, `status-reviewer`, and `final-reviewer` — each in its own context window. Only structured handoff summaries return to the orchestrator thread.
2. **Two-layer isolation in efficiency and one-shot multi-phase clusters.** `cluster-implementer` (outer) reads shared context once, then delegates each phase to a nested `phase-implementer` (inner). Per-phase implementation residue never accumulates in the outer cluster context. Speed mode and singleton clusters skip the wrapper.
3. **File-based state.** All progress is persisted to `.dev-orchestrator/`. The skill never depends on conversation history. After auto-compaction in supervised modes, re-read state files and continue. In one-shot mode, the running agent re-reads `one-shot-log.md` to identify where it was.

`PreCompact` hook behavior, per-mode file presence, and contract-affecting deviation detection via `Affects:`: see `references/workflow-phases.md` Context Management, `references/state-file-formats.md` Mode-Driven File Presence, and `references/workflow-phases.md` Contract-Affecting Deviations.

## Reference Files

For detail beyond these summaries:

- `references/workflow-phases.md` — Phase-by-phase entry/exit/error handling. Contains the **One-Shot Mode Cheat Sheet** (per-aspect supervised-vs-one-shot table), **Contract-Affecting Deviations** classification, **Session Resumption Protocol**, **Context Management**, **Concurrency Groups**, **Clusters**, and **Agent Handoff Summary Format** for both per-phase and cluster handoffs.
- `references/state-file-formats.md` — Schemas and worked examples for `manifest.json`, `status-overview.md`, `guidance.md`, `roadmap.md`, `status.md`, `one-shot-log.md`. Contains the **Mode-Driven File Presence** table.
- `examples/sample-workflow/` — Worked example of `.dev-orchestrator/` state after Phase 3 of a two-topic workflow (sample `manifest.json`, `guidance.md`, `roadmap.md`, `status.md`, `status-overview.md`).
