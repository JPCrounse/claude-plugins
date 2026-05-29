# State File Formats

All state files are created under `.dev-orchestrator/` in the user's project working directory.

## Directory Structure

```
.dev-orchestrator/
├── manifest.json              # Workflow metadata & session history
├── status-overview.md         # Top-level subtopic tracking
├── <topic-slug>/              # One directory per topic/subtopic
│   ├── guidance.md            # Collected context (Phase 2 output)
│   ├── roadmap.md             # Phased checklist (Phase 3 output)
│   └── status.md              # Item tracking + session log
└── <another-topic-slug>/
    ├── guidance.md
    ├── roadmap.md
    └── status.md
```

Topic slugs use kebab-case derived from the topic name.

---

## manifest.json

Central metadata file tracking the entire workflow.

```json
{
  "version": "1.0",
  "created": "2026-05-28T10:00:00Z",
  "updated": "2026-05-28T14:30:00Z",
  "mainTopic": {
    "name": "User Authentication System",
    "slug": "user-auth-system",
    "description": "Implement complete user authentication with OAuth2 and session management"
  },
  "subtopics": [
    {
      "name": "Data Models",
      "slug": "data-models",
      "description": "User, session, and token database schemas"
    },
    {
      "name": "API Endpoints",
      "slug": "api-endpoints",
      "description": "REST endpoints for auth flows"
    }
  ],
  "currentPhase": "implementation",
  "executionMode": "efficiency",
  "acceptanceMode": "deferred",
  "guidanceCollectionMode": "interactive",
  "sessions": [
    {
      "started": "2026-05-28T10:00:00Z",
      "lastActive": "2026-05-28T11:30:00Z",
      "phase": "context-collection",
      "compactions": 0
    },
    {
      "started": "2026-05-28T13:00:00Z",
      "lastActive": "2026-05-28T14:30:00Z",
      "phase": "implementation",
      "compactions": 1
    }
  ]
}
```

**Fields:**
- `version` — Schema version of the manifest format.
- `created` / `updated` — ISO 8601 timestamps
- `mainTopic` — The overarching goal with name, slug, description
- `subtopics` — Array of subtopics (empty array if user chose not to split). Each has name, slug, description
- `currentPhase` — One of: `context-collection`, `roadmap-generation`, `implementation`, `acceptance-review`, `final-review`, `complete`. The `acceptance-review` value covers Phase 4.5 (batch acceptance review) — only reached when `acceptanceMode: "deferred"` and Phase 4 has completed all phases. Skipped in one-shot mode (Phase 5 handles acceptance directly).
- `executionMode` — One of: `speed`, `efficiency`, `one-shot`, `deferred`. Determines Phase 4 delegation strategy and supervision level. `deferred` is a sentinel used between Phase 1.5 (where the user chose "supervised") and Phase 3.5 (where the user picks speed vs efficiency); Phase 3.5 rewrites it to `speed` or `efficiency` before Phase 4 begins.
- `acceptanceMode` — One of: `per-phase`, `deferred`. `per-phase` triggers acceptance review after each phase. `deferred` defers all acceptance to Phase 4.5, except for blocking-deviation items which still pause Phase 4 for immediate review. Phase 1.5 sets `deferred` for new workflows; `per-phase` is reachable only by manually editing manifest.json. Locked to `deferred` when `executionMode: "one-shot"`. Workflow-level only — no per-topic override.
- `guidanceCollectionMode` — One of: `interactive`, `batch`. `interactive` (default for supervised modes) runs guidance-collector agents one topic at a time with user Q&A. `batch` collects all per-topic inputs upfront from the user, then spawns N collectors in parallel. Set at the start of Phase 2. One-shot mode auto-selects `batch` (no user prompt).
- `sessions` — Append-only log of session starts, with compaction count per session

When there are no subtopics, the main topic acts as the single topic. Use `mainTopic.slug` as the directory name.

### Execution Modes

- **`speed`** — Supervised mode. Phase 4 delegates one `phase-implementer` subagent per phase. Concurrency groups marked `[concurrent]` may spawn parallel inner sub-agents. Maximum wall-clock speed; each phase re-loads shared context. Honors `acceptanceMode`.
- **`efficiency`** — Supervised mode. Phase 4 delegates one `cluster-implementer` subagent per multi-phase cluster (see Clusters under roadmap.md). The cluster-implementer reads shared context once, then iterates the cluster's phases sequentially, delegating each to a nested `phase-implementer`. Concurrency groups within phases are **serialized** in this mode (max token savings, no in-phase parallelism). Singleton clusters short-circuit directly to `phase-implementer`. Honors `acceptanceMode`.
- **`one-shot`** — Fully autonomous mode. No per-phase user interaction. State persistence is reduced: `status.md` per topic is **not** written; `status-overview.md` is **not** written; phase progress is logged to a single `one-shot-log.md` at the workflow root. Delegation uses a *balanced* strategy: phases are clustered like efficiency mode (per-cluster outer agent with shared-context loading), but concurrency groups within phases run in parallel like speed mode. `acceptanceMode` is locked to `deferred` — Phase 4.5 is **skipped**; Phase 5 (final review) handles all acceptance against the working tree. **No resumption is supported** — a mid-workflow failure aborts the workflow; the user must start over (likely in a supervised mode after revising inputs). Auto-compaction is still safe; the `PreCompact` hook writes its marker to `one-shot-log.md` instead of (non-existent) status.md files.
- **`deferred`** — Sentinel value used between Phase 1.5 (where the user chose "supervised") and Phase 3.5 (where the user chooses speed vs efficiency). Phase 4 must not run with this value — Phase 3.5 must rewrite it first.

### Mode-Driven File Presence

| File | speed | efficiency | one-shot | deferred (during Phase 1.5–3.5) |
|------|-------|------------|----------|------|
| `manifest.json` | yes | yes | yes | yes |
| `guidance.md` per topic | yes | yes | yes | yes (after Phase 2) |
| `roadmap.md` per topic | yes | yes | yes (after Phase 3) | yes (after Phase 3) |
| `status.md` per topic | yes | yes | **no** | yes (after Phase 3) |
| `status-overview.md` | yes (if subtopics) | yes (if subtopics) | **no** | yes (if subtopics) |
| `one-shot-log.md` (root) | no | no | **yes** | no |

---

## status-overview.md

Top-level progress dashboard. Only created when subtopics exist.

```markdown
# Status Overview: User Authentication System

Last updated: 2026-05-28T14:30:00Z

## Progress

| Topic | Status | Current Phase | Progress | Blocked |
|-------|--------|---------------|----------|---------|
| Data Models | done | -- | 4/4 done | No |
| API Endpoints | started | Phase 2: Endpoints | 5/12 done | No |

## Detail

### Data Models
- [x] Phase 1: Schema Design (4/4 done) — cluster `schema-and-migrations`

### API Endpoints
- [x] Phase 1: Core Endpoints (3/3 done) — cluster `auth-endpoints`
- [ ] Phase 2: Endpoints (2/6 done, 1 started) — cluster `auth-endpoints`
- [ ] Phase 3: Testing (0/3 todo) — cluster `testing`
```

**Status values for topics:** `todo`, `started`, `acceptance`, `done`

**Progress column** is the whole-topic roll-up: items `done` / total items across *all* phases in the topic — not the current phase alone. Above, API Endpoints shows `5/12 done` = 3 (Phase 1) + 2 (Phase 2) + 0 (Phase 3) of 12 total items. The `Current Phase` column tracks *where* work is; `Progress` tracks *how much* is done.

**Detail lines** append each phase's cluster id (the `— cluster ...` suffix shown above) so efficiency-mode grouping stays visible at a glance. The roadmap-generator writes them; Phase 4 updaters preserve the suffix while refreshing counts.

---

## guidance.md (per topic)

Structured aggregation of all context collected during Phase 2.

```markdown
# Guidance: Data Models

Collected: 2026-05-28T10:15:00Z
Sources: 3

## Overview

Brief summary of what this topic covers and its role in the larger project.

## Specifications

- User table must include: id (UUID), email (unique), password_hash, created_at, updated_at
- Session table: id, user_id (FK), token_hash, expires_at, created_at
- Refresh tokens stored separately with rotation support

## Constraints

- Must use PostgreSQL with Prisma ORM (existing project dependency)
- All timestamps in UTC
- Passwords hashed with bcrypt, minimum cost factor 12
- Maximum 5 active sessions per user

## References

- Existing schema: see `prisma/schema.prisma` lines 1-45
- Auth library docs: [pasted content or summary]
- Company security policy: passwords must meet NIST SP 800-63B guidelines

## Open Questions

- Should we support social login (Google, GitHub) in this phase or defer?
- What is the session expiry policy? (suggested: 7 days with sliding window)

---
_Collection metadata: 3 sources, 1 open question pending_
```

**Sections are fixed** — agents always write these 5 sections plus the metadata footer:
1. **Overview** — Brief summary of what the topic covers and its role in the project
2. **Specifications** — Extracted requirements, schemas, API contracts, behavioral specs
3. **Constraints** — Technical limitations, dependencies, performance requirements, policies
4. **References** — Documentation excerpts, code locations, external links, examples
5. **Open Questions** — Unresolved ambiguities, decisions needed, items to clarify

Empty sections get a "None identified" placeholder.

---

## roadmap.md (per topic)

Phased implementation plan generated from guidance.md.

```markdown
# Roadmap: Data Models

Generated: 2026-05-28T10:30:00Z
Based on: guidance.md

## Clusters

- `schema-and-migrations` — Phases 1, 2 (shared context: Prisma schema files, migration tooling, seed scripts)
- `validation` — Phase 3 (singleton — validator/test files do not overlap with schema work)

## Phase 1: Schema Design
Priority: High
Dependencies: None
Cluster: schema-and-migrations
Estimated items: 4

### Checklist

#### Group 1 [sequential]
1. Define User model with all required fields and constraints
   Affects: 2.1, 3.1

#### Group 2 [concurrent]
2. Define Session model with foreign key to User
   Affects: 2.1
3. Define RefreshToken model with rotation support
   Affects: 2.1

#### Group 3 [sequential]
4. Add database indexes for email lookups and token queries
   Affects: none

## Phase 2: Migrations & Seed Data
Priority: High
Dependencies: Phase 1
Cluster: schema-and-migrations
Estimated items: 3

### Checklist

#### Group 1 [sequential]
1. Generate and review Prisma migration
   Affects: 2.2, 2.3

#### Group 2 [concurrent]
2. Create seed script for development/test users
   Affects: none
3. Write migration verification tests
   Affects: none

## Phase 3: Validation Layer
Priority: Medium
Dependencies: Phase 1
Cluster: validation
Estimated items: 3

### Checklist

#### Group 1 [concurrent]
1. Add Zod schemas for User create/update inputs
   Affects: 3.3
2. Add password strength validation per NIST guidelines
   Affects: 3.3

#### Group 2 [sequential]
3. Add unit tests for all validators
   Affects: none
```

**Structure rules:**
- Phases are numbered sequentially
- Each phase has: Priority, Dependencies, Cluster, Estimated items count
- Checklist items are numbered globally within each phase (continuous numbering)
- Items are specific and actionable (not vague)
- Each item has an `Affects:` line listing downstream items it blocks if deviated from (see Affects Annotation below)

**Affects annotation:**
- Every checklist item carries an `Affects:` line on the line immediately after the item text.
- The value is a comma-separated list of downstream item references in the form `<phase-number>.<item-number>` (e.g., `2.1, 3.3`), or the literal `none`.
- Item references are scoped to the current topic — cross-topic dependencies are not tracked here (they are handled at the topic-ordering level).
- The roadmap-generator populates this field by analyzing which downstream items would be invalidated if the current item's specification (signature, schema, file path, or referenced guidance constraint) changed during implementation.
- The `phase-implementer` agent uses `Affects:` to determine whether a deviation from guidance is **contract-affecting**: a deviation that changes anything an item in the `Affects:` list relies on is contract-affecting and triggers immediate acceptance review regardless of `acceptanceMode`. See `agents/phase-implementer.md`.
- `Affects: none` means a deviation on this item cannot poison any other item — safe to defer acceptance even when the deviation is significant.
- The annotation is informational metadata; manual edits to roadmap.md may omit it for items the user adds, in which case the phase-implementer falls back to treating all deviations from those items as potentially-blocking until proven otherwise.

**Cluster rules:**
- A **cluster** is a group of phases (within the same topic) that share enough context to benefit from a single outer agent in efficiency mode. See the `Clusters` section at the top of roadmap.md for the cluster registry.
- Cluster IDs are kebab-case, scoped to the topic (uniqueness only required within a topic).
- Every phase declares exactly one cluster via the `Cluster:` line.
- A cluster may contain one phase (singleton — short-circuits to direct phase-implementer in efficiency mode) or many.
- The `roadmap-generator` agent decides cluster boundaries based on shared file paths, shared guidance sections, and domain overlap. See `agents/roadmap-generator.md` for the heuristic.
- Cluster membership is ignored entirely in `speed` mode — only `efficiency` mode reads the cluster field.

**Concurrency group rules:**
- Items within a phase are organized into numbered groups
- Each group is marked `[concurrent]` or `[sequential]`
- `[concurrent]` — items in this group have no dependencies on each other. In `speed` mode they may run as parallel sub-agents; in `efficiency` mode they are processed sequentially within the inner phase-implementer (max token savings).
- `[sequential]` — items in this group must be done in order, or the group contains a single item
- Groups are ordered by dependency: all items in group N must complete before group N+1 starts
- A single item that blocks subsequent work is its own `[sequential]` group
- Items that share a common prerequisite but are independent of each other form a `[concurrent]` group

---

## status.md (per topic)

Live tracking of checklist item progress with session history.

```markdown
# Status: Data Models

Last updated: 2026-05-28T14:30:00Z
Current phase: Phase 2

## Checklist

### Phase 1: Schema Design [COMPLETE]
**Group 1** [sequential]
- [x] (done) Define User model with all required fields and constraints
**Group 2** [concurrent]
- [x] (done) Define Session model with foreign key to User
- [x] (done) Define RefreshToken model with rotation support
**Group 3** [sequential]
- [x] (done) Add database indexes for email lookups and token queries

### Phase 2: Migrations & Seed Data [IN PROGRESS]
**Group 1** [sequential]
- [x] (done) Generate and review Prisma migration
**Group 2** [concurrent]
- [~] (acceptance) Create seed script for development/test users
- [ ] (todo) Write migration verification tests

### Phase 3: Validation Layer [PENDING]
**Group 1** [concurrent]
- [ ] (todo) Add Zod schemas for User create/update inputs
- [ ] (todo) Add password strength validation per NIST guidelines
**Group 2** [sequential]
- [ ] (todo) Add unit tests for all validators

## Session Log

### 2026-05-28T10:00:00Z
- Started Phase 1: Schema Design
- Completed: User model, Session model, RefreshToken model, indexes
- All Phase 1 items done
- Key decisions: Used UUID v7 for sortable IDs, added composite index on (user_id, expires_at)

### 2026-05-28T13:00:00Z
- Resumed. Started Phase 2: Migrations & Seed Data
- Completed: Prisma migration generated and applied
- In progress: Seed script (awaiting user acceptance)
- Context: Migration file at prisma/migrations/20260528_auth_tables/migration.sql

### 2026-05-28T14:30:00Z [COMPACTION]
- Context compacted. Phase 2 in progress, 1 item in acceptance, 1 item remaining.
```

**Item state markers:**
- `[ ] (todo)` — Not started
- `[~] (started)` — Work in progress
- `[~] (acceptance)` — Implemented, awaiting user verification
- `[~] (acceptance) [BLOCKING]` — Implemented with a contract-affecting deviation from guidance — acceptance review is required immediately, not deferred, because the deviation affects items in the original `Affects:` list. Orchestrator pauses Phase 4 progression until the user resolves this item.
- `[x] (done)` — User-verified complete

**Phase header states:** `[PENDING]`, `[IN PROGRESS]`, `[COMPLETE]`

**Session log rules:**
- Each entry starts with ISO 8601 timestamp header
- Append-only (never modify previous entries)
- Include: what was done, key decisions, relevant file paths
- Compaction entries marked with `[COMPACTION]` suffix
- Blocking-deviation entries marked with `[BLOCKING DEVIATION]` suffix and include the specified vs actual contract, the reason for the deviation, and the list of `Affects:` items now at risk
- Keep entries concise — this log enables session resumption, not full audit

---

## one-shot-log.md (workflow root, one-shot mode only)

Single append-only log at `.dev-orchestrator/one-shot-log.md`. Written by phase-implementer and cluster-implementer when `executionMode: "one-shot"` and `status.md` files are not maintained.

```markdown
# One-Shot Log: User Authentication System

Started: 2026-05-28T10:00:00Z
Mode: one-shot (balanced delegation)

## Events

### 2026-05-28T10:05:12Z [PHASE START]
- Topic: data-models
- Phase 1: Schema Design
- Cluster: schema-and-migrations
- Items: 4

### 2026-05-28T10:18:33Z [PHASE END]
- Topic: data-models
- Phase 1: Schema Design
- Items completed: 4 (all acceptance pending Phase 5 review)
- Key decisions: Used UUID v7 for sortable IDs
- Deviations: none

### 2026-05-28T10:18:34Z [CLUSTER PROGRESS]
- Topic: data-models
- Cluster: schema-and-migrations
- Phases complete: 1 of 2
- Continuing to Phase 2

### 2026-05-28T10:31:07Z [BLOCKING DEVIATION]
- Topic: data-models
- Phase 2 item 1: "Generate and review Prisma migration"
- Specified: Single migration file
- Implemented: Split into two migrations for transactional safety
- Affects: 2.2, 2.3
- Workflow aborted — one-shot does not support partial completion. User intervention required.
```

**Entry types:**
- `[PHASE START]` — Inner phase-implementer begins
- `[PHASE END]` — Inner phase-implementer completes successfully
- `[CLUSTER PROGRESS]` — Cluster-implementer marks progress between cluster phases (only in efficiency-style cluster delegation, which one-shot also uses)
- `[BLOCKING DEVIATION]` — A contract-affecting deviation was detected. In one-shot mode, this aborts the workflow.
- `[COMPACTION]` — Auto-compaction fired (appended by PreCompact hook in one-shot mode in lieu of the missing status.md)

**Rules:**
- Append-only — never modify or remove prior entries
- Entries are dense (one event per `###` block) — this is operational log, not narrative
- The final-reviewer reads this log alongside the working tree to reconstruct what was built and when
- No item-level state is tracked here (no `(todo)`/`(acceptance)`/`(done)` markers) — granular item state would bloat the log without forensic value; the working tree is the source of truth for what was implemented

---

## Naming Conventions

- Topic slugs: kebab-case, derived from topic name (e.g., "API Endpoints" → `api-endpoints`)
- All timestamps: ISO 8601 with timezone (UTC preferred)
- File encoding: UTF-8
- Line endings: LF
