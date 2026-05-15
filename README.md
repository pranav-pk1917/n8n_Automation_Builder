# SEO-Tools

Webley Media's multi-tenant SEO + GEO keyword research and content automation platform.

Status: **Phase 1 (Keyword Cleaning + Clustering Pipeline)** — under active development.

## What this is

A scalable, multi-tenant pipeline for cleaning, classifying, and clustering keyword research data across many agency clients, with bidirectional AI x human verification. Each new client onboards via a website crawl + structured questionnaire; the system auto-derives their service taxonomy and validates it against multiple evidence sources before activating.

## High-level architecture

- **Orchestration:** n8n (workflows exported to `n8n-workflows/exports/`)
- **Data layer:** Supabase (Postgres + pgvector + RLS) — a separate project from any client-facing site DB
- **LLM gateway:** OpenRouter (unified `/chat/completions` + `/embeddings` API). Model selection is dynamic via env vars (`DEFAULT_EMBEDDING_MODEL`, `DEFAULT_LLM_MODEL`, `DEFAULT_CROSS_VALIDATION_MODEL`) — defaults to `openai/text-embedding-3-small` @ 768 dim, `google/gemini-2.0-flash-001`, and `openai/gpt-4o-mini` for cross-validation. Swap any of them by editing one line in `.env`. See [ADR 0005](docs/adr/0005-openrouter-unified-gateway.md).
- **Clustering:** HDBSCAN via a small Python FastAPI worker (`python-worker/`)
- **HITL:** Slack + Telegram (multi-channel, configurable per client)
- **Intern view:** Read-only Google Sheet, auto-synced

See `docs/architecture.md` for the full v3 plan.

## Setting up Phase 1 (for the intern / first-time setup)

If you are setting this project up from scratch on a new machine or for a new client:

1. Follow [`docs/MANUAL-SETUP-GUIDE.md`](docs/MANUAL-SETUP-GUIDE.md) end-to-end. It is a checkbox-driven, intern-friendly walkthrough of every external account, key, and service you need (Supabase, Gemini, SerpAPI, Slack, Telegram, Railway, n8n, Cloudflare tunnel, Google Sheets, WPGraphQL).
2. Fill in [`docs/HANDOFF-TEMPLATE.md`](docs/HANDOFF-TEMPLATE.md) as you go — it tells you exactly where each secret belongs (`.env` vs n8n credentials) and tracks which connectivity tests you have verified.
3. When the handoff template's "Ready to resume" row is **Y**, paste the resume prompt at the bottom of the handoff doc into the Cursor chat. The build agent picks up from there and starts assembling the n8n workflows.

The "Getting started" section below is the condensed version for someone who already has everything provisioned.

## Layout

```
SEO-Tools/
  docs/              <- architecture, ROADMAP, ADRs, API contracts
  supabase/          <- versioned migrations + Postgres functions + RLS policies + seed data
  python-worker/     <- FastAPI clustering microservice (Dockerized)
  n8n-workflows/     <- version-controlled JSON exports + import instructions
  prompts/           <- LLM prompts (markdown, versioned for diff-able prompt changes)
  scripts/           <- one-off utilities + legacy PowerShell scripts kept for reference
  tests/             <- fixtures + e2e smoke tests
```

## Getting started (when Phase 1 ships)

1. Spin up a new Supabase project (NOT the one used by any client-facing site).
2. Run `supabase/migrations/*.sql` in order.
3. Deploy `python-worker/` to Cloud Run or Railway.
4. Import `n8n-workflows/exports/*.json` into your n8n instance.
5. Configure credentials per `n8n-workflows/credentials.example.md`.
6. Copy `.env.example` to `.env` and fill in keys.
7. Run WF-ONBOARD on Webley first to validate the onboarding flow.

## Future / improvements

See `docs/ROADMAP.md` for Phase 2+ work and deferred ideas.

## Conventions

- Every architectural decision worth remembering goes into `docs/adr/` as a numbered Architecture Decision Record.
- LLM prompts are markdown files with frontmatter (model, temperature, max_tokens, version). Prompt changes are PR-reviewed.
- Supabase migrations are forward-only and numbered. Never edit a shipped migration; write a new one.
- n8n workflows are exported as JSON after every meaningful change and committed to `n8n-workflows/exports/`.

## License

Private — Webley Media internal tooling.
