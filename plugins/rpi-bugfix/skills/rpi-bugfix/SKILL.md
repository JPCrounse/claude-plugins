---
name: rpi-bugfix
description: |
  Take a single bug from a Jira issue key all the way to a verified pull request through a gated Research → Plan → Implement workflow. Use this skill when the user wants to drive a specific, ticketed bug all the way to a shipped fix/PR — they name or clearly imply a Jira issue AND intend to land a code change, not just diagnose or triage it: "fix NEXTHP-123", "work this bug ticket through to a PR", "research, plan and implement the fix for this Jira bug", "take this bug from ticket to PR". Also use it to resume an in-progress fix — "continue the fix for NEXTHP-123", "where did we leave off on that bug", "resume the rpi-bugfix workflow" (resume triggers assume a `.rpi-bugfix/` state directory already exists). It interviews the user, writes an approved spec, validates impact against the code graph, plans the fix, implements it on a `fix/` branch with a regression test, and opens the PR — pausing at three hard human gates (spec approval, reproduction confirmed, post-fix reproduction passes). It delegates diagnosis and PR steps to existing tools (debug-error/bugsnag-triage methodology, self-review, pr-ci-fixer) rather than reimplementing them. Do NOT use it for: triaging a Bugsnag error with no Jira ticket and no intent to ship a fix (use bugsnag-triage); pure root-cause diagnosis with no intent to implement (use debug-error); a quick one-file change the user already understands (just make the edit); or large multi-bug or multi-subsystem efforts (use the dev-orchestrator plugin's orchestrate skill).
---

# RPI Bugfix

Drive a single bug from a Jira issue key to a verified pull request through a gated **Research → Plan → Implement** workflow. All progress persists to `.rpi-bugfix/<JIRA-KEY>/` so the workflow survives compaction and resumes across sessions.

This skill is a **thin orchestrator**. It owns the gated ceremony and the user interaction; it **delegates** the heavy lifting — diagnosis to the `debug-error`/`bugsnag-triage` methodology (applied inside the `bug-researcher` agent via the bundled `references/diagnostic-heuristics.md`), and pre-push/PR work to the `self-review` and `pr-ci-fixer` skills. Four agents do the isolated work and return bounded summaries; the main thread (this skill) stays lean and runs the gates.

The protocols below are summaries. For full entry/exit criteria, error handling, and the agent handoff formats, read `references/workflow-phases.md`. For state-file schemas, read `references/state-file-formats.md`.

## Prerequisites

- **Required:** the `bugsnag-triage` plugin is installed — it provides the Jira and Bugsnag MCP servers (`mcp__plugin_bugsnag-triage_*`) the research agent uses, and the shared `.claude/bugsnag-triage.config.json`. If a repo has no such config, the workflow degrades gracefully (see Graceful Degradation).
- **Optional enhancements:** a `.codegraph/` index (else Explore+Grep fallback); the `self-review` and `pr-ci-fixer` skills (else inline fallback); the Figma MCP (for UI bugs only). None of these are hard dependencies.

## Session Detection

Before starting, look for existing state under `.rpi-bugfix/`.

- If the user names a Jira key, check `.rpi-bugfix/<JIRA-KEY>/state.json`.
- Otherwise list the bug directories under `.rpi-bugfix/` and ask which to resume (or whether to start a new one).

**Found:** read `state.json` (including `mode`, `intensity`, and the `feedback` block), summarize where it left off, and append a new entry to its `sessions` array (ISO 8601 timestamp + current phase). **First**, if `feedback.awaitingImplementation == true` — the previous session was aborted at a rapid-mode checkpoint to implement feedback — run the Abort→Implement→Rewind step in **Rapid-Iteration Mode** before any other work. Otherwise resume at `currentPhase` per the Session Resumption Protocol in `references/workflow-phases.md`. Respect gate state — a workflow paused at a gate resumes by re-presenting that gate.

**Not found:** begin Phase 1.

## Model Advisory (inline)

The agents are pinned per phase (Opus for research/validation/planning, Sonnet for implementation), so quality is guaranteed regardless of the session model. The interactive interview, however, runs in this main thread — recommend the driving session be on Opus for it. If the session is not on Opus, note this once (e.g. "research agents are pinned to Opus; consider `/model opus` for the interview") and **proceed** — do not block. Record the note in `state.json.sessionModelWarning`.

## Mode & Intensity

Two orthogonal per-session settings, both recorded in `state.json` and re-confirmable on resume:

- **Mode** — `standard` (default) or `rapid`. `standard` is the base workflow, unchanged. `rapid` adds a feedback checkpoint after every phase plus an abort→implement→rewind loop, for tightening the skill itself while dogfooding it — see **Rapid-Iteration Mode** below. It never skips or weakens a gate.
- **Intensity** — `high` (default), `medium`, or `low`. It sets how much investigative breadth each delegated agent applies. `high` reproduces today's behavior; `medium`/`low` trade thoroughness and latency for faster, cheaper iterations. **Intensity never weakens the fix's correctness, the regression-test decision, the evidence standard, or any of the three gates** — it only trims investigative breadth. On every agent delegation, append the **Intensity block** for the active level to the task-brief *suffix* (the cacheable prefix stays static); its row-by-row contents are the Intensity mapping table in `references/workflow-phases.md`. At `high` the block is the current behavior, so it may be omitted.

**Selection (new session, in Phase 1):** after seeding from Jira, ask for the mode and intensity — default `standard` + `high`, a no-op relative to the base flow — or accept them from trigger phrases ("rapid iteration mode", "low/medium/high intensity"). Persist both into `state.json` at creation. On resume, honor the stored values and accept changes ("switch to rapid", "set intensity medium").

## Phase 1: Research

Run the interview **in the main thread** — agents cannot ask the user live follow-up questions, and this keeps the raw Jira/Bugsnag payloads out of the long-lived thread.

1. **Seed.** Fetch the Jira issue (`jira_get_issue`) for its title, type, body, and links. Derive the slug for the branch name from the title.
2. **Create state.** Create `.rpi-bugfix/<JIRA-KEY>/` and write `state.json` (schema in `references/state-file-formats.md`): `jiraKey`, `currentPhase: "research"`, the selected `mode`/`intensity` (defaults `standard`/`high`), gate statuses `pending`, the `feedback` block at its defaults, zero-initialized `metrics`, the first `sessions` entry.
3. **Interview.** Ask only non-obvious questions, informed by the issue body: exact reproduction steps, screenshots (capture as text), confirmation of the involved project(s) from the config, the Bugsnag error id/URL if any, relevant logs, and — for UI/visual bugs — a Figma link. If a Figma link is given, fetch the intended design context here (the main thread has full tool access) and carry it into the brief as text.
4. **Delegate research.** Invoke `bug-researcher` with the assembled brief and the state-dir path. It fetches the Bugsnag error, locates the source, correlates git/release history, assesses test coverage, and writes `spec.md`. Increment `metrics.agentInvocations`.
5. **Handle open questions.** If the handoff returns open questions, re-interview the user to resolve them and re-invoke `bug-researcher`. The spec's Open Questions section must be empty before the gate.

### Gate G1 — Spec Approval (HARD)

Present `spec.md`. The user reviews and edits it directly (it is the contract for everything downstream). **Do not run the code graph or touch any code until the user approves** — every later phase trusts the spec, so an unreviewed assumption here propagates into the impact analysis, the plan, and the fix. On approval set `state.json.gates.specApproved = true` and `currentPhase: "impact"`.

## Phase 2: Impact Analysis

Delegate to `codegraph-validator` with the state-dir path. It reads only the approved `spec.md`, validates each claim against the code graph (or Explore+Grep fallback), computes the blast radius, and writes `impact-analysis.md`. Increment `metrics.agentInvocations`.

Present the verdicts. **If the suspected source was refuted**, highlight it — the plan must build on the verified view, not the original hypothesis. Set `currentPhase: "plan"`.

## Phase 3: Plan

Delegate to `bug-planner` with the state-dir path. It reads `spec.md` + `impact-analysis.md`, writes `plan.md` (ordered fix steps with `Affects:` annotations, risk areas), and decides the regression-test policy. Copy its `regressionTest` decision (`required` | `documented-no-harness`) into `state.json`. Increment `metrics.agentInvocations`. Present the plan.

### Gate G2 — Reproduction Confirmed (HARD, waivable)

Ask the user to reproduce the bug using `spec.md`'s steps **before** any code is written — confirming the repro now prevents sinking effort into an unverified fix.

- **Confirmed** → set `gates.reproConfirmed = "confirmed"`, proceed.
- **Cannot reproduce (heisenbug)** → offer to waive. On waive, set `gates.reproConfirmed = "waived"` with the reason in `session-notes.md`, and warn that the fix will be unverified by reproduction — G3 will then necessarily be waived too, and the PR must say so.

## Phase 4: Implementation

1. **Create the branch.** From the integration branch, create `fix/<JIRA-KEY>-slug`. Resolve the integration branch from `.claude/bugsnag-triage.config.json` (`integrationBranch`); if absent, detect the default branch (`gh repo view --json defaultBranchRef`, else `origin/main|master|develop`) or ask. Record `branch` in `state.json`.
2. **Delegate implementation.** Invoke `bug-implementer` with the state-dir path, the branch name, and the `checksCommand` (from config, or note none). It edits the working tree, writes the regression test the plan requires, runs the checks, and appends gotchas to `session-notes.md`. It does **not** commit or push. Increment `metrics.agentInvocations`; roll up its reported sub-agent count into `metrics.subAgentSpawns`.
3. **Handle a blocking issue.** If the handoff sets `blockingIssue: true`, the code refuted a plan assumption — pause, re-delegate `bug-planner` with the new constraint, then re-implement. Do not push a fix built on a broken assumption.

### Phase 4b — Self-Review

If the `self-review` skill is installed, invoke it (`Skill(self-review)`) on the branch diff and surface its findings for the user to address or accept. If it is not installed, do a light inline diff sanity-check and note that the dedicated audit was skipped. Never hard-fail for a missing optional skill.

### Gate G3 — Post-Fix Reproduction Passes (HARD)

Ask the user to re-run the reproduction steps against the fix. **Passes** → set `gates.postFixReproPassed = true`, proceed to the PR. (If G2 was waived, G3 cannot be satisfied by reproduction — record it waived and ensure the PR body flags the fix as unverified.)

## Phase 5: PR + Retrospective

1. **Draft and confirm the PR.** Compose the title `fix(<JIRA-KEY>): <summary>` and a body that links the Jira issue and Bugsnag error, summarizes the fix, and flags "unverified by reproduction" if G2/G3 were waived. **Show the draft and get explicit confirmation before creating anything** — opening a PR is an outward-facing action.
2. **Commit, push, open.** Commit on the `fix/<JIRA-KEY>-slug` branch with the `fix(<JIRA-KEY>): <summary>` message, push, and open the PR (`gh`).
3. **CI.** If CI comes back red and the `pr-ci-fixer` skill is installed, invoke it (`Skill(pr-ci-fixer)`); otherwise surface the failing job for the user to address.
4. **Retrospective (inline).** Append a closing summary to `session-notes.md` (the searchable per-bug index). For broader, reusable lessons — a non-obvious debugging journey, a class of bug worth remembering — **propose** Claude-memory entries and write them only on user confirmation. Set `currentPhase: "complete"` and offer to clean up `.rpi-bugfix/<JIRA-KEY>/` (keep, archive, or remove). In rapid mode, run the deferred-feedback step (below) **before** cleanup.

## Rapid-Iteration Mode

Active only when `state.json.mode == "rapid"`. It layers a **skill-improvement** feedback loop on top of the base workflow to tighten the skill itself while dogfooding it — every gate stays exactly as it is; nothing here skips or weakens G1/G2/G3. The feedback is about the *rpi-bugfix skill* (its SKILL.md/agents/references), **not** the bug's artifacts (the gates already let the user edit those directly). **The full protocol — exact prompts, state transitions, rewind mechanics, and the branch/PR caveats — lives in `references/workflow-phases.md`; the summary here is enough to drive it.**

- **Per-phase feedback checkpoint.** After each phase finishes its work *and* its gate/handoff is processed — Research→G1, Impact, Plan→G2, Implement→(self-review + G3), PR→complete — and before advancing, ask whether the user wants to leave feedback on that phase. If they do, append a `pending` entry to `session-feedback.md` (timestamp · phase · intensity · the note), bump `feedback.pending`, then ask **Continue** (bank it and go on) or **End now** (stop to implement it).
- **End now** sets `feedback.awaitingImplementation = true` and `feedback.resumePhase = <current phase>`, writes a `[FEEDBACK-ABORT]` marker to `session-notes.md`, and stops — Session Detection picks it up next time. In rapid mode, defer each gate's `currentPhase` advance until after the checkpoint, so an abort leaves `currentPhase` at the just-finished phase.
- **Deferred (banked) path.** On reaching `complete` with pending feedback and no abort, surface the list and offer to implement it against the plugin source now; flip entries to `implemented`. The bug already shipped, so this improves *future* runs — no rewind.
- **Abort→Implement→Rewind path.** On resume with `awaitingImplementation == true`: implement the pending feedback against the plugin source, then offer to **rewind** the bug to `resumePhase` and re-run it with the improved skill, so the effect is visible immediately.
- **Rewind** (also a general "restart \<KEY\> from the \<phase\> phase" request in either mode): reset `currentPhase`, stale the artifacts of that phase onward, reset the gates at/after it, then re-run — mechanics and the no-auto-git / opened-PR caveats are in `references/workflow-phases.md`.

**Feedback edits the plugin source, not this bug.** If the working tree is not the `claude-plugins-jp` plugin repo, do not edit blindly — surface the pending list and point at the plugin repo; optionally validate with the `plugin-dev` skills.

## Metrics

The harness exposes no token meter, so `state.json.metrics` stands in as the cost proxy: increment `agentInvocations` on every delegation and roll up `subAgentSpawns` from handoffs. Soft backstop: if `subAgentSpawns` climbs past ~8 on one bug (usually a thrashing implementer), surface it and ask before continuing.

## Token Optimization Protocol

Context management is automatic. **`/compact` is a user-only command — never prompt the user to run it as part of the workflow.** Five mechanisms keep the orchestrator thread lean:

1. **Subagent delegation.** Heavy reads, the code graph, edits, and test runs happen inside the four agents, each in its own context. Only bounded handoffs (~1–2K tokens) return here.
2. **Distilled-artifact handoffs (no double context load).** Each phase reads only the prior phase's distilled `.md` — `spec.md` → `impact-analysis.md` → `plan.md` — never the raw upstream context. The raw Bugsnag blobs die in `bug-researcher`; the `codegraph_explore` dump dies in `codegraph-validator`. The implementer JIT-reads only the files the plan names.
3. **File-based state + bounded reads.** All progress lives in `.rpi-bugfix/<JIRA-KEY>/`; the skill never depends on conversation history. After compaction, re-read `state.json` and the **tail** of `session-notes.md` (recent entries + any open blocker), never the whole log.
4. **Prompt-cache preservation (maintainer guard).** Agent system prompts and task-brief templates stay **static** — no `<JIRA-KEY>`, branch name, timestamps, or dynamically-assembled tool lists in the prefix. Per-invocation variables go in the task-brief suffix, after the cacheable prefix. One stray key in a prompt prefix forfeits the cache discount on every call.
5. **Cost visibility.** The `metrics` counters above, surfaced in the final summary.

`PreCompact` hook behavior is in `references/workflow-phases.md` (Context Management); it appends a `[COMPACTION]` marker to each active bug's `session-notes.md`.

## Graceful Degradation

- **No `.claude/bugsnag-triage.config.json`** (most common gap): ask the user to confirm project(s)/source paths in the interview; default the integration branch via the detection ladder; ask for or skip `checksCommand` with a logged note. Do not bail.
- **No Bugsnag link on the issue:** `bug-researcher` works from the stack trace/description using the bundled heuristics (generic path).
- **No `.codegraph/` index:** `codegraph-validator` falls back to Explore+Grep and stamps the analysis; never run `codegraph init` automatically.
- **Bug not reproducible:** waive G2 (and consequently G3); flag the unverified fix in the PR body.
- **`self-review` / `pr-ci-fixer` not installed:** degrade to the inline fallbacks above; never hard-fail.
- **Jira auth fails / key not found:** fail fast at the entry point and surface the PAT-regeneration guidance — do not start the pipeline against a bad key.

## Reference Files

- `references/workflow-phases.md` — per-phase entry/exit/error handling, the Session Resumption Protocol, Context Management, the full agent handoff formats, and the rapid-iteration protocols (feedback checkpoint, abort→implement→rewind, intensity mapping table).
- `references/state-file-formats.md` — schemas and worked examples for `state.json`, `spec.md`, `impact-analysis.md`, `plan.md`, `session-notes.md`, and `session-feedback.md`, plus the bounded-reads rule.
- `references/diagnostic-heuristics.md` — **(agent-only; the orchestrator never reads it)** the self-contained root-cause playbook `bug-researcher` reads during Research: error-shape classification, source-location ladder, release correlation, triage heuristics.
