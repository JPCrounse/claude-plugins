# Workflow Phases — Detailed Protocol

## Phase Overview

| Phase | Name | Mode | Agent | Exit Criteria |
|-------|------|------|-------|---------------|
| 1 | Goal Definition | Interactive, main thread | None (inline) | manifest.json created with topics |
| 2 | Context Collection | Interactive, per topic | guidance-collector | All topics have guidance.md |
| 3 | Roadmap Generation | Automated | roadmap-generator | All topics have roadmap.md + status.md |
| 4 | Implementation | Semi-automated, per phase | phase-implementer | All items done |
| 5 | Final Review | Semi-automated | final-reviewer | Deviations resolved, standards passed |

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

## Phase 2: Context Collection

### Entry Conditions
- `manifest.json` exists with `currentPhase` = `context-collection`
- Topic directories exist without `guidance.md`

### Process
For each topic without a `guidance.md` (in order):
1. Delegate to `guidance-collector` agent with:
   - Topic name and description (from manifest.json)
   - Directory path (`.dev-orchestrator/<topic-slug>/`)
2. The agent interacts with the user to collect context:
   - Prompts for documentation, specs, code references, URLs
   - Categorizes each piece of input
   - Asks clarifying questions about ambiguities
   - When user says "done" / "that's all" / "next": aggregates into guidance.md
3. Agent returns a summary of collected context

After all topics have guidance.md:
- Update `manifest.json` currentPhase to `roadmap-generation`

### Exit Criteria
- Every topic directory contains a `guidance.md`
- manifest.json currentPhase updated

### Error Handling
- User wants to skip a topic: create a minimal guidance.md with "No specific guidance provided — use general best practices"
- User wants to go back and add more context: re-run guidance-collector for that topic (appends to existing guidance.md)

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
   - Writes `roadmap.md` for each topic
   - Writes `status.md` for each topic (all items `todo`, empty session log)
   - Writes `status-overview.md` at the `.dev-orchestrator/` root (only if multiple topics)
3. Agent returns summary of all roadmaps with phase/item/concurrent group counts

After generation:
- Update `manifest.json` currentPhase to `implementation`
- **Run `/compact`** automatically (see Automatic Compaction section)

### Exit Criteria
- Every topic has `roadmap.md` and `status.md`
- `status-overview.md` exists (if subtopics)
- manifest.json currentPhase updated

### Error Handling
- User wants to modify roadmap: edit roadmap.md directly, then update status.md to match
- User wants to add/remove checklist items: agents respect the current state of roadmap.md

---

## Phase 4: Implementation

### Entry Conditions
- `manifest.json` exists with `currentPhase` = `implementation`
- All topics have `roadmap.md` and `status.md`

### Process
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

After agent returns:
- Update `status-overview.md` with current state
- **Run `/compact`** automatically with the agent's handoff summary (see Automatic Compaction section)
- After compaction, re-read state files and continue to next phase

### Exit Criteria
- All items across all topics are `done`
- `manifest.json` currentPhase updated to `final-review`

### Error Handling
- Phase fails mid-way: status.md reflects partial progress, session log documents the failure
- User wants to skip an item: mark it as `done` with a note in the session log
- User rejects an acceptance item: agent marks it back to `todo` with feedback in session log
- Deviation from guidance: agent documents what was specified, what was implemented, why, and who decided (agent or user)

---

## Phase 5: Final Review

### Entry Conditions
- `manifest.json` exists with `currentPhase` = `final-review`
- All checklist items across all topics are `done`

### Process
1. Delegate to `final-reviewer` agent with the manifest.json path
2. **Stage 1 — Guidance Compliance:**
   - Agent reads all guidance.md files and status.md session logs
   - Cross-references implementation against guidance specifications
   - Produces deviation report categorizing:
     - Documented deviations (logged during implementation with agent/user attribution)
     - Undocumented deviations (found during review)
     - Guidance items not addressed
   - User reviews and resolves each deviation (approve, justify, or request correction)

3. **Stage 2 — Project Standards:**
   - Agent scans for project-level guidelines (CLAUDE.md, linting configs, coding conventions)
   - Reviews implemented code against these standards
   - Produces standards compliance report
   - User approves or requests fixes

4. **Stage 3 — Finalization:**
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
The phase-implementer agent:
- Processes groups in order
- For `[concurrent]` groups with substantial items: spawns parallel sub-agents (one per item) in a single message
- For `[concurrent]` groups with simple items: may implement sequentially for efficiency
- For `[sequential]` groups: always implements one at a time

---

## Session Resumption Protocol

When the orchestrate skill detects an existing `.dev-orchestrator/manifest.json`:

1. Read `manifest.json` to determine `currentPhase`
2. Read `status-overview.md` (or single topic `status.md`) for progress
3. Present a brief status summary to the user
4. Offer options:
   - **Continue** — Resume from current phase and topic
   - **Status report** — Delegate to status-reviewer agent for detailed breakdown
   - **Skip to next topic/phase** — Advance past current work
   - **Start over** — Rename current `.dev-orchestrator/` to `.dev-orchestrator.archived-YYYY-MM-DD/` (using the current date) and begin Phase 1 fresh
5. Append new session entry to `manifest.json` sessions array
6. Resume the appropriate phase

---

## Automatic Compaction Protocol

Compaction is run **automatically** (not just suggested) at these points to optimize token usage:

### When to Compact
1. **After Phase 3 completes** — roadmap generation consumed significant context reading guidance files
2. **After each phase-implementer returns** — implementation context (file reads, edits, sub-agent results) is no longer needed
3. **Not after Phase 5** — workflow is done, no further context needed

### How to Compact
Run `/compact` with a summary constructed from the agent's handoff. The summary must include:
- Current workflow phase and what just completed
- Which topics/phases are done
- What the next step is
- Key decisions that should survive compaction

### After Compaction
- Re-read `manifest.json` to determine current state
- Re-read relevant status files to find next actionable item
- The handoff summary in the compact message provides enough context to resume efficiently
- Session log entries in status.md document what happened before compaction

### Agent Handoff Summaries and Compaction
Each agent's handoff summary is designed to serve double duty:
1. As the input for the `/compact` summary (what to preserve)
2. As a self-contained resumption point (the next agent can start from this alone)

This means agents must include in their handoff:
- Enough state information that re-reading all files is not necessary for the next step
- Key decisions and deviations (these would be lost in compaction otherwise)
- Clear identification of what comes next

---

## Agent Handoff Summary Format

Every agent should end its work with a structured summary block:

```
## Handoff Summary
- **Phase completed:** Phase [N]: [Name]
- **Topic:** [topic name] ([topic slug])
- **Items completed:** [count] (all in acceptance, pending user verification)
- **Items already done:** [count]
- **Concurrent groups processed:** [count], of which [count] were run in parallel
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

This summary is what the main orchestrate skill uses to:
1. Update status-overview.md
2. Construct the `/compact` summary
3. Determine the next phase to execute
