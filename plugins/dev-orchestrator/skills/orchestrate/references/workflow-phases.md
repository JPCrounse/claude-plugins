# Workflow Phases — Detailed Protocol

## Phase Overview

| Phase | Name | Mode | Agent | Exit Criteria |
|-------|------|------|-------|---------------|
| 1 | Goal Definition | Interactive, main thread | None (inline) | manifest.json created with topics |
| 1.5 | Autonomy Selection | Interactive, main thread | None (inline) | executionMode set to `deferred` (supervised) or `one-shot`; acceptanceMode set to `deferred` |
| 2 (interactive) | Context Collection | Interactive, per topic, serial | guidance-collector | All topics have guidance.md |
| 2 (batch) | Context Collection | User pre-supplies inputs, then parallel | guidance-collector × N (parallel) | All topics have guidance.md |
| 3 | Roadmap Generation | Automated | roadmap-generator | All topics have roadmap.md (with cluster + Affects annotations); status.md per topic (unless one-shot) |
| 3.5 | Mode Selection | Interactive, main thread (skipped unless executionMode = deferred) | None (inline) | executionMode rewritten from `deferred` to `speed` or `efficiency` |
| 4 (speed) | Implementation | Semi-automated, per phase | phase-implementer | All items done or in acceptance |
| 4 (efficiency) | Implementation | Semi-automated, per cluster | cluster-implementer (multi-phase) / phase-implementer (singletons) | All items done or in acceptance |
| 4 (one-shot) | Implementation | Fully autonomous, per cluster, balanced delegation | cluster-implementer / phase-implementer with one-shot directive | All phases complete OR workflow aborted on blocking deviation |
| 4.5 | Batch Acceptance Review | Interactive, main thread (skipped unless acceptanceMode = deferred AND not one-shot) | None (inline) | All items either done or todo; no items in acceptance |
| 5 | Final Review | Semi-automated | final-reviewer | Deviations resolved, standards passed; in one-shot mode also handles per-item acceptance walkthrough |

---

## Phase 1: Goal Definition

### Entry Conditions
- No `.dev-orchestrator/` directory exists, OR user explicitly requests a new workflow

### Process
1. Ask user for the main topic name and a brief description of the goal
2. Ask whether to split into subtopics:
   - Recommend splitting for stories with 10+ checklist items or multiple distinct concerns
   - Suggest subtopics based on natural boundaries in the description
   - Accept user-defined subtopics (comma-separated or one per line)
3. Convert topic names to kebab-case slugs
4. Create directory structure:
   ```
   .dev-orchestrator/
   ├── manifest.json
   └── <topic-slug>/     (one per topic)
   ```
5. Write `manifest.json` with all metadata
6. Create TaskCreate entries for each topic
7. Update `manifest.json` currentPhase to `context-collection`

### Exit Criteria
- `manifest.json` exists with valid topic list
- All topic directories created
- At least one topic defined

### Error Handling
- If user wants to rename topics later: update manifest.json and rename directories
- If user wants to add subtopics after initial definition: append to manifest and create new directories

---

## Phase 1.5: Autonomy Selection

### Entry Conditions
- Phase 1 complete: `manifest.json` exists, topics defined
- `executionMode` and `acceptanceMode` not yet set

### Process
1. Ask the user one question: **supervised** or **one-shot**?
2. Explain the tradeoff briefly:
   - Supervised: user stays in the loop at meaningful decision points (roadmap review, optional speed-vs-efficiency choice at Phase 3.5, acceptance review). Speed-vs-efficiency choice is deferred until the roadmap exists.
   - One-shot: fully autonomous from this point through Phase 5. No status files, no per-phase reviews, no resumption.
3. Persist to `manifest.json`:
   - Supervised → `executionMode: "deferred"`, `acceptanceMode: "deferred"`
   - One-shot → `executionMode: "one-shot"`, `acceptanceMode: "deferred"` (locked)

### Exit Criteria
- `manifest.json` has `executionMode` and `acceptanceMode` set
- Workflow proceeds to Phase 2

### Error Handling
- User wants to switch modes later: edit manifest.json directly. Switching from supervised to one-shot mid-flight is risky (status.md exists but one-shot ignores it); switching from one-shot to supervised requires recreating status.md from one-shot-log.md (manual, not supported by the skill).
- User chose one-shot but then wants to pause during Phase 4: not supported. One-shot is non-interactive past this point. The user can interrupt the model and switch to supervised mode by editing manifest.json before resuming, but mid-workflow rescue is best-effort.

---

## Phase 2: Context Collection

### Entry Conditions
- `manifest.json` exists with `currentPhase` = `context-collection`
- Topic directories exist without `guidance.md`
- `executionMode` and `acceptanceMode` are set (Phase 1.5 complete)

### Sub-Decision: Collection Mode
At Phase 2 entry, ask the user (or auto-default if one-shot) which collection mode:
- `interactive` (default for supervised modes) — serial collectors with Q&A
- `batch` — user pre-supplies inputs, collectors run in parallel

Persist as `guidanceCollectionMode` in `manifest.json`.

### Process — Interactive Mode
For each topic without a `guidance.md` (in order):
1. Delegate to `guidance-collector` agent with:
   - Topic name and description (from manifest.json)
   - Directory path (`.dev-orchestrator/<topic-slug>/`)
   - Directive: `collectionMode: interactive`
2. The agent interacts with the user to collect context:
   - Prompts for documentation, specs, code references, URLs
   - Scans the codebase proactively
   - Categorizes each piece of input
   - Asks clarifying questions about ambiguities
   - When user says "done" / "that's all" / "next": aggregates into guidance.md
3. Agent returns a summary of collected context.

### Process — Batch Mode
1. **Collect inputs serially.** For each topic in order, ask the user to paste all their inputs (documentation, specs, file references, examples) in one message. Continue until all topics have inputs.
2. **Spawn collectors in parallel.** In a single message, invoke N guidance-collector sub-agents, one per topic. Each receives:
   - Topic name, slug, directory path
   - Directive: `collectionMode: batch`
   - The user's pre-supplied input for that topic in the task brief
3. Wait for all collectors to complete. Each writes its own guidance.md without user interaction.
4. Present the aggregate summary. Surface open-questions per topic — the user can either resolve them now (which re-invokes the relevant collector) or defer to Phase 3 review.

### After Either Mode
- Update `manifest.json` currentPhase to `roadmap-generation`

### Exit Criteria
- Every topic directory contains a `guidance.md`
- `manifest.json` `currentPhase` updated
- `guidanceCollectionMode` persisted

### Error Handling
- User wants to skip a topic: create a minimal guidance.md with "No specific guidance provided — use general best practices"
- User wants to go back and add more context: re-run guidance-collector for that topic (appends to existing guidance.md). Interactive mode supports incremental addition naturally; batch mode requires re-invoking with new input only.
- Batch-mode collector reports many open questions: surface them. The user can either provide more input (re-run that topic's collector) or proceed with the open questions documented in guidance.md (they will be visible during Phase 3 roadmap review).

---

## Phase 3: Roadmap Generation

### Entry Conditions
- `manifest.json` exists with `currentPhase` = `roadmap-generation`
- All topics have `guidance.md`

### Process
1. Delegate to `roadmap-generator` agent with the manifest.json path
2. The agent processes all topics:
   - Reads each `guidance.md` as the authoritative source
   - Decomposes work into ordered phases with specific checklist items
   - **Organizes items into concurrency groups** (see Concurrency Groups section below)
   - **Identifies context clusters** within each topic (see Clusters section below)
   - Writes `roadmap.md` for each topic (with cluster registry and per-phase cluster annotation)
   - Writes `status.md` for each topic (all items `todo`, empty session log)
   - Writes `status-overview.md` at the `.dev-orchestrator/` root (only if multiple topics)
3. Agent returns summary of all roadmaps with phase/item/concurrent group/cluster counts

After generation:
- Update `manifest.json` `currentPhase` to `implementation`. Do this **before** Phase 3.5, so an interruption during mode selection resumes into the Phase 4 entry guard (which re-runs Phase 3.5) rather than resuming at `roadmap-generation` and regenerating the roadmap.
- Run **Phase 3.5: Mode Selection** (below), which persists the chosen `executionMode`.
- Proceed directly to Phase 4. Do not prompt for or attempt `/compact` (see Context Management section)

### Exit Criteria
- Every topic has `roadmap.md` (with cluster annotations) and `status.md`
- `status-overview.md` exists (if subtopics)
- `manifest.json` `currentPhase` updated and `executionMode` persisted

### Error Handling
- User wants to modify roadmap: edit roadmap.md directly, then update status.md to match. If clusters are edited, ensure every phase still has exactly one `Cluster:` line and the top-of-file `## Clusters` registry remains consistent.
- User wants to add/remove checklist items: agents respect the current state of roadmap.md

---

## Phase 3.5: Mode Selection

A single decision point between roadmap generation and implementation. The orchestrator (not an agent) asks the user to choose between `speed` and `efficiency` execution modes for Phase 4, then persists the choice to `manifest.json`.

### Process
1. Surface the cluster breakdown from the roadmap-generator's summary: total clusters, how many are multi-phase, how many are singletons.
2. Explain the tradeoff:
   - **Speed mode** — one `phase-implementer` per phase; `[concurrent]` groups may spawn parallel inner sub-agents; faster wall-clock, higher token cost (shared context re-read per phase).
   - **Efficiency mode** — one `cluster-implementer` per multi-phase cluster (singletons short-circuit to `phase-implementer`); inner phase-implementer sub-agents serialize `[concurrent]` groups for max token savings; slower wall-clock, lower token cost.
3. Default recommendation: efficiency mode when at least one multi-phase cluster exists; speed mode otherwise.
4. Persist the chosen value as `executionMode: "speed"` or `executionMode: "efficiency"` in `manifest.json`.

### Exit Criteria
- `manifest.json` has `executionMode` set
- Workflow proceeds to Phase 4

### Error Handling
- User doesn't want to choose: default to the recommendation above. Document the default in the next session log entry so it's visible during resumption.
- User wants to change mode mid-implementation: edit `manifest.json` directly. The next phase or cluster honors the new value. State files remain compatible across modes.

---

## Phase 4: Implementation

### Entry Conditions
- `manifest.json` exists with `currentPhase` = `implementation` and `executionMode` set to `speed`, `efficiency`, or `one-shot` (the `deferred` sentinel must have been resolved at Phase 3.5)
- All topics have `roadmap.md` (with cluster annotations) and `status.md`

### Process — Speed Mode
1. Read `status-overview.md` (or the single topic's `status.md`) to identify the next actionable phase:
   - Find the first topic with items not in `done` state
   - Within that topic, find the first phase with items not in `done` state
2. Delegate to `phase-implementer` agent with:
   - Topic name and slug
   - Phase number to implement
   - Directory path (`.dev-orchestrator/<topic-slug>/`)
3. The agent implements each checklist item respecting concurrency groups:
   - Processes groups in order (Group 1 before Group 2, etc.)
   - For `[concurrent]` groups: may spawn parallel sub-agents
   - For `[sequential]` groups: processes items one at a time
   - Updates status.md item states as work progresses
   - Documents any deviations from guidance with reasoning and attribution
   - Appends session log entries
   - Returns structured handoff summary when phase completes

### Process — Efficiency Mode
1. Read `status-overview.md` (or the single topic's `status.md`) and the topic's `roadmap.md` to identify the next actionable cluster:
   - Find the first topic with items not in `done`
   - Within that topic, find the cluster containing the lowest-numbered unfinished phase
2. Determine cluster size:
   - **Singleton cluster:** Skip the cluster wrapper. Delegate directly to `phase-implementer` (same call as speed mode).
   - **Multi-phase cluster:** Delegate to `cluster-implementer` with:
     - Topic name and slug
     - Cluster ID
     - Ordered list of phase numbers in the cluster
     - Directory path (`.dev-orchestrator/<topic-slug>/`)
3. The `cluster-implementer` agent:
   - Reads shared context once (guidance.md, roadmap.md, source files referenced by the cluster)
   - Iterates the cluster's phases in order, sequentially (no parallelism across phases)
   - For each phase: delegates to a nested `phase-implementer` sub-agent
   - The nested phase-implementer processes `[concurrent]` groups **serially** in efficiency mode (no parallel sub-agents) — this is the explicit speed-for-tokens tradeoff
   - Aggregates per-phase handoff summaries
   - Returns a structured cluster-level handoff containing all phases' summaries
4. The user-facing Post-Phase Handling (acceptance review, status updates) is applied per-phase from the cluster's aggregated handoff.

### Process — One-Shot Mode
1. Emit a one-line status message to the user when each phase or cluster starts and ends. This is the only mid-Phase-4 user-visible signal.
2. Iterate topics in order. For each topic, iterate clusters in order:
   - **Singleton cluster:** Delegate directly to `phase-implementer` with one-shot directive (*parallelize concurrent groups, log to `one-shot-log.md`*).
   - **Multi-phase cluster:** Delegate to `cluster-implementer` with one-shot directive (passes through to inner phase-implementers).
3. Inner phase-implementers in one-shot:
   - Process `[concurrent]` groups in parallel (speed-style — efficiency's serialization does not apply)
   - **Skip** all `status.md` and `status-overview.md` writes
   - Append `[PHASE START]`, `[PHASE END]`, `[BLOCKING DEVIATION]` entries to `.dev-orchestrator/one-shot-log.md`
4. **Blocking-deviation handling is strict.** If any inner phase-implementer reports `blockingDeviation: true`:
   - Append `[WORKFLOW ABORTED]` to one-shot-log.md
   - Update manifest currentPhase to `final-review` (so Phase 5 can surface the abort)
   - Stop. Do not continue iterating.
5. No Post-Phase Handling in one-shot — items accumulate in implementation state and are reviewed at Phase 5.

### Post-Phase Handling — Supervised Modes Only
After each phase (speed mode) or cluster (efficiency mode) returns:
- Update `status-overview.md` with current state
- Present handoff summary to user
- **Branch on `acceptanceMode`:**
  - `per-phase`: run the per-phase acceptance review now (mark accepted items `done`, rejected items back to `todo` with feedback)
  - `deferred`: skip the per-phase review; items stay in `acceptance` for Phase 4.5. **Exception:** if the handoff has `blockingDeviation: true`, run an immediate targeted review of the blocking item only. See Phase 4.5 section for details.
- Continue to next phase or cluster directly. Do not prompt for or attempt `/compact` (see Context Management section)
- If automatic compaction fires mid-cluster in efficiency mode, the cluster-implementer resumes by re-reading state files (it does not need to be respawned — the orchestrator simply continues delegating where it left off after compaction recovery)

### Final transition out of Phase 4
- **Supervised modes:** When all items reach `acceptance` or `done`:
  - `acceptanceMode: "per-phase"`: every item should already be `done`. Proceed to Phase 5.
  - `acceptanceMode: "deferred"`: items in `acceptance` need batch review. Update `currentPhase` to `acceptance-review` and proceed to Phase 4.5.
- **One-shot mode:** When all phases complete (no blocking deviation). Update `currentPhase` to `final-review`. Proceed to Phase 5 (which handles the one-shot acceptance walkthrough first).

### Exit Criteria
- **Supervised, per-phase acceptance:** All items across all topics are `done`. `currentPhase` is `final-review`.
- **Supervised, deferred acceptance:** All items are `done` or `acceptance`; no items remain `todo` or `started`. `currentPhase` is `acceptance-review` (Phase 4.5 runs next).
- **One-shot, successful:** Every phase emitted `[PHASE END]` in `one-shot-log.md` with no `[BLOCKING DEVIATION]` and no `[WORKFLOW ABORTED]`. `currentPhase` is `final-review`.
- **One-shot, aborted:** A `[BLOCKING DEVIATION]` and `[WORKFLOW ABORTED]` entry exist in `one-shot-log.md`. `currentPhase` is `final-review` (Phase 5 surfaces the abort to the user).

### Error Handling
- Phase fails mid-way (supervised modes): status.md reflects partial progress, session log documents the failure
- User wants to skip an item (supervised modes): mark it as `done` with a note in the session log
- User rejects an acceptance item in per-phase review: agent marks it back to `todo` with feedback in session log
- Deviation from guidance: agent documents what was specified, what was implemented, why, and who decided. Contract-affecting deviations trigger the blocking-deviation escape valve (see Contract-Affecting Deviations section).
- In efficiency mode, if the cluster-implementer's inner phase-implementer fails non-blockingly: the cluster-implementer marks the failed phase's items appropriately, logs the failure, returns its handoff for the work done so far. The orchestrator then either re-delegates the remaining phases of the cluster (after the user resolves the blocker) or falls through to the next cluster.
- In one-shot mode, any irrecoverable failure (blocking deviation, inner agent failure, environmental error) aborts the workflow. There is no resumption path; the user must restart, optionally in a supervised mode after revising guidance.

---

## Phase 4.5: Batch Acceptance Review

### Entry Conditions
- `executionMode` is `speed` or `efficiency` (one-shot skips Phase 4.5)
- `acceptanceMode` is `deferred` (per-phase mode skips Phase 4.5 — every item was reviewed during Phase 4)
- `currentPhase` is `acceptance-review`
- At least one item in any topic's status.md is in `acceptance` state

### Process
1. Walk every topic's `status.md` and collect all items still in `acceptance` state. Group hierarchically: topic → phase → group.
2. Present the entire backlog as one structured review. For each item, include:
   - Item description
   - Brief implementation summary (extracted from the relevant session log entry)
   - `[BLOCKING]` tag if applicable (these should normally already have been resolved during Phase 4 — flag any remaining as anomalies)
3. Accept user input:
   - Per item: accept (→ `done`) or reject (→ `todo`)
   - Bulk: "approve all" / "reject all" shortcuts
4. For each rejected item, prompt the user per-item: re-implement, or override-accept with rationale.
5. After review:
   - If any items are now `todo`: re-enter Phase 4 with the orchestrator skipping completed phases and only re-delegating phases containing `todo` items.
   - If all items are `done`: update `currentPhase` to `final-review` and proceed to Phase 5.

### Exit Criteria
- Zero items in `acceptance` state across all topics
- `manifest.json` `currentPhase` is `final-review`

### Error Handling
- Items still tagged `[BLOCKING]` in the backlog: this is a state-machine bug — Phase 4's blocking-deviation handler should have resolved them. Surface as an anomaly and let the user choose how to handle.
- User wants to defer some items to a future workflow: mark `done` with a `Deferred: <reason>` note in the session log. Document in the final-reviewer report.

---

## Phase 5: Final Review

### Entry Conditions
- `manifest.json` exists with `currentPhase` = `final-review`
- **In supervised modes:** all checklist items across all topics are `done` (Phase 4.5 cleared the `acceptance` state, or per-phase review handled it inline).
- **In one-shot mode:** there is no item-level state to check. Entry is signalled by either (a) every roadmap phase having emitted `[PHASE END]` in `one-shot-log.md` without a `[BLOCKING DEVIATION]`, OR (b) a `[WORKFLOW ABORTED]` entry in `one-shot-log.md` — both cases route through Phase 5, the latter so the final-reviewer can surface the abort to the user.

### Process
1. Delegate to `final-reviewer` agent with the manifest.json path. The agent reads `executionMode` and branches its input-set and review stages accordingly.
2. **Stage 0 (one-shot mode only) — Acceptance Walkthrough:**
   - Agent walks every roadmap item across all topics, presenting each with implementation evidence from the working tree (Grep/Read against the codebase, git history for files modified during implementation).
   - User accepts or rejects per item, grouped by topic and phase for navigability.
   - Outputs the same `done`/rejected state that supervised modes track in status.md.
3. **Stage 1 — Guidance Compliance:**
   - Agent reads all guidance.md files.
   - In supervised modes: reads each topic's `status.md` session log for documented deviations.
   - In one-shot mode: reads `one-shot-log.md` for `[BLOCKING DEVIATION]` entries (only blocking deviations were logged in one-shot); undocumented deviations are expected and discovered by comparing the working tree against guidance.md.
   - Cross-references implementation against guidance specifications.
   - Produces deviation report categorizing:
     - Documented deviations (logged during implementation with agent/user attribution)
     - Undocumented deviations (found during review)
     - Guidance items not addressed
   - User reviews and resolves each deviation (approve, justify, or request correction)

4. **Stage 2 — Project Standards:**
   - Agent scans for project-level guidelines (CLAUDE.md, linting configs, coding conventions)
   - Reviews implemented code against these standards
   - Produces standards compliance report
   - User approves or requests fixes

5. **Stage 3 — Finalization:**
   - Agent offers documentation integration (README, API docs, ADRs, changelog)
   - Agent offers cleanup of `.dev-orchestrator/` (keep, archive, or remove)
   - manifest.json currentPhase set to `complete`

### Exit Criteria
- All deviations resolved (approved or corrected)
- Standards review passed
- manifest.json currentPhase = `complete`
- User has chosen cleanup option

### Error Handling
- If corrections are needed: agent loops back to implementation as needed
- If user wants to skip review: mark as complete with a note that review was skipped

---

## Concurrency Groups

Checklist items within a phase are organized into numbered concurrency groups.

### Group Types
- **`[sequential]`** — Items must be done in order, or the group contains a single blocking item
- **`[concurrent]`** — Items have no dependencies on each other and can be implemented in parallel

### Ordering Rules
- Groups are numbered sequentially within a phase
- All items in Group N must complete before Group N+1 starts
- Within a `[concurrent]` group, items can be started simultaneously
- Within a `[sequential]` group, items are done top-to-bottom

### Dependency Analysis
When creating groups, the roadmap-generator analyzes:
1. Which items produce outputs that other items consume
2. Which items modify the same files or systems
3. Which items are truly independent

**Example:** Given 10 items where:
- Item 1 blocks everything → Group 1 [sequential]: item 1
- Items 2, 3, 4 are independent → Group 2 [concurrent]: items 2, 3, 4
- Item 5 requires item 3, blocks item 6 → Group 3 [sequential]: item 5
- Items 6, 7, 8 are independent → Group 4 [concurrent]: items 6, 7, 8
- Item 9 requires item 7, item 10 is independent → Group 5 [concurrent]: items 9, 10

### Implementation Behavior
The phase-implementer agent's handling of `[concurrent]` groups depends on the workflow's `executionMode`:
- **Speed mode:**
  - For `[concurrent]` groups with substantial items: spawns parallel sub-agents (one per item) in a single message
  - For `[concurrent]` groups with simple items: may implement sequentially for efficiency
- **Efficiency mode:**
  - For `[concurrent]` groups: always processes items sequentially within the agent's own context (no parallel sub-agent spawning) — this is the explicit speed-for-tokens tradeoff
- **Both modes:**
  - Processes groups in order (Group 1 before Group 2)
  - For `[sequential]` groups: always implements one at a time

The phase-implementer reads `manifest.json`'s `executionMode` on entry to decide its behavior.

---

## Clusters

A **cluster** is a set of phases within the same topic that share enough context to benefit from a single outer agent in efficiency mode. Cluster membership is declared per-phase in roadmap.md and listed at the top of roadmap.md under `## Clusters`.

### What Counts as Shared Context
- **Shared file set** — phases will read/edit substantially overlapping source files
- **Shared guidance sections** — phases primarily reference the same Specifications/Constraints in guidance.md
- **Domain coherence** — phases address the same layer (data, API, validation, tests, infrastructure)

### Cluster IDs
- Kebab-case (e.g., `schema-and-migrations`, `auth-endpoints`, `validation`)
- Unique within their topic (not globally — two topics can each have a `validation` cluster)
- Chosen by the roadmap-generator to describe the shared concern

### Singleton vs Multi-Phase Clusters
- A **multi-phase cluster** contains two or more phases. In efficiency mode, these are delegated to a `cluster-implementer` (outer agent) that reads shared context once and iterates phases sequentially.
- A **singleton cluster** contains one phase. In efficiency mode, these short-circuit: the orchestrator delegates directly to `phase-implementer`, skipping the cluster-implementer wrapper (no setup-sharing benefit).

### Speed Mode Ignores Clusters
In speed mode, cluster membership has no effect — every phase is delegated independently to `phase-implementer`. The cluster field is still present in roadmap.md and remains valid if the user later switches modes.

### Why Clusters, Not Topics
The outer agent could in principle be scoped per-topic, but a topic often contains phases across different concerns (e.g., a topic spans data + API + tests). Clustering at the phase level lets the outer agent's setup-share benefit kick in only where files and guidance actually overlap, instead of forcing one large outer agent to carry unrelated phase context.

---

## One-Shot Mode Cheat Sheet

One-shot mode special-cases nearly every phase. This table consolidates the differences so callers do not need to reassemble them from the per-phase sections above.

| Aspect | Supervised (`speed` / `efficiency` / `deferred`) | One-shot |
|---|---|---|
| Phase 1.5 setting | `executionMode: "deferred"`, `acceptanceMode: "deferred"` | `executionMode: "one-shot"`, `acceptanceMode: "deferred"` (locked) |
| Phase 2 collection mode | User-chosen (`interactive` default, or `batch`) | Auto-set to `batch` — no user prompt |
| Phase 3.5 | Runs when `executionMode = "deferred"` to pick `speed` vs `efficiency` | Skipped — `one-shot` already final |
| Phase 4 delegation | Speed: phase-implementer per phase. Efficiency: cluster-implementer per multi-phase cluster, phase-implementer for singletons. | Balanced: cluster-implementer per multi-phase cluster (like efficiency), phase-implementer for singletons. Inner phase-implementers parallelize `[concurrent]` groups (like speed). |
| Phase 4 user signal | Per-phase handoff summaries + acceptance prompts | One-line status line at each phase/cluster start/end — the only user-visible signal |
| Phase 4 acceptance | Per-phase or deferred (4.5) review | None mid-flight; deferred to Phase 5 Stage 0 |
| Blocking deviation handling | Immediate per-item acceptance review, then continue | Append `[WORKFLOW ABORTED]` to `one-shot-log.md`, update `currentPhase` to `final-review`, stop |
| Phase 4.5 | Runs when `acceptanceMode: "deferred"` | Skipped — Phase 5 handles acceptance |
| Phase 5 | Stage 1 (compliance) → Stage 2 (standards) → Stage 3 (finalize) | Stage 0 (per-item acceptance walkthrough from working tree) → Stage 1 → Stage 2 → Stage 3 |
| State files written | `manifest.json`, per-topic `guidance.md`/`roadmap.md`/`status.md`, optional `status-overview.md` | `manifest.json`, per-topic `guidance.md`/`roadmap.md`, root `one-shot-log.md`. **No `status.md`, no `status-overview.md`.** |
| `PreCompact` hook target | Append `[COMPACTION]` to each topic's `status.md` session log | Append `[COMPACTION]` to `one-shot-log.md` |
| Resumption | Full — re-invoke skill, reads `manifest.json` and resumes | **Not supported.** Mid-workflow failure requires starting over (optionally in a supervised mode after revising inputs). |
| Session detection options offered | Continue / Status report / Skip / Archive-and-restart | Proceed to Phase 5 (if at `final-review`) / Status report / Archive-and-restart — no "Continue" or "Skip" |

When debugging or reviewing a one-shot workflow, the authoritative artifacts are `one-shot-log.md` (event sequence) and the working tree (item-level state). No `status.md` exists.

---

## Contract-Affecting Deviations

When the phase-implementer deviates from guidance.md, the deviation is classified as either non-blocking (deferred to acceptance review like any other deviation) or **contract-affecting** (blocking — pauses Phase 4 in supervised modes, aborts the workflow in one-shot mode).

The classification is mechanical: consult the item's `Affects:` line in roadmap.md, populated by the roadmap-generator. The list contains downstream item references in the form `<phase-number>.<item-number>` (e.g., `2.1, 3.3`), or the literal `none`.

### A deviation is contract-affecting if all three apply:
1. The item's `Affects:` line lists at least one downstream item.
2. The deviation changes one of: a public function/method signature, a data schema (DB column, API request/response shape, message schema), a file path, or the resolution of an open question from guidance.md.
3. At least one item in the `Affects:` list depends on what changed.

### Non-blocking deviations (deferred to acceptance review):
- `Affects: none` — no downstream items can be poisoned.
- The deviation is internal-implementation only (no observable interface change).
- The deviation matches a constraint the user already verbally approved during the in-flight phase.

### When in doubt: classify as blocking
False positives only cost one acceptance review. False negatives propagate broken contracts to subsequent phases.

### Special case: manual `Affects:` omission
If a roadmap item lacks an `Affects:` line entirely (typically because the user added the item manually after generation), treat any deviation as potentially-blocking. Document the missing annotation in the deviation log so a future roadmap-generator run can backfill it.

### Where this is enforced
- `phase-implementer` (`agents/phase-implementer.md`) performs the check during step (g) Classify any deviation. Blocking deviations halt the phase and return with `blockingDeviation: true`.
- `cluster-implementer` (`agents/cluster-implementer.md`) propagates `blockingDeviation` from any inner phase-implementer up to its cluster handoff and halts cluster iteration.
- The orchestrate skill's Post-Phase Handling (in supervised modes) consumes `blockingDeviation: true` by triggering an immediate per-item acceptance review of the blocking item, regardless of `acceptanceMode`.
- In one-shot mode, `blockingDeviation: true` causes the orchestrator to abort the workflow (no recovery path).

---

## Session Resumption Protocol

When the orchestrate skill detects an existing `.dev-orchestrator/manifest.json`:

1. Read `manifest.json` to determine `currentPhase` and `executionMode`.
2. **If `executionMode` is absent** — the workflow was interrupted between Phase 1 and Phase 1.5, before autonomy was chosen. No status files exist yet. Skip the status summary and resume at Phase 1.5 (Autonomy Selection); the rest of this protocol does not apply.
3. Branch on `executionMode`:

   **Supervised modes (`speed`, `efficiency`, `deferred`):**
   - Read `status-overview.md` (or single topic `status.md`) for progress.
   - Present a brief status summary to the user.
   - Offer options:
     - **Continue** — Resume from current phase and topic
     - **Status report** — Delegate to status-reviewer agent for detailed breakdown
     - **Skip to next topic/phase** — Advance past current work
     - **Start over** — Rename current `.dev-orchestrator/` to `.dev-orchestrator.archived-YYYY-MM-DD/` (using the current date) and begin Phase 1 fresh

   **One-shot mode:**
   - Read `one-shot-log.md` (if present) for forensic context. Status files do not exist by design.
   - One-shot does not support resumption (by design — see `references/state-file-formats.md` Execution Modes). The previous run either completed (Phase 5 not yet reached, or already complete), aborted, or was interrupted mid-Phase-4.
   - Present a brief summary based on `one-shot-log.md` entries (which topics/phases logged `[PHASE END]`, whether `[WORKFLOW ABORTED]` is present, last activity timestamp).
   - Offer options:
     - **Proceed to Phase 5** — Only if `currentPhase` is `final-review` (one-shot completed Phase 4 without aborting, or aborted with `[WORKFLOW ABORTED]` — Phase 5 surfaces both).
     - **Status report** — Delegate to status-reviewer for the reduced phase-level breakdown
     - **Archive and start over** — Rename `.dev-orchestrator/` to `.dev-orchestrator.archived-YYYY-MM-DD/` and begin a fresh workflow (optionally in a supervised mode this time)
   - Do not offer "Continue" or "Skip to next phase" — they are not meaningful in one-shot since no per-phase checkpoint exists.

4. Append a new session entry to `manifest.json` sessions array.
5. Resume the appropriate phase (supervised) or surface the one-shot final-review/abort.

---

## Context Management

`/compact` is a Claude Code slash command — only the user can invoke it. The assistant cannot execute it programmatically, and the orchestrate skill does not prompt the user to run it. Context stays manageable through three mechanisms:

### 1. Subagent Delegation (primary)
Each phase delegates heavy work to a dedicated subagent (`guidance-collector`, `roadmap-generator`, `phase-implementer`, `cluster-implementer`, `status-reviewer`, `final-reviewer`). These agents run in their own context windows — only the structured handoff summary returns to the orchestrator thread. Most token pressure never reaches the main conversation.

**Two-layer isolation in efficiency mode.** When the workflow runs in `executionMode: "efficiency"`, multi-phase clusters use nested delegation: the `cluster-implementer` (outer) reads shared context once and delegates each phase to a `phase-implementer` (inner). Per-phase implementation residue (file contents, edit diffs, tool results) lives and dies inside the inner agent's discarded context — the outer cluster context only accumulates per-phase handoff summaries. This is the design's answer to "share setup cost across related phases without bloating any single agent's working context." The assistant cannot self-compact mid-run, so this nested-delegation pattern is the implementation of that intent.

### 2. File-Based State (recovery)
All workflow progress is persisted to `.dev-orchestrator/`:
- `manifest.json` — current phase, session history, compaction counts
- `status.md` per topic — checklist progress and session log
- `roadmap.md`, `guidance.md` per topic — authoritative plan and inputs

The skill never depends on conversation history. Any session — fresh, resumed, or post-compaction — reconstructs state by reading these files.

### 3. Automatic Compaction (fallback)
When Claude Code auto-compacts at the context-window threshold, the `PreCompact` hook (`scripts/pre-compact-save.sh`) runs and:
- Updates `manifest.json` `updated` timestamp
- Increments `compactions` counter on the latest session entry
- Appends a `[COMPACTION]` marker to each topic's `status.md` session log

After auto-compaction, the assistant re-reads `manifest.json` and the relevant status files to continue. The handoff summaries in the session log provide enough context to resume the in-flight phase.

### Agent Handoff Summaries
Each agent's handoff summary is designed to serve double duty:
1. As the resumption record written to `status.md` session log (survives compaction)
2. As a self-contained resumption point (the next agent can start from this alone)

This means agents must include in their handoff:
- Enough state information that re-reading all files is not necessary for the next step
- Key decisions and deviations (these would otherwise be lost in compaction)
- Clear identification of what comes next

---

## Agent Handoff Summary Format

There are two handoff variants: a **per-phase** handoff (emitted by `phase-implementer` whether invoked directly or nested inside a `cluster-implementer`), and a **cluster-level aggregated** handoff (emitted only by `cluster-implementer`).

### Per-Phase Handoff (phase-implementer)

```
## Handoff Summary
- **Phase completed:** Phase [N]: [Name]
- **Topic:** [topic name] ([topic slug])
- **Items completed:** [count] (all in acceptance, pending user verification)
- **Items already done:** [count]
- **Concurrent groups processed:** [count], of which [count] were run in parallel (parallel count is always 0 in efficiency mode)
- **Key decisions:**
  - [decision 1]
  - [decision 2]
- **Deviations from guidance:**
  - [deviation description] — reason: [reason] — decided by: [agent/user]
  - None (if no deviations)
- **Files changed:**
  - [path 1]: [what changed]
  - [path 2]: [what changed]
- **Current state:** [topic] has [done]/[total] items done, [acceptance] in acceptance, [remaining] remaining across all phases
- **Next action:** Phase [N+1]: [Name] is ready for implementation
- **Compact context:** [topic] Phase [N] complete. Key: [1-2 sentence summary of what was built and critical decisions]. Ready for Phase [N+1]: [name].
```

### Cluster Handoff (cluster-implementer)

Emitted only by `cluster-implementer` after processing a multi-phase cluster in efficiency mode. Contains every nested phase-implementer's per-phase handoff verbatim, plus cluster-level aggregation:

```
## Cluster Handoff Summary
- **Cluster:** [cluster-id]
- **Topic:** [topic name] ([topic slug])
- **Phases processed in this invocation:** [list]
- **Phases skipped (already done):** [list, or "none"]
- **Phases terminated early:** [list, or "none"]
- **Per-Phase Summaries:**
  ### Phase [N]: [Name]
  [inner phase-implementer's Per-Phase Handoff verbatim]

  ### Phase [N+1]: [Name]
  [inner phase-implementer's Per-Phase Handoff verbatim]

  ...
- **Cluster-Level Decisions:** (decisions spanning multiple phases or requiring cluster-wide choices)
  - [decision 1]
- **Cluster-Level Deviations:** (deviations affecting multiple phases)
  - [deviation], or "None"
- **Files Changed Across Cluster:** (deduplicated union from inner phases)
  - [path]: [what changed]
- **Current Cluster State:** [X] of [Y] phases complete; [A] items in acceptance pending user verification across the cluster; [R] items remaining
- **Next Action:** Next cluster in topic is [next-cluster-id], or next topic is [topic], or proceed to Phase 5
- **Compact Context:** [topic] cluster [cluster-id] complete. Phases [list]. Key: [1-2 sentence cluster-level summary]. Next: [next cluster or topic].
```

### How the Orchestrator Uses These

The orchestrate skill uses handoff summaries to:
1. Update `status-overview.md`
2. Append a session-log entry to the topic's `status.md` (survives any later compaction)
3. Determine the next phase or cluster to execute
4. Drive the per-phase acceptance review — for cluster handoffs, the acceptance review walks each per-phase summary inside the cluster handoff in order, not the cluster as a whole
