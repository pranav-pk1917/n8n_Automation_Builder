# ADR 0001 — Three-axis taxonomy for keyword clusters

Status: **Accepted** (Phase 1 build)

Date: 2026-05-14

## Context

When building a keyword research pipeline that must scale across many agency clients in many industries, the question is how to label each cluster so that downstream systems (content production, internal linking, page mapping) can route correctly.

Initial design (v1) used a single axis: `intent_type`. Sheet tabs were keyed off this.

v2 introduced `service_pillar` as the primary axis, aligned to Webley's existing four `/services/*` URLs: `visibility`, `performance`, `creative`, `infrastructure`.

The user (Pranav, Webley Media) pushed back: pillars vary by client. A pharma client cares about compliance content that crosses multiple pillars. A clothing DTC client doesn't need compliance content at all. Forcing a single-axis taxonomy either over-fits Webley or loses information when applied to other clients.

## Decision

Adopt a **three-axis taxonomy** for every cluster:

| Axis | Definition | Source | Mutability |
|---|---|---|---|
| `service_pillar` | The client's actual service offering, anchored to a real landing-page URL the client sells from. | Per-client declared in `clients.config.service_pillars`, set during onboarding from website crawl + questionnaire. | Mostly stable. Adding a pillar requires building a new landing page first. |
| `vertical_niche` | The industry the searcher operates in (healthcare, pharma, fintech, SaaS, e-commerce, etc.). | Declared at onboarding via questionnaire; auto-extended via `taxonomy_suggestions` as data reveals new niches. | Mutable. Adding a niche is cheap (one row). |
| `content_theme` | The KIND of concern the keyword expresses (compliance, pricing, comparison, how-to, case-study, etc.). | Fully LLM-derived per cluster. | Fully dynamic. Stabilizes around ~50 themes over time. |

A cluster is a *cell* in the (pillar x niche x theme) cube. Example: "HIPAA-compliant patient app development for pharma startups" -> `{pillar: infrastructure, niche: pharma, theme: compliance}`.

## Consequences

### Positive

- **Per-client adaptability.** Webley's pillars don't constrain other clients. Each client has their own `service_pillars` list.
- **Niche dimension** captures industry-specific concerns without polluting the pillar axis.
- **Content_theme dimension** is data-driven and emergent; no upfront classification scheme needed.
- **Cell-based routing** to landing pages and case studies works naturally. The same `/services/infrastructure` page surfaces different case studies based on niche.
- **Live discovery** of niches and themes via `taxonomy_suggestions` lets the system grow organically without intern intervention until human approval is needed.

### Negative

- **More columns** on the `clusters` table (3 axis assignments + 2 confidence scores + 1 cannibalization flag = 6 new columns).
- **More LLM tokens per cluster** to extract all three labels (~$0.005 per cluster, ~$1 per 200 clusters; acceptable).
- **More complex routing logic** in WF-03 (auto-assign vs propose-to-human vs suggest-new-pillar based on confidence thresholds per axis).
- **Cross-client comparison** is harder (each client has its own pillar/niche namespace). But Phase 1 is single-client by design; cross-client benchmarking is a Phase 4 feature.

## Alternatives considered

### Alternative A: Single axis (intent_type)

Rejected. Doesn't distinguish "buy app development" from "what is app development" — both could be `commercial_investigation` but route to entirely different content.

### Alternative B: Single axis (service_pillar, no niche, no theme)

Rejected after user pushback. Over-fits Webley's structure; doesn't scale to non-agency or differently-structured clients.

### Alternative C: Two axes (pillar x niche, no theme)

Considered but rejected. The "kind of concern" within a (pillar, niche) cell is critical for choosing the content template in Phase 2. Without `content_theme`, Phase 2 would have to re-extract it from cluster keywords every time — wasteful and inconsistent.

### Alternative D: Fully data-driven (no declared pillars at all)

Rejected. Pillars must anchor to real landing-page URLs the client sells from. If the data surfaces a "pillar" the client doesn't service (e.g., 60% of pharma keywords are about regulatory submissions and Webley doesn't do that), the right move is to decline or refer that work — not to bend the taxonomy to fit data noise. Pillars are a business decision, not a data decision.

### Alternative E: Hierarchical taxonomy (pillar > sub-pillar > leaf)

Considered for Phase 2. Phase 1 keeps it flat; hierarchy can be added without schema change if needed (via `parent_id` on a unified `taxonomy` table). Not worth the complexity now.

## References

- v3 architecture: `../architecture.md`
- Schema details: `../../supabase/migrations/0001_initial_schema.sql`
