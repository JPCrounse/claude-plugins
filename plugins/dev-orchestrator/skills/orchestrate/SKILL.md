---
name: orchestrate
description: This skill should be used when the user wants to "start a development workflow", "break down a large story", "plan and implement a feature", "orchestrate development phases", "continue where I left off", "pick up where we stopped", "where are we", "what's the status", "show me the progress", "create a development roadmap", "implement in phases", "break this into manageable pieces", "help me implement this large task", "implement this epic", "plan this sprint work", "resume the implementation", or needs structured multi-phase development with goal definition, context collection, roadmap generation, and phased implementation with cross-session state tracking. Use this skill for any large, multi-step development task that would benefit from structured decomposition — even if the user doesn't explicitly ask for "orchestration". Do NOT use for simple single-file fixes, code reviews, or code explanation requests.
---

# Dev Orchestrator

Manage large development stories through a structured 5-phase workflow: goal definition, context collection, roadmap generation, phased implementation, and final review. All progress persists to `.dev-orchestrator/` files for cross-session continuity.

## Session Detection

Before starting any phase, check for existing state:

1. Check if `.dev-orchestrator/manifest.json` exists in the current working directory.
2. **If found:** Read `manifest.json` and branch on `executionMode`:
   - **Supervised modes (`speed`, `efficiency`, `deferred`):** Read `status-overview.md` (or the single topic's `status.md`). If status files do not yet exist (workflow was interrupted during Phase 1), skip status display and resume from the current phase recorded in manifest.json. Otherwise, present a brief status summary showing current phase, topic progress, and last activity timestamp. Offer options: continue, view detailed status (delegate to `status-reviewer`), skip to next phase, or archive and start over (rename existing `.dev-orchestrator/` to `.dev-orchestrator.archived-YYYY-MM-DD/`).
   - **One-shot mode:** Read `.dev-orchestrator/one-shot-log.md` for forensic context. One-shot does not support resumption by design. Present a phase-level summary from log entries (`[PHASE END]` events, presence of `[WORKFLOW ABORTED]`). Offer only: proceed to Phase 5 (if `currentPhase` is `final-review`), view status report, or archive-and-restart (optionally in a supervised mode this time). Do not offer "continue" — there is no resumable mid-state.
3. **If not found:** Begin Phase 1.

When resuming, append a new session entry to `manifest.json` sessions array with the current ISO 8601 timestamp and current phase.

## Phase 1: Goal Definition

Run inline in the main conversation thread. No agent delegation.

1. Ask the user for the **main topic** — a name and brief description of what this development workflow will accomplish.
2. Ask whether to **split into subtopics**. Recommend splitting when the story involves multiple distinct concerns or would produce 10+ checklist items. Either suggest subtopics based on natural boundaries in the description, or accept user-defined subtopics.
3. Convert all topic names to kebab-case slugs. If no subtopics, the main topic slug becomes the single working directory (e.g., `.dev-orchestrator/user-auth-system/`).
4. Create the directory structure:
   ```
   .dev-orchestrator/
   ├── manifest.json
   ├── <topic-slug>/
   └── <another-topic-slug>/
   ```
5. Write `manifest.json` with the topic list, timestamps, and `currentPhase: "context-collection"`. See `references/state-file-formats.md` for the exact schema. Do not yet set `executionMode`, `acceptanceMode`, or `guidanceCollectionMode` — those are set in Phase 1.5 and Phase 2.
6. Use TaskCreate to create a tracking task for each topic.
7. Run **Phase 1.5: Autonomy Selection** (below) to set `executionMode` and `acceptanceMode`, then transition to Phase 2.

## Phase 1.5: Autonomy Selection

A short interactive step between goal definition and context collection. Run inline in the main conversation thread.

Ask the user one question: **supervised** or **one-shot**?

- **Supervised** — The workflow pauses at meaningful decision points: roadmap review, mode-selection (Phase 3.5), and acceptance review (Phase 4.5 or per-phase). User stays in the loop. Speed-vs-efficiency execution mode is chosen later at Phase 3.5, when the roadmap exists to inform the choice.
- **One-shot** — Fully autonomous. The workflow runs end-to-end without per-phase user interaction. Status files are not maintained; progress is logged to a single `one-shot-log.md`. Acceptance is deferred entirely to Phase 5. No resumption — a mid-workflow failure aborts and requires starting over.

Persist the choice to `manifest.json`:
- Supervised → `executionMode: "deferred"` and `acceptanceMode: "deferred"`
- One-shot → `executionMode: "one-shot"` and `acceptanceMode: "deferred"` (one-shot locks acceptanceMode to deferred)

Default recommendation: supervised. One-shot is appropriate for well-scoped workflows where the user has high confidence the guidance is complete and unambiguous.

Then transition to Phase 2.

## Phase 2: Context Collection

**Branch on `executionMode`** to determine collection-mode handling:

- **One-shot mode:** Skip the user prompt. Auto-set `guidanceCollectionMode: "batch"` (one-shot is non-interactive past Phase 1.5 — interactive Q&A would block the autonomy contract). The user is expected to have included all per-topic inputs alongside their initial workflow request. If guidance for any topic is unclear, the batch collector's "Open Questions" output will surface this — but no mid-Phase-2 user prompt happens.
- **Supervised modes (`deferred`, `speed`, `efficiency`):** Ask the user which **collection mode** to use:
  - **Interactive (default)** — Run guidance-collector serially per topic. Each collector asks follow-up questions and scans the codebase. Best when the user is discovering specs as they go.
  - **Batch** — User pre-supplies all per-topic inputs upfront, then collectors run in parallel to structure them. No follow-up questions. Best when the user has all material pre-assembled and wants faster context collection.

Persist the chosen value as `guidanceCollectionMode: "interactive"` or `"batch"` in `manifest.json`.

### Phase 2 — Interactive Mode

For each topic (or the single main topic if no subtopics), in order:

1. Delegate to the `guidance-collector` agent. Provide the topic name, description, directory path (`.dev-orchestrator/<topic-slug>/`), and the directive *"collectionMode: interactive"*.
2. The agent interacts with the user to collect documentation, specifications, code references, and requirements. It writes a structured `guidance.md` file.
3. After the agent returns, confirm the guidance.md was written and present the collection summary.
4. Move to the next topic and repeat.

### Phase 2 — Batch Mode

1. **Collect inputs serially in a tight loop.** For each topic in order, ask the user: *"Paste all guidance for topic <name>: documentation, specs, file references, examples. When done, just say 'next'."* Capture the user's response per topic. The user attention cost is N short pastes — much cheaper than N interactive sessions.
2. **Spawn collectors in parallel.** In a single message, invoke the `guidance-collector` agent once per topic. Each invocation receives the topic name, slug, directory path, the directive *"collectionMode: batch"*, and the user's pre-supplied input for that topic in the task brief.
3. Wait for all collectors to return. Each writes its own `guidance.md`.
4. Present the aggregate collection summary (N topics processed, total sources, total open questions across all topics).
5. **Surface open questions for review.** If any topic's `guidance.md` has open questions, list them grouped by topic. The user can resolve them now (which triggers a second targeted invocation of guidance-collector for that topic) or defer them to Phase 3's roadmap review.

### Both Modes — After Phase 2

After all topics have `guidance.md`:
- Update `manifest.json` to set `currentPhase: "roadmap-generation"`.
- Transition to Phase 3.

If the user wants to skip a topic: create a minimal guidance.md noting that general best practices should be used.

## Phase 3: Roadmap Generation

Delegate to the `roadmap-generator` agent. Provide the path to `manifest.json`.

The agent:
- Reads all `guidance.md` files as authoritative sources
- Decomposes work into phases with checklist items organized into concurrency groups
- Identifies **context clusters** within each topic — sets of phases that share enough context to benefit from a single outer agent in efficiency mode
- Writes `roadmap.md` per topic with cluster annotations and a top-level cluster registry
- Writes `status.md` per topic
- Writes `status-overview.md` at the `.dev-orchestrator/` root (only if multiple topics)
- Returns a summary with phase, item, concurrent group, and cluster counts

After the agent returns:
- Present the roadmap summary to the user, including the cluster breakdown (which clusters span multiple phases vs. which are singletons). **In one-shot mode**, present the summary but do not invite the user to modify it — one-shot is non-interactive past this point. The user can abort and restart in a supervised mode if the roadmap looks wrong.
- (Supervised only) If the user wants to modify the roadmap before proceeding, instruct them to edit the relevant `roadmap.md` directly, then update `status.md` to match before continuing.
- Run **Phase 3.5: Mode Selection** (below) **only if `executionMode` is currently `"deferred"`**. If `executionMode` is already `speed`, `efficiency`, or `one-shot`, skip Phase 3.5.
- Update `manifest.json` to set `currentPhase: "implementation"`. This write must complete before Phase 4 begins.
- Then proceed to Phase 4. Do not prompt for or attempt `/compact` — context management is handled by subagent delegation and Claude Code's automatic threshold-compaction (which fires the `PreCompact` hook that persists state to `.dev-orchestrator/` files). All progress is recoverable from state files in supervised modes (one-shot mode is non-recoverable by design).

## Phase 3.5: Mode Selection (supervised only)

Runs only when `executionMode: "deferred"` (i.e., the user chose "supervised" at Phase 1.5 and the speed-vs-efficiency choice has not yet been made). Skip entirely in one-shot mode or if the user already selected speed or efficiency.

A short interactive step between roadmap generation and implementation. Run inline in the main conversation thread — no agent delegation.

Ask the user which **execution mode** to use for Phase 4. Present the choice with the concrete numbers from the roadmap-generator's summary (total phases, total clusters, multi-phase clusters vs. singletons). The two modes are:

- **Speed mode** — One `phase-implementer` subagent per phase. Concurrency groups marked `[concurrent]` may spawn parallel inner sub-agents. Maximum wall-clock speed. Each phase re-loads shared context from disk, so total tokens consumed are higher. Best for: small workflows, time-sensitive work, workflows where phases don't share much context (mostly singleton clusters).

- **Efficiency mode** — One `cluster-implementer` subagent per **multi-phase** cluster only; singleton clusters short-circuit directly to `phase-implementer`. The cluster-implementer reads shared context once, then iterates the cluster's phases sequentially, delegating each to a nested `phase-implementer`. **Concurrency groups within phases are serialized** in this mode (no parallel inner sub-agents — max token savings). Best for: large workflows with multiple phases per cluster, token-sensitive work (e.g., long-running sessions where context budget matters).

Persist the choice by rewriting `manifest.json`'s `executionMode` from `"deferred"` to `"speed"` or `"efficiency"`. Default recommendation: efficiency mode when the roadmap contains at least one multi-phase cluster; speed mode otherwise.

## Phase 4: Implementation

Read `manifest.json` for the persisted `executionMode` and `acceptanceMode`. If `executionMode` is `"deferred"`, Phase 3.5 was incorrectly skipped — go back and run it. Otherwise the delegation strategy branches on `executionMode`.

### Phase 4 — Speed Mode

Iterate through phases and topics in order:

1. Read `status-overview.md` (or single topic's `status.md`) to find the next actionable phase — the first topic with the first phase that has items not in `done` state.
2. Delegate to the `phase-implementer` agent. Provide the topic slug, phase number, and directory path. The agent handles concurrency groups (spawning parallel sub-agents for `[concurrent]` groups when beneficial).
3. The agent implements each checklist item, updates status.md, documents any deviations from guidance, and returns a structured handoff summary.
4. After the agent returns, run the **Post-Phase Handling** section below.
5. Repeat until all items across all topics reach `acceptance` or `done`.

### Phase 4 — Efficiency Mode

Iterate through topics in order, processing each topic cluster-by-cluster:

1. Read `status-overview.md` (or the single topic's `status.md`) and the topic's `roadmap.md` to find the next actionable cluster:
   - Identify the first topic with items not in `done` state.
   - Within that topic, find the first cluster whose phases contain items not in `done`. Cluster order follows the order the phases appear in roadmap.md (a cluster is "first" if it contains the lowest-numbered unfinished phase).
2. Determine cluster size:
   - **Singleton cluster (one phase):** Short-circuit. Delegate directly to the `phase-implementer` agent for that phase. There is no setup-sharing benefit, so skip the cluster-implementer wrapper.
   - **Multi-phase cluster:** Delegate to the `cluster-implementer` agent. Provide the topic slug, cluster ID, the ordered list of phase numbers in the cluster, and the directory path.
3. The chosen agent implements its scope. For the cluster-implementer, that means: read shared context once, then iterate the cluster's phases serially, delegating each phase to a nested `phase-implementer` (with `[concurrent]` groups serialized in this mode). For a direct phase-implementer call, that means a single phase as in speed mode.
4. After the agent returns, run the **Post-Phase Handling** section below — applied per-phase as reported in the cluster-implementer's handoff (or once for a direct phase-implementer call).
5. Repeat until all items across all topics reach `acceptance` or `done`.

### Phase 4 — One-Shot Mode

Fully autonomous. No user interaction between Phase 1.5 and Phase 5. State persistence is reduced (no status.md, no status-overview.md — only `one-shot-log.md`). Delegation is balanced: cluster like efficiency mode, but inner phase-implementer parallelizes `[concurrent]` groups.

1. **Emit a single-line status message** to the user-visible thread when each phase or cluster starts and ends (e.g., "Starting topic `data-models` cluster `schema-and-migrations` (Phases 1–2)..." → "Finished cluster `schema-and-migrations`."). This is the only user-visible signal during Phase 4 — the user needs at least this much breadcrumbing to know the workflow is alive.
2. Iterate through topics in order. For each topic, iterate through clusters in order:
   - **Singleton cluster:** Delegate directly to `phase-implementer` with the directive *"one-shot mode — log to one-shot-log.md, parallelize concurrent groups"*.
   - **Multi-phase cluster:** Delegate to `cluster-implementer` with the topic slug, cluster ID, ordered phase list, directory path, and a one-shot directive. The cluster-implementer passes the one-shot directive through to nested phase-implementers.
3. After each return, check the handoff's `blockingDeviation` flag:
   - `false`: continue to the next phase or cluster. **Do not run Post-Phase Handling.** No acceptance review happens in one-shot mode mid-flight.
   - `true`: **abort the workflow.** Append a `[WORKFLOW ABORTED]` entry to `one-shot-log.md` summarizing the blocking deviation. Update `manifest.json` to `currentPhase: "final-review"` (Phase 5 will surface the abort to the user). Do not continue.
4. If all phases complete without a blocking deviation, proceed to Phase 5 (skip Phase 4.5 entirely — one-shot's acceptance happens at Phase 5).

### Post-Phase Handling (supervised modes only)

After each phase (or cluster) returns in speed or efficiency mode:

1. Update `status-overview.md` with current progress if it exists.
2. Present the handoff summary to the user. For a cluster-implementer return, this is the aggregated cluster handoff; surface each phase's contents individually.
3. **Branch on `acceptanceMode`:**
   - **`per-phase`:** Run the per-phase acceptance review now. Present items in `acceptance` state to the user for verification:
     - List each acceptance item with a brief description of what was implemented
     - For each item the user approves: update status.md to mark it as `(done)`
     - For rejected items: mark back to `(todo)` with a note in the session log about what needs fixing
     - If the user says "looks good" or "approve all": mark all acceptance items as done in a single update
   - **`deferred`:** Skip the per-phase review — items stay in `acceptance` for Phase 4.5 batch review. **Exception:** if the handoff has `blockingDeviation: true`, run an immediate targeted review of the blocking item only:
     - Present the blocking item with the deviation details and the affected downstream items from the `Affects:` list
     - User accepts → mark `(done)`, remove the `[BLOCKING]` tag, log user-approval in the session log, continue to next phase
     - User rejects → mark back to `(todo)`, log user feedback in session log, optionally update guidance.md, re-delegate the affected phase
4. Proceed to the next phase or cluster. Do not prompt for or attempt `/compact` — the heavy work happened inside the delegated agent's own context, so the orchestrator thread only accumulates handoff summaries. If automatic compaction fires, the `PreCompact` hook persists state and the workflow resumes by re-reading `.dev-orchestrator/` files.

When all items in all topics reach `acceptance` or `done` (supervised modes):
- If `acceptanceMode: "per-phase"`: every item should already be `done` (per-phase review covered each item). Proceed directly to Phase 5.
- If `acceptanceMode: "deferred"`: items in `acceptance` state still need batch review. Update `manifest.json` to `currentPhase: "acceptance-review"` and proceed to Phase 4.5.

When all phases complete in one-shot mode (no blocking deviation):
- Update `manifest.json` to set `currentPhase: "final-review"`.
- Transition to Phase 5.

## Phase 4.5: Batch Acceptance Review (deferred-acceptance supervised modes only)

Runs only when `executionMode` is `speed` or `efficiency` AND `acceptanceMode` is `deferred` AND `currentPhase` is `acceptance-review`. Skipped entirely in one-shot mode (Phase 5 handles acceptance there) and in per-phase mode (every item was already reviewed during Phase 4).

1. Read every topic's `status.md` and collect items still in `acceptance` state.
2. Group items hierarchically: by topic → by phase → by group.
3. Present the entire backlog to the user as one structured review:
   ```
   ## Batch Acceptance Review

   ### Topic: <topic name>
   #### Phase 1: <name>
   - Item 1.1: <description> — [implementation summary]
   - Item 1.2: <description> — [implementation summary]
   ...
   ```
   Highlight any items still tagged `[BLOCKING]` (these would normally have been resolved during Phase 4's targeted review — if any remain, that's a bug worth flagging).
4. Accept user input per item or in bulk:
   - **Per-item user choice:** for each item, the user accepts (mark `done`) or rejects.
   - **Bulk shortcut:** the user can say "approve all" to mark all `acceptance` items as `done` in one update.
   - **Reject all shortcut:** the user can say "reject all" to mark all `acceptance` items as `todo` (this re-enters Phase 4 for the whole backlog — rarely the right move but supported).
5. For rejected items, the user decides per item: re-implement (mark `todo` and re-enter Phase 4 with a scoped filter), or override-accept with a written rationale (mark `done` with a `User accepted despite concerns: <reason>` note in the session log).
6. After the review completes, all items are either `done` or `todo`:
   - If any items are `todo`: re-enter Phase 4 with the orchestrator skipping completed phases and only re-delegating phases containing `todo` items.
   - If all items are `done`: update `manifest.json` to `currentPhase: "final-review"` and transition to Phase 5.

## Phase 5: Final Review

Triggered when all supervised-mode checklist items are `done`, OR when one-shot mode completes successfully (no blocking deviation), OR when one-shot mode aborts on a blocking deviation (final-reviewer surfaces the abort).

1. Delegate to the `final-reviewer` agent. Provide the path to `manifest.json`.
2. The agent conducts these stages:

   **Stage 0 (one-shot mode only) — Acceptance Walkthrough:** Since one-shot deferred all acceptance to here, final-reviewer walks every roadmap item, presenting implementation evidence from the working tree. User accepts/rejects per item, grouped by topic and phase. See `agents/final-reviewer.md` for details.

   **Stage 1 — Guidance Compliance:** Evaluates all implemented work against each topic's guidance.md. Produces a deviation report listing:
   - Documented deviations (in supervised modes — logged by phase agents with reasoning and attribution)
   - `[BLOCKING DEVIATION]` events from session logs or one-shot-log.md
   - Undocumented deviations (found during review but not logged — expected to be more common in one-shot)
   - Guidance items not addressed
   The user reviews and approves or requests corrections for each deviation.

   **Stage 2 — Project Standards:** After deviations are resolved, reviews implemented code against project-level standards (CLAUDE.md, linting configs, coding conventions, test coverage requirements). Produces a standards compliance report. The user approves or requests fixes.

3. After both stages are approved:
   - The agent offers **documentation integration** — updating project README, API docs, ADRs, changelog, or other relevant documentation with the work done in this workflow.
   - The agent offers **cleanup** — the user chooses to keep, archive, or remove the `.dev-orchestrator/` directory.

4. Update `manifest.json` to set `currentPhase: "complete"`.
5. Present the final workflow completion summary.

## Token Optimization Protocol

Context management for large workflows relies on three mechanisms that operate without user intervention. **`/compact` is a user-only slash command — the assistant cannot invoke it and must not prompt the user to run it as part of the normal workflow.**

- **Subagent delegation is the primary strategy.** Heavy work (file reads, edits, sub-sub-agents) happens inside `guidance-collector`, `roadmap-generator`, `phase-implementer`, `status-reviewer`, and `final-reviewer` — each runs in its own context. Only their structured handoff summaries return to the orchestrator thread, so the main conversation stays lean across phases. In **efficiency mode for multi-phase clusters** and **one-shot mode for multi-phase clusters**, an additional `cluster-implementer` agent wraps the phase-implementer in a second layer of isolation: it reads shared context once and then delegates each phase to a nested `phase-implementer`, so per-phase implementation residue (file contents, edit diffs) never accumulates in the outer cluster context either. Speed mode and singleton clusters skip the cluster-implementer wrapper.
- **State lives in files, not conversation history.** All progress is persisted to `.dev-orchestrator/`. The file set depends on `executionMode` (see `references/state-file-formats.md` "Mode-Driven File Presence"). In supervised modes (`speed`, `efficiency`), the full state set (`manifest.json`, per-topic `guidance.md`/`roadmap.md`/`status.md`, optional `status-overview.md`) supports resumption from any point. In one-shot mode, the reduced state set (`manifest.json`, per-topic `guidance.md`/`roadmap.md`, root `one-shot-log.md`) supports forensics but **not resumption** — a one-shot workflow that fails must be restarted, optionally in a supervised mode.
- **Automatic threshold-compaction is safe in supervised modes.** When Claude Code auto-compacts, the `PreCompact` hook (`hooks/hooks.json` → `scripts/pre-compact-save.sh`) bumps the manifest timestamp, increments the session's `compactions` counter, and appends a `[COMPACTION]` marker to each topic's `status.md` session log (or to `one-shot-log.md` in one-shot mode). After compaction in supervised modes, re-read `manifest.json` and status files to reconstruct state. After compaction in one-shot mode, the workflow may continue from the in-memory state of the currently-running agent (since one-shot has no checkpoints to resume from — the running agent re-reads `one-shot-log.md` to identify where it was).
- **Agent handoff summaries** are designed to be self-contained: the next agent or session can resume from the handoff alone without re-reading all files. Each agent summarizes its progress so successors start with minimal context overhead.
- **Contract-affecting deviations are caught early** via the `Affects:` annotations on every roadmap item. The phase-implementer compares each deviation against the affected-items list. Blocking deviations in supervised modes trigger an immediate per-item acceptance review; blocking deviations in one-shot mode abort the workflow (no recovery path, by design).
- **The user may run `/compact` themselves at any time.** If they do, the same `PreCompact` hook fires and the workflow remains recoverable in supervised modes. The skill itself never asks for this.

## Reference Files

- For detailed phase transition rules, entry/exit criteria, error handling, and handoff summary format: read `references/workflow-phases.md`
- For state file schemas and examples (manifest.json, status.md, guidance.md, roadmap.md, status-overview.md): read `references/state-file-formats.md`
