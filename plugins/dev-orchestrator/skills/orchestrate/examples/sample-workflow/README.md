# Sample Workflow

A worked example of `.dev-orchestrator/` state captured at the moment Phase 3 (Roadmap Generation) has completed and Phase 4 (Implementation) is about to begin.

**Scenario:** A `user-authentication-system` workflow split into two subtopics, `data-models` and `api-endpoints`, configured for supervised + efficiency execution + deferred acceptance. Phase 3.5 has already rewritten `executionMode` from `"deferred"` to `"efficiency"`.

## What this example shows

- The shape of `manifest.json` after Phases 1, 1.5, 2, 3, and 3.5 have all set their respective fields.
- A multi-topic workflow's `status-overview.md` at the root.
- Per-topic `guidance.md` files (Phase 2 output).
- Per-topic `roadmap.md` files including the `## Clusters` registry, per-phase `Cluster:` line, and per-item `Affects:` annotations (Phase 3 output).
- Per-topic `status.md` files with all items in `(todo)` state — no implementation has begun.

## Files

```
.dev-orchestrator/
├── manifest.json
├── status-overview.md
├── data-models/
│   ├── guidance.md
│   ├── roadmap.md
│   └── status.md
└── api-endpoints/
    ├── guidance.md
    ├── roadmap.md
    └── status.md
```

This example does not include `one-shot-log.md` (only present in one-shot mode) or any session-log entries from Phase 4 (no implementation has run yet).

## What is NOT shown

- Phase 4 progress (items transitioning to `started`, `acceptance`, `done`).
- Session log entries from `phase-implementer` or `cluster-implementer` returns.
- A `[BLOCKING]` item or `[BLOCKING DEVIATION]` session entry.
- A one-shot workflow's `one-shot-log.md`.

For the schema of those forms, see `references/state-file-formats.md`.
