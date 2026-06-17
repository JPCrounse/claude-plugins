# AI Token-Usage Optimization — Guidance

A working reference for designing agentic AI systems (and the prompts/agents/skills that drive them) to control token consumption and cost at scale. Distilled from CockroachLabs' *"The hidden economics of agentic AI: managing costs at scale"* (cockroachlabs.com/blog/agentic-ai-costs-at-scale), with the source's quantitative findings preserved so this doc can be used both as design guidance and as an audit rubric.

> **Why this matters.** Gartner projects **40% of agentic-AI projects will be cancelled by 2027 due to cost overruns** — not technical failure. The teams that survive *modeled costs before deploying, instrumented usage alongside the product, and measured output rather than consumption.* Cost discipline is a design property, not an afterthought.

---

## 1. The core problem: where agentic tokens actually go

Agentic systems consume **5–30× more tokens per task than a single chatbot turn** (Gartner, 2026), and Goldman Sachs projects a **24× increase in token consumption by 2030**. The dominant driver is not the "useful" generation — it is overhead that compounds across the many model calls a single task requires:

- **Re-sent context is ~62% of total agent inference cost** (Stanford Digital Economy Lab). System prompts, tool definitions, and accumulated state get re-transmitted on every step of a multi-step workflow.
- **Context rot**: Chroma's 2025 testing found *every* frontier model degrades as input length grows — **30%+ accuracy loss in mid-window positions**, noticeable after **20–30 turns** (well within normal agent runs). Bigger context is not just costlier; it is *less accurate*.
- **Inference is only ~20% of total cost of ownership.** The other ~80% is orchestration, evaluation, monitoring, governance, and tooling. Optimizing the model bill alone misses most of the iceberg.

The throughline: **per-call token count × number of calls** is the real bill, and both factors balloon silently. Optimization means attacking both.

---

## 2. The optimization levers

Each lever below lists *what it is*, *the evidence*, *how to apply it*, and *the anti-pattern that destroys it*.

### Lever 1 — Prompt caching (highest ROI)
- **What:** Keep the *prefix* of every repeated call (system prompt, tool schemas, stable instructions) byte-identical so it is served from cache.
- **Evidence:** Cache reads cost **$0.30/MTok vs $3.00/MTok standard — a 90% reduction.** Break-even at **2.3 reuses** within the cache TTL (≈1 hour). Agentic workflows reuse the same prefix dozens of times per task, so the ceiling is enormous.
- **How to apply:** Put everything stable *first*; put per-call variables (the specific task, IDs, user data) *last*, after the cacheable prefix. Frequently-invoked agents benefit most — keep their prompts and brief-templates static.
- **Anti-patterns (cache killers):** Injecting `Today is <date>` into a system prompt (invalidates the cache daily — one team got a **1% discount instead of 90%**). Session/request IDs in the prefix. Dynamically-assembled or reordered tool registrations (LangChain's `react_agent` injecting unique IDs produced **0% cache hits** on identical prompts). Per-call personalization spliced into the prefix.

### Lever 2 — Context management (four sub-levers)
Keep each working context as small as the task allows. Target **working context under ~8K tokens** for consistent accuracy.
1. **Compaction** — summarize conversation history as it nears limits, *preserving decisions and outstanding tasks*; discard transcript noise.
2. **Layered / tiered tool calling** — coordinator holds high-level tools and activates specialists on demand. Do not ship all 40 tool schemas on every call when 3–5 are needed. (Tool-schema bloat is pure re-sent-context tax — see Lever 1.)
3. **Just-in-time retrieval** — pull context only when the agent signals it needs it, rather than front-loading everything "in case."
4. **Sub-agent isolation** — split work across agents with clean contexts that return small (**~1,000–2,000 token**) summaries to the coordinator. Implementation residue lives and dies in the sub-agent's discarded context.

### Lever 3 — Model routing discipline
- **What:** Route each subtask to the cheapest model that can do it; reserve premium models for genuine planning/judgment.
- **Evidence:** A single team cut spend **from $40K to $24K/month ($16K saved) by routing simpler subtasks to cheaper models — no product change.** The per-token gap ($0.50 vs $3.30/MTok) looks trivial for one query but becomes "a real unit-economics problem" across ~15 calls per task with accumulating context.
- **How to apply:** Match model (and reasoning effort) to role — read-only reporting → cheapest/lowest effort; execution → mid-tier; planning/architecture/final judgment → premium/highest effort.

### Lever 4 — Reliable state / avoid the retry multiplier
- **What:** Unreliable state access (timeouts, stale reads, schema mismatches) makes agents *retry*, and each retry re-sends the full context plus a new tool call.
- **Evidence:** A **3-retry pattern on a single read triples** that step's token cost; across thousands of sessions this dominates the bill. A healthcare company's inference cost jumped **$12K → $68K in six weeks** from retrieval faults alone.
- **How to apply:** Make state access reliable and idempotent. Cap retries explicitly. Prefer "document the failure and continue / hand back to a human" over blind re-attempts. Bound agent loops (max iterations) to kill runaways. (Unmanaged runaways are real: one OpenClaw user spent **$1.3M in 30 days**; another burned **10B tokens in 8 months** on a $100/mo plan.)

### Lever 5 — Measurement & governance (the lever most often skipped)
- **What:** Instrument consumption *and* outcomes from day one; make cost visible at the point of the decision that drives it.
- **Evidence:** Uber exhausted its **full annual AI budget by mid-April** — *"nobody evaluated effectiveness before consumption went parabolic."* **Fewer than a third of organizations** (Deloitte 2025) can attribute AI spend to measurable business outcomes. **The measurement failure precedes the cost failure.**
- **How to apply:** Track **value per 1,000 tokens**, not raw token count. Measure outcomes (tasks completed, tickets resolved). Watch for *inverted economics* — outcomes flat/declining while consumption climbs. Surface cost (or a usable proxy) where a user picks a mode/strategy, so the choice is data-informed. Model expected cost *before* running, especially for autonomous/unattended runs.

### Lever 6 — RAG vs. long-context (a volume decision, not a dogma)
- Low-volume / internal: a full RAG pipeline can cost more than just sending the context directly (embeddings 3–8% of spend, vector DB 5–12%, data cleaning **30–50% of RAG project cost**, re-indexing ~20%/mo).
- High-volume / user-facing: retrieving a few thousand relevant tokens beats reprocessing a million-token window per query — on both cost and latency.
- The agentic analog: **just-in-time file/context reads (retrieval)** usually beat **loading everything up front (long context)** once a workflow has many steps.

---

## 3. Quick-reference audit rubric

Use this to grade any agentic system or agent/prompt design. Score each dimension; the weakest are usually Lever 5 (governance) and unbounded growth.

| # | Dimension | Look for (good) | Red flags (bad) |
|---|-----------|-----------------|-----------------|
| 1 | **Re-sent context** | State persisted externally; only compact summaries flow between steps | Full history/state re-sent every call; shared context re-loaded per step |
| 2 | **Prompt caching** | Static prefixes; variables appended last; frequently-called agents kept static | Timestamps / IDs / dynamic tool lists in the cacheable prefix |
| 3 | **Context size / rot** | Small per-agent contexts; JIT retrieval; bounded summaries (~1–2K tokens) | Monolithic context; append-only logs read in full; 20–30+ turn threads |
| 4 | **Tool surface** | Least-privilege, tiered tools per agent | One flat agent carrying all tool schemas |
| 5 | **Model routing** | Cheapest-capable model + effort per role | Premium model for everything, including trivial steps |
| 6 | **Retry / runaway control** | Explicit retry caps; loop bounds; "document & continue" | Blind retries re-sending context; no iteration ceiling |
| 7 | **Measurement / governance** | Consumption + outcome tracking; cost visible at decision points; pre-run cost modeling | No token/cost visibility; mode tradeoffs stated only qualitatively |
| 8 | **Output discipline** | Summaries size-targeted; verbatim payloads curated/compressed | Unbounded verbatim aggregation; growing handoffs |

---

## 4. One-line summary

> Most agentic cost is *overhead* — re-sent context, oversized windows, premium models on cheap work, and retries — and most cost *failures* are really **measurement** failures. Cache aggressively, keep contexts small and isolated, route models by role, cap retries, and instrument consumption against outcomes before you scale.

---

*Source: CockroachLabs, "The hidden economics of agentic AI: managing costs at scale." Figures (Stanford 62%, Chroma context-rot, Gartner 5–30×/40%-cancellation, Deloitte attribution, and the $40K→$24K / $12K→$68K / $1.3M case studies) are quoted from that article. Generated 2026-06-17.*
