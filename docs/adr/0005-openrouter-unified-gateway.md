# ADR 0005 — OpenRouter as the unified LLM gateway with dynamic model selection

Status: **Accepted** (Phase 1 build)

Date: 2026-05-14

## Context

Phase 1 of SEO-Tools needs two distinct kinds of LLM call:

1. **Text embeddings** (Tier 1 similarity filter, gold-example centroids, page embeddings) — high volume, ~60K embeddings per pipeline run.
2. **Chat completions** with structured JSON output — Tier 2 classifier, cluster theme labeler, pillar/niche assigner, ICP scorer, onboarding site analyzer, questionnaire validator, competitor brand NER, and the cross-validation second-pass reclassifier.

The initial design (pre-ADR-0005) hard-coded both to Google Gemini — `gemini-embedding-001` for embeddings and `gemini-2.0-flash` for chat. That choice had three concrete problems:

1. **Model deprecation churn.** `text-embedding-004` was deprecated and replaced by `gemini-embedding-001` mid-2025; the same will keep happening every 6-12 months. Each deprecation forced edits in [.env.example](../../.env.example), every prompt file's frontmatter, [architecture.md](../architecture.md), [credentials.example.md](../../n8n-workflows/credentials.example.md), and the manual setup guide — a coupling we want to eliminate.
2. **Same-family cross-validation is weak.** [ADR 0002](./0002-bidirectional-verification.md) uses "AI second-pass agrees" as a quality audit signal. If both passes are Gemini, they share training biases and agreement is meaningless. We need pass-1 and pass-2 to be from different model families, ideally cheaply.
3. **Multi-provider integration explodes credential count.** Adding OpenAI as a second provider would mean a second API key, a second n8n credential, a second cost-tracking source, and a second deprecation timeline to follow.

As of May 2026, OpenRouter exposes both chat completions AND embedding models behind a single OpenAI-compatible API surface (embeddings support was added in 2026; before that, OpenRouter only proxied chat models, which would have ruled it out). This changes the calculus.

## Decision

Adopt **OpenRouter** as the single LLM gateway for SEO-Tools, with **role-based dynamic model selection** wired through environment variables.

### The contract

1. There is exactly **one outbound LLM credential** in n8n: `OpenRouter_SEOTools` (HTTP Header Auth, `Authorization: Bearer $OPENROUTER_API_KEY`).
2. Active model selection lives in [.env](../../.env.example) as a small set of env vars:
   - `DEFAULT_EMBEDDING_MODEL` — OpenRouter slug for embedding (default `openai/text-embedding-3-small`)
   - `DEFAULT_EMBEDDING_DIMS` — dimensions requested from the embedding endpoint (default `768`, matches our `vector(768)` schema)
   - `DEFAULT_LLM_MODEL` — primary chat model (default `google/gemini-2.0-flash-001`)
   - `DEFAULT_CROSS_VALIDATION_MODEL` — second-pass model, deliberately a different family (default `openai/gpt-4o-mini`)
3. Prompt frontmatter declares a **role**, not a concrete model:
   ```yaml
   provider: openrouter
   role: llm                # or: cross_validation
   ```
   At run time n8n maps `role` -> the matching `DEFAULT_*_MODEL` env var and passes that slug as the `model` field of the OpenRouter request.
4. The Python clustering worker never calls an LLM; this ADR does not affect [python-worker/](../../python-worker/).

### Default models, May 2026

| Role | OpenRouter slug | Why this default |
|---|---|---|
| Embedding | `openai/text-embedding-3-small` @ 768 dim | Stable, well-versioned by OpenAI, accepts `dimensions` parameter so we keep `vector(768)` schema. $0.02/M tokens. |
| Primary LLM | `google/gemini-2.0-flash-001` | Cheap, fast, supports structured JSON output, large context window. ~$0.10-0.30 per pipeline run. |
| Cross-validation | `openai/gpt-4o-mini` | Different model family from the primary, so disagreement is a real signal not just same-bias agreement. Marginally more expensive but only invoked on overrides, not every keyword. |

## Reasoning

### Why a gateway at all

The user-stated concern was "models keep changing and the older models are removed over time." OpenRouter solves this directly: the gateway tracks deprecation across providers and we only have to track *its* slug catalog (https://openrouter.ai/models), not three separate provider deprecation timelines. When `openai/text-embedding-3-small` is retired and replaced by `openai/text-embedding-4-small`, the migration is one line in `.env`.

### Why dynamic env-var selection vs hard-coded model in frontmatter

If model names live in the 8 prompt files, the [architecture.md](../architecture.md), the [credentials.example.md](../../n8n-workflows/credentials.example.md), and the manual setup guide, every model swap is an 8-12 file edit. With role-based env-var selection, every swap is one line in `.env`. The trade-off — slightly less explicit per-prompt control — is acceptable because prompts at this scale don't need per-prompt model tuning; they need a stable "primary LLM" and "second-pass LLM" abstraction.

### Why three roles, not one or five

- One role (`llm` for everything) would prevent the cross-family second-pass design from working.
- Five+ roles (per-prompt role like `llm_classifier`, `llm_theme_labeler`, etc.) would add operational complexity without buying anything in Phase 1, since all chat prompts use similar capabilities (structured JSON, similar context window, similar temperature).
- Three roles — primary chat (`llm`), cross-validation (`cross_validation`), embedding (`embedding`) — cover the actual functional needs and keep `.env` short.

We can split a role later if a specific prompt grows special needs (e.g., a long-context onboarding analyzer might warrant `llm_onboarding` with `DEFAULT_ONBOARDING_MODEL`). The role system is additive.

### Schema compatibility (no migration needed)

Both `openai/text-embedding-3-small` and `openai/text-embedding-3-large` accept a `dimensions` parameter in the embed request. We pass `dimensions: 768` and the API returns 768-dim vectors that fit our existing `vector(768)` schema from [0002_pgvector.sql](../../supabase/migrations/0002_pgvector.sql). The ivfflat indexes are dimension-agnostic at the schema level; only the data dimensionality matters. Migrating to a model that does NOT support `dimensions` (e.g. Gemini embeddings are fixed at 768 or 3072 depending on version; Qwen3-embedding-8B is 1024) would require either a schema migration or use of native-768 models. The May-2026 default avoids this.

### Cost transparency stays intact

The `api_cost_log` table records `provider`, `model`, `input_tokens`, `output_tokens`, `usd_cost`. With OpenRouter:
- `provider` = `'openrouter'`
- `model` = the resolved OpenRouter slug (e.g. `'openai/text-embedding-3-small'`)
- token counts come from OpenRouter's response, same fields as direct providers
- `usd_cost` comes from OpenRouter's response (it includes per-request cost in the response metadata)

Cost analytics can be sliced by underlying model even when models change, because the historical `model` column preserves the slug active at the time of each call.

### `llm_prompt_hash` interplay

The hash formula stays:
```
sha256(rendered_prompt_text || "::" || resolved_model_slug || "::" || temperature)
```

When `DEFAULT_LLM_MODEL` env var changes, the resolved slug changes, the hash changes, and `cross_validation_events` / `quality_audits` can detect that "agreement rate dropped after the model swap on 2026-09-15". This is exactly the audit signal we want.

## Consequences

### Positive

- **One credential, one billing dashboard.** Replaces what would otherwise be 2+ separate provider accounts.
- **Model swaps are one-line operations.** Edit `.env`, restart n8n, done. No prompt edits, no workflow JSON edits.
- **Cross-family second-pass becomes trivial.** Primary on Gemini, cross-validation on GPT, no extra integration cost.
- **Future BYOK is easy.** Phase 2's per-client `openrouter_api_key` slots into `clients.config` without touching the gateway logic.
- **Documentation stays terse.** Setup guide Section 5 has 5 click steps + 2 verify curls instead of separate Gemini and OpenAI sections.

### Negative

- **Embedding model swaps are NOT free.** Once we have 60K keywords embedded with `openai/text-embedding-3-small`, switching to `qwen/qwen3-embedding-8b` means those stored vectors are in incompatible latent spaces — similarity scores across them are garbage. **An embedding-model swap requires re-embedding all prior data.** Operationally: a new `pipeline_run` of `kind = 'reembed'` walks every `raw_keywords` row, embeds it with the new model, overwrites the `keyword_classifications.embedding` and `gold_examples.embedding` columns, and invalidates any cached similarity scores. Same applies to `pages.embedding`. This is going to live in `scripts/one-off/reembed_with_new_model.py` whenever we first swap.
- **Chat-model swaps invalidate audit cohorts.** Not destructive, but `llm_prompt_hash` changes, so quality-audit agreement-rate comparisons across the swap point are not apples-to-apples. The fix is to treat pre-swap and post-swap classifications as separate cohorts in audits.
- **Single point of failure.** If OpenRouter has an outage, every LLM call fails. In practice their uptime is high and acceptable for an internal agency tool, but for a future SaaS we may want a secondary direct-provider credential as a manual failover.
- **Marginal latency overhead.** ~50-150 ms per call from the extra hop. Doesn't matter for batch operations or HITL cards.
- **Marginal markup.** OpenRouter generally passes through provider pricing at parity or with a small (~5%) markup. Negligible at Phase 1 scale.

### Operational runbook for model swaps

**To change the primary LLM** (cheap, safe):
1. Pick a new slug from https://openrouter.ai/models.
2. Run it against the verify curl in Section 5 of the setup guide to confirm structured JSON support and reasonable latency.
3. Edit `.env`: change `DEFAULT_LLM_MODEL`.
4. Restart n8n (`docker compose restart n8n`).
5. Watch the next pipeline run's `quality_audits` agreement rate; expect a transient dip while the new model "learns" the prompts. Sustained drop > 5 percentage points means revert.

**To change the cross-validation LLM** (cheap, safe): same flow, edit `DEFAULT_CROSS_VALIDATION_MODEL`.

**To change the embedding model** (expensive, irreversible without re-embed):
1. Confirm the new model supports `dimensions: 768` OR plan a schema migration to a different vector dimension.
2. Schedule downtime — re-embedding 60K keywords per client takes 5-15 minutes plus full Tier 1 recompute.
3. Edit `.env`: change `DEFAULT_EMBEDDING_MODEL` (and `DEFAULT_EMBEDDING_DIMS` if needed).
4. Run `scripts/one-off/reembed_with_new_model.py` (does not exist yet — write when first needed).
5. Invalidate `v_gold_centroids` (it auto-recomputes on next read since it's a view).
6. Re-run Tier 1 filter for any in-flight `pipeline_runs`.
7. Commit the `.env` change AND tag the change in `cross_validation_events` with `event_type = 'embedding_model_swap'` for auditability.

## Alternatives considered

### Alternative A: stay on direct Gemini for everything

Rejected. The model-deprecation pain is real and recurring, the cross-family verification problem is unsolved, and the multi-vendor BYOK story for Phase 2 is worse.

### Alternative B: direct OpenAI for everything

Rejected. More expensive than Gemini Flash for chat ($0.15/M input vs $0.075/M for Flash). Same single-family weakness for cross-validation as Alternative A. Same deprecation churn.

### Alternative C: custom multi-provider abstraction layer in n8n

Build n8n Function nodes that dispatch to Gemini, OpenAI, Anthropic, etc. based on env vars.

Rejected. This is reinventing OpenRouter, badly. We'd have to maintain provider-specific request/response shape handling, our own deprecation tracker, and our own cost reconciliation. OpenRouter already does all of this.

### Alternative D: Vercel AI SDK as the abstraction

Rejected for the orchestration layer. Vercel AI SDK is excellent for TypeScript app code (it's used by the Next.js site), but our orchestration runs in n8n which talks HTTP. Adding a JS runtime in n8n Function nodes to host the AI SDK just to get provider abstraction is heavier than calling OpenRouter directly via HTTP.

### Alternative E: self-hosted LLM gateway (LiteLLM, etc.)

Rejected for Phase 1. LiteLLM is a good open-source alternative if Phase 4 finds we need self-hosting for cost or compliance reasons. For now the Phase 1 priority is to get the pipeline running; a managed gateway minimizes ops surface.

## References

- [docs/architecture.md](../architecture.md) — tech stack section
- [SEO-Tools/.env.example](../../.env.example) — the env-var contract
- [SEO-Tools/prompts/README.md](../../prompts/README.md) — `role` -> env-var mapping table
- [SEO-Tools/n8n-workflows/credentials.example.md](../../n8n-workflows/credentials.example.md) — `OpenRouter_SEOTools` credential setup
- [docs/MANUAL-SETUP-GUIDE.md](../MANUAL-SETUP-GUIDE.md) Section 5 — intern-facing API key creation walkthrough
- [docs/adr/0002-bidirectional-verification.md](./0002-bidirectional-verification.md) — the cross-family second-pass design that depends on this decision
- OpenRouter models catalog: https://openrouter.ai/models
- OpenRouter embeddings docs: https://openrouter.ai/docs/api/api-reference/embeddings/create-embeddings
