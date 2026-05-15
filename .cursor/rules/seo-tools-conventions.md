# SEO-Tools conventions (Cursor rule)

When working inside `SEO-Tools/`, follow these conventions:

## Supabase

- Migrations are **forward-only and numbered**. Never edit a shipped migration; write a new one.
- All tables with client-scoped data have a `client_id` column and an RLS policy referencing `client_members`.
- Functions are `SECURITY INVOKER` unless they need to bypass RLS (then `SECURITY DEFINER`).
- Enums are named (not inline CHECK constraints).
- Index expression-on-column patterns; do NOT index expression-on-subquery (illegal in Postgres).

## Prompts

- Every prompt file has YAML frontmatter (id, version, provider, model, temperature, max_output_tokens, response_format).
- Placeholders use `{{double_braces}}`. n8n fills them in.
- LLM responses use **structured JSON output** (function calling). Never rely on plain-text parsing.
- When a prompt changes meaningfully, bump `version` in frontmatter. The `llm_prompt_hash` will change automatically.

## n8n workflows

- Functional node names (`Verify_Payload`, `HubSpot_Upsert_Lead`). Never default `HTTP Request` / `Function`.
- Every workflow has a top-of-canvas sticky note: purpose, trigger, outputs, dependent workflows.
- Workflows are exported to `n8n-workflows/exports/<wf-name>.json` after every meaningful change.
- Inter-workflow handoff happens via Supabase state, not in-memory chaining. Each workflow re-queries state on entry.

## Python worker

- Type-hinted. `from __future__ import annotations` at top of every module.
- Pydantic v2 models for all request/response shapes (`schemas.py`).
- Structured logging via `structlog` (JSON output).
- No business logic in `main.py` — endpoints delegate to module functions.
- Tests live in `tests/` with `test_*.py` naming.

## ADRs

- Number them sequentially: `0001-`, `0002-`, etc.
- Sections: Context, Decision, Reasoning, Consequences (positive/negative), Alternatives considered, References.
- One decision per ADR. If you need to update one, mark the old one Superseded and write a new one.

## Cost tracking

- Every API call (LLM, embedding, SerpAPI) MUST insert a row into `api_cost_log` with the actual cost.
- Cost guardrail (`check_cost_ceiling`) is called BEFORE every expensive batch, not after.
- Per-client `monthly_api_budget_usd` is set at onboarding and lockable; never bypass without explicit human approval.

## Cross-validation

- Every human override of an AI decision fires AI second-pass.
- Every high-stakes AI decision (new pillar/niche/cluster suggestion, cannibalization risk) queues for human review.
- Disagreements log to `cross_validation_events` with severity.

## Multi-tenancy

- Every new feature must consider: how does this behave for client A vs client B?
- `client_id` is a foreign key in every domain table. NOT optional.
- RLS policies must be tested with at least two clients before merge.
