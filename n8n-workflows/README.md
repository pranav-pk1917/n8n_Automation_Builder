# n8n workflows

Version-controlled JSON exports of every n8n workflow that powers the pipeline.

> The actual workflows live in your n8n instance. This folder is the source of truth for **what they should look like**, so a new n8n instance (or a fresh agency setup) can re-import them from git.

## Workflows

| File | Workflow | Trigger | Purpose |
|---|---|---|---|
| `exports/wf-onboard.json` | WF-ONBOARD | Webhook (`POST /onboard`) or manual | New client onboarding: crawl + LLM site analysis + intern questionnaire + AI cross-validation + writes clients/niches/competitor_brand_names. |
| `exports/wf-00-page-inventory.json` | WF-00 | Cron daily | Per-client page inventory: crawl sitemap + WPGraphQL + Next.js app router parse. Upserts `pages`. |
| `exports/wf-01-ingest.json` | WF-01 | Webhook (`POST /ingest`) or manual | CSV ingest from local merged CSV. Normalize + dedupe + graveyard cache check. Bulk insert into `raw_keywords`. |
| `exports/wf-02-tiered-filter.json` | WF-02 | Trigger (after WF-01) or manual | Tier 0a regex -> Tier 0b competitor-navigational -> Tier 1 embeddings -> Tier 2 LLM. HITL routing by `clients.config.review_tier`. |
| `exports/wf-03-cluster.json` | WF-03 | Trigger (after WF-02) | Calls Python worker -> HDBSCAN. Persists clusters + role-tagged members. LLM theme labels + pillar/niche assignment. Cannibalization check vs `pages`. |
| `exports/wf-04-icp-score.json` | WF-04 | Trigger (after WF-03) | SerpAPI top-3 per surviving cluster (budget-capped). LLM ICP scoring. Computes `priority_score`. |
| `exports/wf-05-sheet-sync.json` | WF-05 | Cron daily | Writes per-client multi-tab Google Sheet (pillars + niches + themes + audit + cost + taxonomy-suggestions). |
| `exports/wf-hitl-dispatcher.json` | WF-HITL-DISPATCHER | Webhook (HITL response) | Receives Slack/Telegram interactive responses; updates `human_reviews` + `keyword_classifications`; triggers AI second-pass via cross-validation engine. |
| `exports/wf-quality-audit.json` | WF-QUALITY-AUDIT | Cron nightly | Samples 5-10% of AI-approved keywords into `quality_audits`; computes rolling 30-day agreement rate; alerts on drift. |
| `exports/wf-cross-validation.json` | WF-CROSS-VALIDATION | Trigger (after human override) | AI second-pass on every human override; logs to `cross_validation_events`; escalates to senior reviewer when both AI and human contradict. |
| `exports/wf-cost-ceiling-guard.json` | WF-COST-CEILING-GUARD | Subprocess (called from WF-02 / WF-03 / WF-04 before expensive batches) | Calls `check_cost_ceiling` Postgres function; pauses run + alerts if breach predicted. |

## Importing into n8n

1. In n8n: **Workflows -> Import from File**.
2. Pick a JSON from `exports/`.
3. Reconnect credentials per `credentials.example.md`.
4. Activate.

## Exporting after changes

When you edit a workflow in the n8n UI:

1. Open the workflow.
2. **Workflow menu -> Download** to get the JSON.
3. Save it to `exports/<wf-name>.json` (replacing the prior version).
4. Commit the change.

## Naming conventions

- File: `wf-<short-name>.json` (kebab-case).
- Node names inside the workflow: descriptive verbs (`Verify_Payload`, `HubSpot_Upsert_Lead`). Never the default `HTTP Request` / `Function` names.
- Sticky notes: every workflow has a top sticky describing what it does, its trigger, its outputs, and which other workflows depend on it.

## Inter-workflow communication

Workflows communicate via:
- **Database state.** WF-01 inserts into `raw_keywords` and a `pipeline_runs` row with `kind='filter'`; WF-02 picks it up via a Supabase trigger or a polling cron.
- **n8n's "Execute Workflow" node** for synchronous handoffs (e.g., WF-03 calls WF-COST-CEILING-GUARD before each expensive batch).
- **Webhooks** for HITL responses (Slack / Telegram POST to `WF-HITL-DISPATCHER`).

No workflow assumes another is "currently running" — each one re-queries state. This makes them idempotent and recoverable after a pause/restart.

## Building the workflows

Phase 1 workflows are built progressively using the `n8n-mcp-official` MCP server. See `docs/architecture.md` for the per-workflow specification. The MCP-based build process:

1. Search nodes / templates via the MCP.
2. Get node schemas with `get_node()`.
3. Build the workflow programmatically using `n8n_create_workflow`.
4. Validate using `validate_workflow`.
5. Test in n8n.
6. Export JSON to `exports/`.
7. Commit.
