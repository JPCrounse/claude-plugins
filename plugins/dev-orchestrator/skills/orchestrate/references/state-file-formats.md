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
- `version` — Schema version for forward compatibility
- `created` / `updated` — ISO 8601 timestamps
- `mainTopic` — The overarching goal with name, slug, description
- `subtopics` — Array of subtopics (empty array if user chose not to split). Each has name, slug, description
- `currentPhase` — One of: `context-collection`, `roadmap-generation`, `implementation`, `final-review`, `complete`
- `sessions` — Append-only log of session starts, with compaction count per session

When there are no subtopics, the main topic acts as the single topic. Use `mainTopic.slug` as the directory name.

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
| API Endpoints | started | Phase 2: Endpoints | 2/6 done | No |

## Detail

### Data Models
- [x] Phase 1: Schema Design (4/4 done)

### API Endpoints
- [x] Phase 1: Core Endpoints (3/3 done)
- [ ] Phase 2: Endpoints (2/6 done, 1 started)
- [ ] Phase 3: Testing (0/3 todo)
```

**Status values for topics:** `todo`, `started`, `acceptance`, `done`

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

## Phase 1: Schema Design
Priority: High
Dependencies: None
Estimated items: 4

### Checklist

#### Group 1 [sequential]
1. Define User model with all required fields and constraints

#### Group 2 [concurrent]
2. Define Session model with foreign key to User
3. Define RefreshToken model with rotation support

#### Group 3 [sequential]
4. Add database indexes for email lookups and token queries

## Phase 2: Migrations & Seed Data
Priority: High
Dependencies: Phase 1
Estimated items: 3

### Checklist

#### Group 1 [sequential]
1. Generate and review Prisma migration

#### Group 2 [concurrent]
2. Create seed script for development/test users
3. Write migration verification tests

## Phase 3: Validation Layer
Priority: Medium
Dependencies: Phase 1
Estimated items: 3

### Checklist

#### Group 1 [concurrent]
1. Add Zod schemas for User create/update inputs
2. Add password strength validation per NIST guidelines

#### Group 2 [sequential]
3. Add unit tests for all validators
```

**Structure rules:**
- Phases are numbered sequentially
- Each phase has: Priority, Dependencies, Estimated items count
- Checklist items are numbered globally within each phase (continuous numbering)
- Items are specific and actionable (not vague)

**Concurrency group rules:**
- Items within a phase are organized into numbered groups
- Each group is marked `[concurrent]` or `[sequential]`
- `[concurrent]` — items in this group have no dependencies on each other and can be implemented in parallel (via parallel sub-agents)
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
- `[x] (done)` — User-verified complete

**Phase header states:** `[PENDING]`, `[IN PROGRESS]`, `[COMPLETE]`

**Session log rules:**
- Each entry starts with ISO 8601 timestamp header
- Append-only (never modify previous entries)
- Include: what was done, key decisions, relevant file paths
- Compaction entries marked with `[COMPACTION]` suffix
- Keep entries concise — this log enables session resumption, not full audit

---

## Naming Conventions

- Topic slugs: kebab-case, derived from topic name (e.g., "API Endpoints" → `api-endpoints`)
- All timestamps: ISO 8601 with timezone (UTC preferred)
- File encoding: UTF-8
- Line endings: LF
