# ADR 0003 — Per-run cost ceiling with auto-pause

Status: **Accepted** (Phase 1 build)

Date: 2026-05-14

## Context

LLM and SerpAPI providers price by usage. A buggy loop, a prompt change that inflates token counts, or a misconfigured client (very large CSV with no upstream filtering) could easily run a single pipeline 10x over expected cost.

For an agency operating on retainers, this risk is real and unbounded.

## Decision

Every pipeline run computes a hard cost ceiling at start time. Every API call increments a running total. Before each expensive batch, the system checks whether the next batch would breach the ceiling. If breach predicted, the pipeline pauses and awaits human decision.

### Formula

```
per_run_ceiling_usd = (clients.config.monthly_api_budget_usd / expected_runs_per_month)
                     * (per_run_cost_ceiling_pct / 100)
```

Defaults:
- `monthly_api_budget_usd = 50`
- `expected_runs_per_month = 4`
- `per_run_cost_ceiling_pct = 150`
- => per-run ceiling = $18.75

### Behavior on breach

1. Set `pipeline_runs.status = 'paused_cost_ceiling'`.
2. Fire **high-severity** HITL alert to all configured channels (Slack + Telegram). Payload includes: cost_so_far_usd, ceiling, remaining_work_estimate, top_5_cost_drivers (by `api_cost_log` group-by).
3. Wait for human decision: `approve_continue` / `extend_ceiling_by` / `abort_run`.
4. Log to `cross_validation_events` with `event_type = cost_ceiling_hit`.

### Where the check fires

- Before Tier 1 embedding batch (predicted cost: keyword_count * avg_tokens * embedding_price).
- Before Tier 2 LLM batch (predicted cost: borderline_count * avg_tokens * classifier_price).
- Before SerpAPI cluster batch (predicted cost: cluster_count * per_query_price).
- Before ICP LLM scoring batch (predicted cost: cluster_count * avg_tokens * classifier_price).

Checks use *predicted* cost (not actual) to prevent the batch from starting if it would overshoot.

## Consequences

### Positive

- **Bounded downside risk** on every run, regardless of upstream data shape.
- **Visibility into cost drivers** in the alert payload — humans don't have to dig through `api_cost_log` to triage.
- **Per-client tunable** via `clients.config`. Premium retainer clients can have higher ceilings; experimental tenants get tight ceilings.
- **Forces explicit human decision** to continue an over-budget run. No silent overruns.

### Negative

- **Pipelines can stall** if no human is available to approve. Mitigation: notification redundancy (Slack + Telegram + optional email digest); per-client `escalation_chain` and SLA timer.
- **False positives** if predicted cost diverges from actual. Mitigation: predicted vs actual variance logged; tune prediction over time.

## Alternatives considered

### Alternative A: Alert without auto-pause

Rejected. The whole point is to prevent damage. Alerts without action allow the run to complete over-budget.

### Alternative B: Per-API-call check (after every call)

Rejected. Too granular; overhead per call. Pre-batch check is sufficient and cheaper.

### Alternative C: Global agency budget instead of per-client

Rejected. Multi-tenant requires per-client cost accountability. A global ceiling would let one runaway tenant exhaust the budget for everyone.

### Alternative D: Hard kill (no human option to extend)

Rejected. Sometimes you need to finish a run that's slightly over budget (e.g., end-of-month delivery). Human-approved extension is the right escape valve.

## References

- v3 architecture: `../architecture.md` section 6
- Schema: `pipeline_runs.cost_so_far_usd`, `pipeline_runs.cost_ceiling_usd`, `pipeline_runs.status` enum value `paused_cost_ceiling`
