---
name: orchestrate
description: This skill should be used when the user wants to "start a development workflow", "break down a large story", "plan and implement a feature", "orchestrate development phases", "continue where I left off", "pick up where we stopped", "where are we", "what's the status", "show me the progress", "create a development roadmap", "implement in phases", "break this into manageable pieces", "help me implement this large task", "implement this epic", "plan this sprint work", "resume the implementation", or needs structured multi-phase development with goal definition, context collection, roadmap generation, and phased implementation with cross-session state tracking. Use this skill for any large, multi-step development task that would benefit from structured decomposition — even if the user doesn't explicitly ask for "orchestration". Do NOT use for simple single-file fixes, code reviews, or code explanation requests.
---

# Dev Orchestrator

Manage large development stories through a structured 5-phase workflow: goal definition, context collection, roadmap generation, phased implementation, and final review. All progress persists to `.dev-orchestrator/` files for cross-session continuity.

## Session Detection

Before starting any phase, check for existing state:

1. Check if `.dev-orchestrator/manifest.json` exists in the current working directory.
2. **If found:** Read `manifest.json` and `status-overview.md` (or the single topic's `status.md`). If status files do not yet exist (workflow was interrupted during Phase 1), skip status display and resume from the current phase recorded in manifest.json. Otherwise, present a brief status summary showing current phase, topic progress, and last activity timestamp. Offer the user options: continue current work, view detailed status (delegate to `status-reviewer` agent), skip to next phase, or start a new workflow (rename existing `.dev-orchestrator/` to `.dev-orchestrator.archived-YYYY-MM-DD/` first).
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
5. Write `manifest.json` with the topic list, timestamps, and `currentPhase: "context-collection"`. See `references/state-file-formats.md` for the exact schema.
6. Use TaskCreate to create a tracking task for each topic.
7. Transition to Phase 2.

## Phase 2: Context Collection

For each topic (or the single main topic if no subtopics), in order:

1. Delegate to the `guidance-collector` agent. Provide the topic name, description, and directory path (`.dev-orchestrator/<topic-slug>/`).
2. The agent interacts with the user to collect documentation, specifications, code references, and requirements. It writes a structured `guidance.md` file.
3. After the agent returns, confirm the guidance.md was written and present the collection summary.
4. Move to the next topic and repeat.

After all topics have `guidance.md`:
- Update `manifest.json` to set `currentPhase: "roadmap-generation"`.
- Transition to Phase 3.

If the user wants to skip a topic: create a minimal guidance.md noting that general best practices should be used.

## Phase 3: Roadmap Generation

Delegate to the `roadmap-generator` agent. Provide the path to `manifest.json`.

The agent:
- Reads all `guidance.md` files as authoritative sources
- Decomposes work into phases with checklist items organized into concurrency groups
- Writes `roadmap.md` and `status.md` per topic (items grouped as `[concurrent]` or `[sequential]`)
- Writes `status-overview.md` at the `.dev-orchestrator/` root (only if multiple topics)
- Returns a summary with phase, item, and concurrent group counts

After the agent returns:
- Update `manifest.json` to set `currentPhase: "implementation"`.
- Present the roadmap summary to the user.
- If the user wants to modify the roadmap before proceeding, instruct them to edit the relevant `roadmap.md` directly, then update `status.md` to match before continuing.
- **Run compact** to clear context before implementation begins. Execute `/compact` with a summary constructed from this pattern, replacing all placeholders with actual values:
  ```
  Dev orchestrator: [main topic name]. Context collection and roadmap generation complete. [topic count] topics, [item count] total items across [phase count] phases. Ready for Phase 4 implementation starting with [first topic]: Phase 1: [first phase name].
  ```
- After compaction, resume by re-reading manifest.json and proceeding to Phase 4.

## Phase 4: Implementation

Iterate through phases and topics in order:

1. Read `status-overview.md` (or single topic's `status.md`) to find the next actionable phase — the first topic with the first phase that has items not in `done` state.
2. Delegate to the `phase-implementer` agent. Provide the topic slug, phase number, and directory path. The agent handles concurrency groups (spawning parallel sub-agents for `[concurrent]` groups when beneficial).
3. The agent implements each checklist item, updates status.md, documents any deviations from guidance, and returns a structured handoff summary.
4. After the agent returns:
   - Update `status-overview.md` with current progress if it exists.
   - Present the handoff summary to the user.
   - **Acceptance review:** Present items in `acceptance` state to the user for verification:
     - List each acceptance item with a brief description of what was implemented
     - For each item the user approves: update status.md to mark it as `(done)`
     - For rejected items: mark back to `(todo)` with a note in the session log about what needs fixing
     - If the user says "looks good" or "approve all": mark all acceptance items as done in a single update
   - **Run compact** to optimize context for the next phase. Execute `/compact` with a summary constructed from the agent's handoff, replacing all placeholders with actual values:
     ```
     Dev orchestrator: [topic name] Phase [number] complete. [done count] done, [acceptance count] in acceptance. Key: [1-2 sentence summary from handoff]. Next: Phase [next number]: [next phase name].
     ```
5. After compaction, re-read manifest.json and status files to reconstruct state, then proceed to the next phase.
6. Repeat until all items across all topics reach `done`.

When all items are `done`:
- Update `manifest.json` to set `currentPhase: "final-review"`.
- Transition to Phase 5.

## Phase 5: Final Review

Triggered when all checklist items across all topics are marked as `done`.

1. Delegate to the `final-reviewer` agent. Provide the path to `manifest.json`.
2. The agent conducts three stages:

   **Stage 1 — Guidance Compliance:** Evaluates all implemented work against each topic's guidance.md. Produces a deviation report listing:
   - Documented deviations (logged by phase/checklist agents with reasoning and attribution — agent decision or user-approved)
   - Undocumented deviations (found during review but not logged)
   - Guidance items not addressed
   The user reviews and approves or requests corrections for each deviation.

   **Stage 2 — Project Standards:** After deviations are resolved, reviews implemented code against project-level standards (CLAUDE.md, linting configs, coding conventions, test coverage requirements). Produces a standards compliance report. The user approves or requests fixes.

3. After both stages are approved:
   - The agent offers **documentation integration** — updating project README, API docs, ADRs, changelog, or other relevant documentation with the work done in this workflow.
   - The agent offers **cleanup** — the user chooses to keep, archive, or remove the `.dev-orchestrator/` directory.

4. Update `manifest.json` to set `currentPhase: "complete"`.
5. Present the final workflow completion summary.

## Token Optimization Protocol

Context management is critical for large workflows. Apply automatic compaction:

- **After Phase 3 (roadmap generation):** Run `/compact` before starting implementation. All state is in files.
- **After each phase-implementer returns:** Run `/compact` with the agent's handoff summary. The next phase-implementer reconstructs context from state files, not conversation history.
- **After Phase 5 completes:** No compaction needed — workflow is done.
- **Compact content:** Always include the current workflow phase, which topics/phases are complete, what comes next, and any key decisions that should survive compaction.
- **State persistence:** All progress is in `.dev-orchestrator/` files. After compaction, re-read `manifest.json` and status files to reconstruct state — no conversation history is needed.
- **Agent handoff summaries** are designed to be self-contained: the next agent or session can resume from the handoff alone without re-reading all files. Each agent summarizes its progress so successors start with minimal context overhead.

## Reference Files

- For detailed phase transition rules, entry/exit criteria, error handling, and handoff summary format: read `references/workflow-phases.md`
- For state file schemas and examples (manifest.json, status.md, guidance.md, roadmap.md, status-overview.md): read `references/state-file-formats.md`
