# ADR 0002 — Bidirectional AI x human verification engine

Status: **Accepted** (Phase 1 build)

Date: 2026-05-14

## Context

This pipeline will be operated by a mix of senior team members and interns. The user (Webley Media) flagged a concrete risk: "one wrong decision can cost us a lot of money," and explicitly asked for a system where AI catches human mistakes AND humans catch AI mistakes — not just the conventional one-direction HITL (human approves AI).

Conventional HITL is unidirectional: AI proposes, human approves/rejects. This catches AI errors but does nothing about human errors — and humans (especially interns under deadline pressure) make confident errors all the time.

## Decision

Adopt a **bidirectional verification engine** as a first-class system component. Both directions of decision are cross-checked by the other side. Every cross-validation event is logged with severity and resolution status.

### Triggers and behaviors

| Trigger | What happens | Severity |
|---|---|---|
| Human overrides an AI keyword decision | AI re-runs classification with extra evidence (3 nearest gold examples + 3 nearest past decisions). If AI still disagrees, escalate to senior reviewer queue. | High if AI's original confidence > 0.85 (a confident AI overruled by a human is worth scrutiny). |
| AI auto-decides a "high-stakes" item (new pillar suggestion, new niche, cluster with cannibalization risk) | Auto-queued for human review even in `tier_a_ai_only` clients. | Medium by default; high if it touches `clients.config.service_pillars`. |
| Intern adds new `gold_example` | AI re-classifies a sample of 20 nearby keywords using the new gold example. If any flip pass<->reject, alert. | Medium. Catches "intern added a bad gold example that broke previously-correct classifications." |
| Onboarding questionnaire answer contradicts website crawl evidence | Flag for human acknowledgment before saving config. | High if pillar mismatch; medium otherwise. |
| Random 5-10% sample of AI decisions selected for spot-check (quality audit) | Human rates; agreement rate tracked over 30 days. | N/A — statistical signal. |
| AI-human agreement rate drops below 85% (30-day rolling) | Alert. Below 70%, auto-pause Tier 1/Tier 2 auto-approval until resolved. | High. |
| Per-run cost ceiling exceeded | Pause pipeline; alert; await human approve/extend/abort. | High. |

### What this protects against

- Intern picks wrong pillar at onboarding -> caught by AI cross-validation (steps 4 + 6 of WF-ONBOARD).
- Intern over-approves in HITL -> caught by AI second-pass; high-severity events surface in Audit tab.
- AI hallucinates a pillar/niche -> caught by human review of `taxonomy_suggestions`.
- Gold example pollution -> caught by re-validation sample on every new gold example.
- Prompt drift (someone tweaked the LLM prompt and decisions changed silently) -> caught by `llm_prompt_hash` + quality_audits rolling agreement.
- Runaway API costs from a buggy loop -> caught by cost ceiling auto-pause.

## Schema impact

- New table `cross_validation_events` (id, client_id, subject_type, subject_id, event_type, actor, decision_before, decision_after, agreement, evidence, severity, resolved, created_at).
- New table `quality_audits` (random-sample agreement tracking).
- New columns on `keyword_classifications`: `decision_reasoning`, `confidence`, `llm_prompt_hash`, `human_override`, `ai_second_pass_agrees`.
- `pipeline_runs.status` enum extended with `paused_cost_ceiling`, `paused_quality_drift`.

## Consequences

### Positive

- **Intern-safe.** Confident wrong decisions get caught.
- **AI-quality-safe.** Drift in LLM behavior or gold-example quality is detected statistically.
- **Auditable.** Every disagreement has evidence and resolution.
- **Tunable per client.** Review tiers (A-D) determine how aggressively to trigger HITL; cross-validation engine runs at all tiers, but escalation paths differ.

### Negative

- **Extra LLM cost** for second-pass verifications (~$0.50 per 60k corpus, marginal).
- **More tables to manage** (cross_validation_events grows fast; partition + 90-day retention by default).
- **Risk of "AI vs human" deadlock** if a senior reviewer is unavailable. Mitigation: escalation chain in `clients.config.escalation_chain` with timeouts.

## Alternatives considered

### Alternative A: One-direction HITL (conventional)

Rejected per user requirement.

### Alternative B: Two humans review each decision (no AI second-pass)

Rejected. Scales linearly in human time; defeats automation purpose. Two-human review only triggers on escalations.

### Alternative C: Track agreement but no auto-pause

Rejected. The point of auto-pause is to prevent damage at scale. Alerts without action don't stop runaway cost or drift.

## References

- v3 architecture: `../architecture.md` section 4
- Schema: `../../supabase/migrations/0001_initial_schema.sql` (cross_validation_events, quality_audits)
- Cost ceiling: [ADR 0003](./0003-cost-ceiling-auto-pause.md)
