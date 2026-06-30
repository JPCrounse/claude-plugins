# Diagnostic Heuristics — Root-Cause Reference

Self-contained reference for the `bug-researcher` agent's Research phase. Read this
when classifying an error, choosing where to look for it in source, correlating it
with releases, or deciding whether it's even a bug.

---

## Table of Contents

1. [Purpose and when to read this](#1-purpose-and-when-to-read-this)
2. [Error-shape classification](#2-error-shape-classification)
3. [Source-location strategy](#3-source-location-strategy)
4. [Release and git correlation](#4-release-and-git-correlation)
5. [Triage heuristics](#5-triage-heuristics)
6. [Guided deepdive](#6-guided-deepdive)

---

## 1. Purpose and when to read this

Read this file during the Research phase of any bug investigation — before grepping,
before forming hypotheses, before recommending fixes. It gives you the full set of
classification, search, and triage patterns needed to diagnose a production error
sourced from a Jira issue (which may contain a linked Bugsnag error, a pasted stack
trace, a symptom description, or some combination). Nothing here depends on any other
plugin being installed.

---

## 2. Error-shape classification

The shape of an error determines the best search strategy. Misclassifying the shape
wastes time — especially with minified JS or framework internal traces that point at
the wrong file. Classify first, then search.

| Shape | Tell | Why it matters | Search strategy |
|---|---|---|---|
| **HTTP error response** | Message contains a URL and HTTP status code (`HttpErrorResponse`, `fetch failed`, `HTTP 500`) | Cause is often backend, not the grepping target; the frontend just surfaces it | Grep the URL path in route definitions and API call sites. Flag early that the root cause may be backend. If 4xx with a structured body, check expected-state first (see §5). |
| **JS TypeError / ReferenceError** | Mangled `x.x(x)` frames in minified traces; messages like `Cannot read properties of undefined`, `x is not a function` | Production stacktraces are minified — reading the JS structure is meaningless | Grep the literal error message text. Fall back to the breadcrumb trail (last navigation, last network call, last user action). Check whether source maps (`.map` files) exist in the build output. |
| **Wrapped server payload** | Structured fields in the error body: `errors[].code`, `errors[].title`, `detail`, or API error envelope | The server returned a structured expected-state response; the client threw instead of handled it | Ask whether this should be caught-and-handled rather than thrown. Grep for the error code or title — both in the backend (where it's constructed) and in the frontend (where it should be consumed). |
| **Framework-specific — Angular `ExpressionChangedAfterItHasBeenChecked`** | Error class name matches exactly | The stacktrace points at Angular internals, not at the real source | The cause is a synchronous signal or state write inside a template binding during change detection. Look at the component's template and find where a signal or observable is written synchronously — not the file the trace points at. |
| **Framework-specific — React state-update-on-unmounted** | `Cannot update a component while rendering a different component` or similar | Stacktrace points at React internals | Find the application component that triggers a state update during its render cycle. The framework frame is noise. |
| **Framework-specific — .NET ObjectDisposedException** | `ObjectDisposedException` in the message | A disposed service is being used — usually a DI lifetime mismatch | Check dependency injection lifetime (scoped vs singleton). The disposer and the consumer are in different scopes. |
| **Framework-specific — Java NPE with empty stack** | `NullPointerException` with no frames (JIT-optimized away) | The JVM omitted the stack for performance | Add `-XX:-OmitStackTraceInFastThrow` to reproduce with frames, or find the source from the error message context alone. |
| **Timeout / connection error** | `ETIMEDOUT`, `ECONNREFUSED`, `ECONNRESET`, `socket hang up`, `deadline exceeded`, `context canceled` | Failure mode varies widely; the cluster shape of elapsed time reveals it without instrumentation | Apply the timing deduction heuristic (§5). Check whether the error correlates with a specific endpoint, time of day, or deployment. Many connection errors are infrastructure-level — be explicit about what the codebase can and cannot answer. |
| **Log-listener / error-publisher** | Top frames are from a logging library, error boundary, or log publisher, not from application code | The publisher is just reporting a failure that happened upstream | Look past the logging frames to what called the publisher. The actual failure is further up the stack or in the breadcrumbs before the error. |
| **Retry / queue** | Error appears in a job handler, queue worker, or retry context; metadata may include `attempt`, `retry_count`, `job.resolved` | Transient vs persistent is the key split; multiple job types through one handler is the secondary issue | Check whether the error is transient (succeeds on retry) or persistent (fails every attempt). If `context` or `job` metadata varies across occurrences, multiple distinct operations are failing through the same handler — enumerate them separately. |

---

## 3. Source-location strategy

Work through this ladder in order. Stop at the first strong hit. Going further than
necessary wastes time; stopping too early misses multi-call-path grouping.

### The ladder

1. **Unique substring of the error message.** A literal, specific fragment of the
   message text is the most direct search. Grep it. If the message is generic
   (`TypeError: Cannot read properties of undefined`) skip to the next step — too
   many results.

2. **URL path from an HTTP error.** If the error message contains a URL, grep for
   the path segment in route definitions, API call sites, and service files. Ignore
   query-string parameters at this stage.

3. **Context field or router URL.** The error's context (often the Angular/React
   router URL) maps to a feature folder. Grep the route path or component name to
   narrow scope. If a config maps router paths to project folders, use it.

4. **Breadcrumbs — last navigation or network request.** The most recent `Angular
   Route`, `Network Request`, or equivalent breadcrumb before the error points at the
   feature area that was active. Use it to narrow the folder even when the message
   and URL are generic.

5. **Non-vendor stack frame.** Even in minified traces, the file path and line
   number in app-owned files are usually preserved. The frame `<app>/src/...` is
   more useful than `<vendor>/node_modules/...`. Skip framework-internal frames and
   look for the first frame in code you own.

### Scope restriction

Before grepping, restrict the search to the relevant source paths for the project
being investigated. Grepping the entire monorepo wastes time and produces false
positives from unrelated packages.

### Delegating broad searches

For exploratory or broad searches — "find every call site that hits this path" or
"what components render this route" — delegate to an Explore subagent rather than
chaining many individual greps inline. Targeted single lookups can use Grep directly.

### Multi-call-path grouping

Bugsnag (and similar tools) group errors by stack frame (file + line). A shared
helper called from five places shows as one error group. Before deep analysis, pull
multiple occurrences (10 or more if available) and compare the `context` field —
and `metaData.job.resolved` for queue errors — across them. If `context` varies,
multiple call paths share the fingerprint and any fix must cover all of them.

---

## 4. Release and git correlation

Use git history to confirm which deploy introduced the error and verify that a
candidate commit actually shipped in the relevant release.

### Find commits in the introducing window

```sh
git fetch --tags
git log --oneline <prev-tag>..<intro-tag> -- <suspect-path>
```

The `--` scoping to a suspect path (or folder) reduces noise. Commits that touched
the suspect path within the introducing window are strong candidates.

If the previous tag does not resolve after fetching — possible in repos that prune
old tags — fall back to:

```sh
git log --since="<first_seen_date - 2 days>" -- <path>
```

### Normalize rates per release, not raw counts

Raw event counts per release are misleading because releases stay in production for
different lengths of time. A release in prod for eleven days accumulates more events
than one in prod for one day, even if the underlying error rate is identical or lower.

To find the triggering release:

```sh
git log --tags --simplify-by-decoration --pretty='%ai %D' --all | grep v
```

Use those dates to compute `rate = events_in_release / days_in_prod` for each
release in the investigation window. The release where rate first rises sharply —
not the one with the highest absolute count — is the trigger.

### Verify a candidate commit actually shipped

A commit on a development or feature branch may not have been included in the
release where the error first appeared. Always verify:

```sh
git tag --contains <sha>
```

If the first tag containing the suspect commit is dated after the error spike began,
that commit cannot be the cause — keep looking. This check prevents false conclusions
from commits that were merged but not yet released at the time of the incident.

### Distinguish "introduced in" from "spiked in"

The first release that emitted an error is not necessarily the release where it
started ramping. A latent bug may emit at a low base rate before a follow-on change
(traffic increase, data migration, dependent service update) causes it to spike.
Per-release rate normalization will surface this distinction.

---

## 5. Triage heuristics

These patterns apply regardless of language, framework, or error-tracking tool.
Apply them before committing to a code investigation — several will save you from
investigating the wrong thing entirely.

### Expected-state filter

HTTP 403, 401, or 409 responses with a structured error payload (`errors[].code`,
`errors[].title`, `detail`) are usually API contracts, not bugs. The server is
behaving correctly — it rejected an authentication failure, a validation error, a
rate limit, or a conflict. Before investigating source code, ask: "Should this
response be caught and handled by the caller, rather than thrown as an error?"

This is the first question to ask, not the last. A large proportion of "errors" in
production tracking tools are expected states that were never caught. Answering this
question early avoids deep analysis of working code.

### Polling tells

High event count divided by low user count — roughly 5 to 20 events per user — is
the signature of a polling loop reporting a recurring expected error on each tick.
Look for `interval`, `timer`, `setInterval`, `repeatWhen`, `cron`, or retry logic
near the failing call site. The fix is almost always to catch the expected response
inside the polling handler, not to change what the server returns.

### Timing deduction from URL TTL parameters

When the failing URL embeds an expiry marker — `Expires=<unix>`, `valid_until=`,
a signed-URL TTL, or a JWT `exp` claim — and the minting code uses a known fixed
window (read the source: `signedUrl($path, ttl: 600)` means 600 seconds), compute
`elapsed = event_time - (Expires - ttl_seconds)` for at least 30 events. The
cluster shape reveals the failure mode without adding instrumentation:

| Cluster pattern | Failure mode |
|---|---|
| Tight cluster at a round timeout value (60s, 30s) | **TCP-level stall** — connection opened but no bytes flowed. The round number is the `default_socket_timeout` or equivalent. |
| Cluster near 0 seconds | **Immediate failure** — DNS resolution failure, connection refused, TLS rejection, or auth 4xx. The request never got past the handshake. |
| Smooth distribution from 0 to N seconds | **Slow-but-flowing transfer** — large files, slow upstream, or bandwidth contention. Not a traditional timeout. |
| Cluster at a specific large value matching a queue runner timeout | **External kill timer** — a queue worker `--timeout`, load balancer idle timeout, or container orchestrator grace period. The job was killed externally, not by a per-call timeout. |

Use this before suggesting "add a timer and log durations" — the data is already
present in the error metadata.

### Fan-out as amplifier

When a single domain event triggers N sequential operations — multi-size thumbnail
generation, multiple listeners on the same event, a multi-step pipeline, a retry
loop — any per-operation flakiness is multiplied by N. A 1% per-call failure rate
with a 5x fan-out becomes a 5% per-event failure rate in the tracking tool.

When the root cause is infrastructure or transient, the fan-out multiplier is often
the cheapest fix available: reducing fan-out from 5x to 2x cuts the effective error
rate by 60% without touching the underlying problem. Surface this as a separate
recommendation even when the underlying flakiness cannot be fixed from application
code.

### Empirical confirmation over instrumentation

Existing event metadata frequently answers timing and source questions without any
code changes. Before suggesting "add logging and wait for the next occurrence," always
check:

- URL parameters (TTLs, request IDs, session tokens, signed-URL expiry markers)
- Breadcrumbs and preceding log entries
- Request and response headers
- Structured metadata (job class, queue name, user agent, console input, attempt count)
- Retry counters and attempt numbers

Signed URL TTLs, request IDs, and retry counters often carry diagnostic data the
original author did not intend to be useful for debugging, but it is there and it is
free. Instrumentation means waiting for the next event and another deploy cycle;
empirical confirmation from existing data is immediate.

### Dev-mode reporting gap

Most error-tracking setups gate event reporting in development mode. Errors seen
locally do not reach the tracking tool. Never tell the user "I'll reproduce this
locally and check the error tracker" — it will not work.

---

## 6. Guided deepdive

A guided deepdive is iterative, hypothesis-driven investigation for when the initial
triage identified a likely cause but the evidence is not yet strong enough to act,
or the user wants to check a different angle before committing to a fix.

### The core loop

**1. Ask for a concrete direction.** Open-ended prompts produce shallow work. Ask
for one of: a specific hypothesis ("this started after the nginx config change"), a
code path to trace ("find every caller of `processAsset`"), a timing question ("are
failures bursty or steady across the day"), or an external correlation the user can
supply ("we deployed on May 1 — does the timing line up"). If the user is vague,
push back with concrete options based on what the initial report found.

**2. Lock the question.** Restate the hypothesis or question in one sentence so
both sides agree on the target before any investigation runs. Investigations that
drift across multiple implicit questions produce ambiguous conclusions.

**3. Match question type to evidence source.**

| Question | Evidence source |
|---|---|
| Timing / failure distribution | Pull ≥30 events; parse timestamps and any TTL params embedded in URLs |
| "Did commit X cause this?" | `git tag --contains <sha>`, `git log <prev-tag>..<intro-tag>` |
| "What other call sites hit this path?" | Grep for the method/file; compare context across multiple occurrences |
| "Are multiple code paths grouped here?" | Compare context and metadata across ≥10 occurrences |
| "Volume per release" | Tag date lookup + events / days-in-prod normalization |
| "Timeout vs immediate fail vs slow transfer" | Timing deduction heuristic (§5) using embedded expiry markers |
| "What changed in the release window?" | `git log v<prev>..v<this> -- <scoped-paths>` |
| External correlation (deploy log, infra change) | Ask the user to paste the context — the codebase cannot answer this |

**4. Report sharply.** Two things only: the evidence (concrete numbers, file/line
refs, commit SHAs — show data, not narrative) and the verdict on the hypothesis
(confirmed, refuted, partially supported, or "evidence not in available data; need
`<external thing>`"). Be willing to say the data is insufficient rather than
speculating.

**5. Update the running theory.** If the deepdive shifted the leading cause,
restate it explicitly. Multiple rounds accrete into tangled answers if the current
best hypothesis is not kept front and center after each round.

**6. Loop or hand off.** Ask: "Dive again with another angle, or ready to act?"
There is no fixed round limit — the user decides when the evidence is sufficient.
Most investigations need two to four rounds before the right action is clear.

### When not to dive further

- The hypothesis is already confirmed and the user is asking again out of habit.
  Surface that: "We have high confidence on X already — what specifically would
  change your assessment?"
- The remaining unknowns are outside the codebase (infra logs, deploy diffs, network
  captures, upstream service health). Hand back to action with the explicit gap noted.
- The user has reframed the same question twice without new information. After two
  rounds on the same theme, stop and ask what would specifically constitute sufficient
  evidence to act.
