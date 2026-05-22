# Phase 2 Update Spec — SEO-Tools n8n Workflow Optimizations

**Version:** 2.2 (delta-spec framing + already-built reconciliation)
**Date:** 2026-05-22
**Base:** Opus 4.7 High Reasoning consensus synthesis (4 independent audits × 7 workflows)
**Status of this document:** This is **not** a build-from-scratch PRD. It is a **delta over the existing Phase 1 build** in [SEO-Tools/n8n-workflows](../..) and [SEO-Tools/supabase](../../../supabase). It enumerates the shortcomings the current 7-workflow pipeline has at production scale, the fixes for each, and the schema/infra changes those fixes assume. When this document and the live n8n editor disagree, **the live editor wins** — exports come second, this spec third.
**Audit pass:** Every retained claim verified against the actual JSON in [SEO-Tools/n8n-workflows/exports/](../../exports), [SEO-Tools/n8n-workflows/sdk/wf-onboard.ts](../../sdk/wf-onboard.ts), and [SEO-Tools/supabase/migrations/](../../../supabase/migrations). Three single-model claims removed as hallucinations (see §0). Second accuracy pass corrected one critical table-name error and two overstated claims. Version 2.2 adds §0.1 already-built inventory, §0.2 open decisions, §0.3 wave→asset map.
**Conflict resolution priority:** Scalability > Maintainability > Execution Speed.

---

## 0. Audit Reconciliation

This section anchors the spec to what already exists, what is intentionally excluded, what is deferred to its own wave, and which existing assets each wave consumes.

### 0.0 Items removed from the draft as hallucinations

The following claims from the draft were verified as **false** against the live JSON / live database and must NOT be acted on:

| Draft item | Claim | Reality |
|---|---|---|
| Opus 04-4 | "`encodeURIComponent` is not exposed in n8n's expression engine; the SerpAPI URL becomes `undefined`." | False. `encodeURIComponent` is a standard JS global available inside n8n `{{ ... }}` expressions. The current usage in `SerpAPI_Search.url` works. |
| Opus 04-10 | "SerpAPI cost not logged." | False. `Log_ICP_Costs` already POSTs a `provider: 'serpapi'` row with `usd_cost` in [wf-04-icp-score.json](../../exports/wf-04-icp-score.json). |
| Opus O11 | "`Build_DB_Writes` ignores `monthly_api_budget_usd` and `navigational_competitor_strategy`, uses hardcoded defaults." | False. The node reads `q.monthly_api_budget_usd \|\| 50` and `q.navigational_competitor_strategy` from the parsed questionnaire. The numeric `50` is a fallback, not an override. |

### 0.1 Already-built inventory (do not recreate)

Verified against [SEO-Tools/supabase/migrations/0001_initial_schema.sql](../../../supabase/migrations/0001_initial_schema.sql) (+ `0002_pgvector.sql`, `0003_rls_policies.sql`, `0004_indexes.sql`), [SEO-Tools/supabase/functions/](../../../supabase/functions), [SEO-Tools/n8n-workflows/exports/](../../exports), [SEO-Tools/n8n-workflows/sdk/wf-onboard.ts](../../sdk/wf-onboard.ts), and the live Supabase instance.

**Tables that exist (and the columns this spec assumes):**

| Table | Notable columns already present |
|---|---|
| `clients` | `id`, `canonical_domain`, `onboarding_status`, `config` jsonb (used for `service_pillars`, `gold_examples`, `monthly_api_budget_usd`, `hitl_channels`, etc.) |
| `niches` | `id`, `client_id`, `name`, `source` |
| `pipeline_runs` | `id`, `client_id`, `kind`, `status`, `started_at`, `finished_at`, `cost_so_far_usd`, `cost_ceiling_usd`, `input_summary`, `output_summary` |
| `raw_keywords` | `id`, `client_id`, `pipeline_run_id`, `keyword`, `volume`, `kd`, ... |
| `keyword_classifications` | `id`, `client_id`, `pipeline_run_id`, `status`, `decided_by`, `intent_type`, ... |
| `clusters` | **already has** `pipeline_run_id`, `total_volume`, `avg_kd`, `priority_score`, `cannibalization_risk_page_id`, `suggested_service_pillar`, `intent_type`, `keyword_count` |
| `keyword_cluster_map` | **already has** `keyword_classification_id`, `cluster_id`, `role`, `distance_from_centroid`; **missing** `client_id` and `pipeline_run_id` (added in Wave 1 via ALTER) |
| `pages` | `id`, `client_id`, `url_path`, `embedding` (vector(768) after `0002_pgvector`), `last_seen_at` |
| `api_cost_log`, `gold_examples`, `competitor_brand_names`, `taxonomy_suggestions`, `cross_validation_events`, `human_reviews`, `quality_audits` | All present per `0001_initial_schema.sql`. Several are under-used by current workflows — fixes below wire them up, not create them. |
| `negative_terms`, `positive_terms` | Present. Used by Tier 0 RPCs. |

**Postgres functions that exist (and the spec must call these by name):**

| Function | Defined in | Used by |
|---|---|---|
| `apply_tier0_regex_filter` | [SEO-Tools/supabase/functions/apply_tier0_regex_filter.sql](../../../supabase/functions/apply_tier0_regex_filter.sql) | WF-02 (intended) |
| `apply_tier0_competitor_navigational_filter` | [SEO-Tools/supabase/functions/apply_tier0_competitor_navigational_filter.sql](../../../supabase/functions/apply_tier0_competitor_navigational_filter.sql) | WF-02 (intended) |
| `check_cost_ceiling` | [SEO-Tools/supabase/functions/check_cost_ceiling.sql](../../../supabase/functions/check_cost_ceiling.sql) | WF-04 cost guard (see 04-6) |
| `compute_priority_score` | [SEO-Tools/supabase/functions/compute_priority_score.sql](../../../supabase/functions/compute_priority_score.sql) | WF-04 priority math (see 04-2) |

> **Note:** [WF-02.md](../../docs/WF-02.md) refers to RPCs named `apply_tier0_filters` and `tier1_embed_and_score` — **these do not exist**. The export `wf-02-tiered-filter.json` does the work in Code nodes instead. This is workflow drift, not a missing migration. Resolution lives in §0.2 below.

**Existing assets that are not yet in the workflow graph but already shipped in the repo:**

- SDK source [SEO-Tools/n8n-workflows/sdk/wf-onboard.ts](../../sdk/wf-onboard.ts) defines the fluent `@n8n/workflow-sdk` style used by all future SDK-deployed workflows (including `SYS-Error-Handler` in §3.1).
- Python clustering worker at [SEO-Tools/python-worker](../../../python-worker) (`POST /cluster`, bearer auth) — already called by WF-03's export.
- Prompts at [SEO-Tools/prompts/](../../../prompts) (`tier2-classifier.md`, `icp-scorer.md`, `onboarding-site-analyzer.md`, `cluster-theme-labeler.md`).
- The `human-written-blog` skill at [SEO-Tools/n8n-workflows/skills-to-add/skill/human-written-skill.md](../../skills-to-add/skill/human-written-skill.md) — selectively wired in Wave 6 (§7.1).

### 0.2 Open decisions deferred to their own wave

These are documented drifts between docs/exports/spec that this Wave 1 work explicitly does **not** decide. Each is owned by its wave; surfacing them here keeps Wave 1 unblocked and prevents the spec from implying a single answer.

| ID | Decision | Default this spec uses | Wave |
|---|---|---|---|
| OD-1 | **WF-02 source of truth.** [WF-02.md](../../docs/WF-02.md) references `apply_tier0_filters` + `tier1_embed_and_score` RPCs that do not exist; the export uses in-n8n `Tier0a_Regex_Filter` / `Tier0b_Competitor_Filter` / `Prepare_Tier1` / `Embed_Keywords_Batch` / `Score_Tier1` Code nodes. | Ratify the **in-n8n Code path** as canonical and call the **existing two Tier 0 functions** from §0.1. Rewrite WF-02.md to match. The non-existent `apply_tier0_filters` and `tier1_embed_and_score` RPCs are not created. | Wave 2 |
| OD-2 | **WF-04 priority formula.** Doc formula `(icp×0.35)+(commercial×0.25)+(volume_norm×0.20)+0.20` vs the multi-term formula stickied in the export. | Call the existing `compute_priority_score` Postgres function in PATCH path (single source of truth in SQL). Update both [WF-04.md](../../docs/WF-04.md) and the export sticky to mirror the function. | Wave 3 |
| OD-3 | **WF-05 sheet layout.** Doc says single `Clusters` tab; export builds multi-tab data but writes only `Cost`. | Per §4.4: lock to **`Clusters` + `Cost`** tabs only for this sprint. Per-pillar / Themes / Taxonomy tabs deferred. | Wave 3 |

### 0.3 Wave → existing-asset map

For each wave, which Phase-1 assets are reused (R) vs which new pieces are added (N).

| Wave | Existing assets reused (R) | New pieces added (N) |
|---|---|---|
| **Wave 1 — Foundations** | `pipeline_runs`, `clusters`, `keyword_cluster_map`, `raw_keywords` (R); the `@n8n/workflow-sdk` style of `wf-onboard.ts` (R); credential names from [credentials.example.md](../../credentials.example.md) (R). | `onboarding_sessions` table (N); `keyword_cluster_map.client_id` + `pipeline_run_id` columns (N); `clusters.worker_cluster_id` column (N); `raw_keywords` unique constraint on `(client_id, lower(keyword))` (N); `SYS-Error-Handler` workflow + bind on 7 workflows (N); 2 new env vars `SLACK_HITL_CHANNEL`, `SLACK_OPS_CHANNEL` (N). |
| **Wave 2 — Critical correctness** | `apply_tier0_regex_filter`, `apply_tier0_competitor_navigational_filter`, `keyword_classifications`, `keyword_cluster_map`, `clusters` (R); the 7 existing workflow IDs (R). | OD-1 resolved (rewrite WF-02.md, no new RPCs); Tier 1 classification writes wired in WF-02; `keyword_cluster_map` writes wired in WF-03; SplitInBatches loop-backs fixed in WF-00 / WF-ONBOARD; onboarding session re-hydration (uses Wave 1 table). |
| **Wave 3 — Scaling & resilience** | `compute_priority_score`, `check_cost_ceiling`, `api_cost_log`, `clusters` (R). | OD-2 + OD-3 resolved; universal LLM/pagination/respond patterns from §3.4-§3.6 applied to existing nodes; WF-04 full PATCH; WF-05 locked `Clusters` + `Cost` writers. |
| **Wave 4 — Polish & idempotency** | All Phase-1 tables (R). | Idempotency markers across writers, the smaller per-workflow polish items in §5. |
| **Wave 5 — Validation** | All seven workflows end-to-end (R). | No new code — chaos test, smoke tests, error-handler verification. |
| **Wave 6 — Voice & content-skill** | `human-written-blog` skill markdown (R); existing prose-producing nodes in WF-ONBOARD / WF-03 / WF-05 (R). | `system_prompts` table (N); `content_drafts` table (N); WF-06 scaffold (N). |

---

## 1. Executive Consensus Summary

The seven-workflow keyword pipeline (Onboard → 00 → 01 → 02 → 03 → 04 → 05) is **architecturally correct but operationally broken at production scale.** The *shape* of the assembly line is sound and should not be redesigned; what is broken is the wiring, idempotency, and persistence inside each station. The system today silently truncates data, double-writes the wrong rows, and reports success on partial runs — meaning every downstream metric (cluster quality, ICP scores, Slack digests) is computed on incomplete inputs.

**Verified critical defects (every one reproduced against the JSON):**

1. **`SplitInBatches` loop is mis-wired in WF-00 and WF-ONBOARD.** Neither workflow has a loop-back edge from the per-item processor back into the batch node. Result: only the first batch (10 pages and 5 pages respectively) is processed, then run-completion fires as if the entire client was synced.
2. **Webhook responses fire inside per-item loops** in WF-01, WF-02, WF-03, and WF-04. The first item's response wins; the caller is told "ok" before downstream work finishes.
3. **The `Range: 0-49999` cap is replicated across WF-01, WF-02, WF-03** with no pagination loop. Any client crossing 50k rows is silently truncated.
4. **`pipeline_run_id` traceability chain is incomplete.** Tier 1 classifications are never written at all (02-1), and `keyword_cluster_map` does not exist yet (03-1). `api_cost_log` in WF-00 has no embedding cost rows. Cross-workflow traceability is broken from WF-01 onward.
5. **There is no global error workflow.** Every JSON has `"errorWorkflow": ""`. Any uncaught exception leaves `pipeline_runs.status = 'running'` forever.
6. **WF-02 silently drops 60–80% of throughput.** Tier 1 `passed` and `rejected` decisions are computed in `Score_Tier1` but never written to `keyword_classifications` — only the `borderline` → Tier-2 path persists. This is the single highest-impact correctness bug in the pipeline.
7. **WF-03 writes cluster headers but no `keyword_cluster_map` rows.** WF-04 and WF-05 cannot reconstruct which keywords belong to which cluster.
8. **WF-ONBOARD chains three n8n webhook triggers as if they were Wait nodes.** Each webhook starts a new execution, so Phase B/C expressions referencing Phase A nodes evaluate to `undefined`. No durable session state exists to re-hydrate from.

**Headline recommendation:** Do not redesign any workflow. Execute the optimization sprint described in §2 as surgical fixes plus the shared architectural additions in §3.

---

## 2. Consolidated System Shortcomings & Fixes (Per Workflow)

### 2.1 WF-ONBOARD — Client Onboarding (Phases A/B/C)

| # | Core Issue | Technical Fix |
|---|---|---|
| O1 | Webhook trigger nodes used as wait/resume points. Each `wf-onboard-*` webhook starts a fresh execution; Phase B/C expressions reading Phase A nodes resolve to `undefined`. | Keep three webhooks but persist all Phase A context to a new `onboarding_sessions` table keyed by `pipeline_run_id` (see §3.2). Phase B and Phase C must begin with `Fetch_Onboarding_Session` (GET on the session row) and reference only fields from that fetched row — never `$('<PhaseA_Node>').first()`. |
| O2 | No `onboarding_sessions` table; Phase A crawl results and LLM site analysis exist only in Phase A's execution log. | Create `onboarding_sessions` (schema in §3.2). After `Aggregate_Page_Data` and `LLM_Site_Analysis`, write `crawled_pages`, `llm_site_analysis`, `competitors`, `seed_keywords`, `client_url`, `client_name`, `status='phase_a_complete'`. |
| O3 | `SplitInBatches_Pages` is wired only from output 0 (`→ Crawl_Page`); no loop-back from `Extract_Page_Content` → `SplitInBatches_Pages`. Only the first batch crawls. | Confirm the loop branch goes to `Crawl_Page`, loop `Extract_Page_Content` → `SplitInBatches_Pages` input, and connect the done branch → `Aggregate_Page_Data`. Verify the SplitInBatches output indexing matches n8n v3 semantics in the test environment before merging. |
| O4 | Phase A returns 200 only after Slack card is posted (10+ seconds). Caller times out; retry creates a duplicate `pipeline_runs` row. | Move `Respond_OK` to fire immediately after `Create_Pipeline_Run` returning `{ pipeline_run_id }`. Use n8n's "Respond to Webhook: Immediately" mode; the rest of Phase A continues asynchronously. |
| O5 | Slack questionnaire posts `input` blocks inside `chat.postMessage`. Slack input blocks only render inside **modals**, not channel messages — fields are non-editable. | Replace `Send_Questionnaire_Card` with a Slack message containing an "Open Onboarding Form" button. Add new webhook `wf-onboard-modal-trigger` that handles the button click, fetches the session row, and calls Slack `views.open` with a modal pre-filled from `llm_site_analysis`. Modal submit_url → `wf-onboard-questionnaire-response`. Phase B parses `payload.view.state.values` and `payload.view.private_metadata.pipeline_run_id`. |
| O6 | `competitors[]`, `seed_keywords[]`, and `gold_examples` are received/built but never written to any Supabase table — no `Write_Competitor_Brand_Names` or `Write_Gold_Examples` node exists. | After `Write_Niches` add: (a) `Write_Competitor_Brand_Names` HTTP POST to `competitor_brand_names`, (b) `Write_Gold_Examples` HTTP POST to `gold_examples` with `source='onboarding_llm_seed'`, (c) update `Build_DB_Writes` so `clients.config.competitors`, `clients.config.seed_keywords`, and `clients.config.gold_examples` are also set (denormalized for WF-02 fast-read). |
| O7 | WF-02 requires `pos_centroid` / `neg_centroid` gold examples; onboarding never collects them. | Add two required modal sections: "5 keywords your ICP would search" (positive) and "5 keywords that look related but are not your ICP" (negative). Persist to `clients.config.gold_examples = { positive: [...], negative: [...] }`. |
| O8 | `Parse_Sitemap_XML` does not detect `<sitemapindex>` (WP default), does not dedupe, no fallback when sitemap is blocked. | (a) Detect `<sitemapindex>`; if present, emit child `<loc>` URLs, fetch each, parse, concat. (b) Strip query/fragments, dedupe with `[...new Set(locs)]`. (c) If sitemap returns 0 URLs, fall back to a static path list `['/', '/services', '/about', '/case-studies']`. |
| O9 | `Fetch_Sitemap` and `Crawl_Page` have no `continueOnFail`. Any 5xx aborts onboarding; `pipeline_runs.status = running` forever. | Set `options.continueOnFail = true` on both nodes. Route their error output to a `Log_Crawl_Error` Code node that writes a `pipeline_run_events` row, then loops back into the batch. |
| O10 | LLM calls (`LLM_Site_Analysis`, `LLM_CrossValidate`) have no retry on 429 and no JSON schema enforcement; one parse error halts Phase A. | (a) Enable node retry: 3 attempts, exponential backoff (2s/4s/8s). (b) Add `response_format: { type: 'json_object' }`. (c) Wrap JSON parse in try/catch; on failure write a fallback row with `status='parse_error'` and continue. |
| O12 | Client slug collision: `slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-')` will unique-violate for two clients with similar names. | Before insert, GET `clients?slug=eq.<slug>&select=id`. If exists, append `-<random4>` until free. |
| O13 | `cross_validation_events` table promised in the sticky note but never written. | After `Parse_CrossVal_Response` add POST to `cross_validation_events` with `client_id`, `pipeline_run_id`, `validation_result`, `had_flags`, `summary`. Write **always**, even when no flags raised (audit completeness). |
| O14 | Idempotent re-onboarding: if a `clients` row with the same `canonical_domain` exists, Phase C inserts a duplicate. | In Phase C `Write_Client`, change to upsert: PATCH if `canonical_domain` matches; else INSERT. Use Supabase `Prefer: resolution=merge-duplicates` with `on_conflict=canonical_domain`. |

> Note: Draft item **O11** has been removed — see §0.

---

### 2.2 WF-00 — Page Inventory Sync

| # | Core Issue | Technical Fix |
|---|---|---|
| 00-1 | `Batch_Pages` SplitInBatches loop has no loop-back from `Upsert_Page` back to `Batch_Pages`. Only the first batch is processed; the rest are silently dropped. | Wire `Upsert_Page` → `Batch_Pages` (loop-back input). Wire the SplitInBatches done branch → new `Aggregate_Run` (Aggregate, mode "Combine") → `Complete_Run`. Delete the existing direct `Upsert_Page → Complete_Run` edge. Verify loop vs. done output indexing in the test environment. |
| 00-2 | `Complete_Run` fires per page rather than once per client. Run is marked completed on first page; later failures invisible. | Resolved by 00-1 (Complete_Run moves to done-branch of Batch_Pages). |
| 00-3 | `Fetch_Page_HTML` has no per-page fault tolerance. A single 404 or timeout aborts the whole client. | Set `options.continueOnFail = true`. Route error output to `Log_Page_Fetch_Error` Code node that POSTs `{ client_id, page_url, error, run_id }` to `pipeline_run_events` (or sets `pages.crawl_status = 'error'`), then loop back into `Batch_Pages`. |
| 00-4 | `Parse_Sitemap` does not handle sitemap-index files (`<sitemapindex>`) — WP default. Workflow sees zero URLs for any WP client. Also does not dedupe despite comment claiming so. | (a) Detect `<sitemapindex>`; emit child URLs; add `Fetch_Child_Sitemap` HTTP node + `Parse_Child_Sitemap` Code node. (b) Strip query/fragments. (c) `const uniqueLocs = [...new Set(locs)]`. |
| 00-5 | Hardcoded WPGraphQL URL `https://cms.webleymedia.com/graphql` for every client — every client's inventory polluted with Webley's blog. | Replace with `={{ $json.client_config?.wp_graphql_url \|\| $env.WP_GRAPHQL_URL }}`. Wrap `Fetch_WP_Posts` in an `IF` gate: skip when `wp_graphql_url` is null. |
| 00-6 | `Merge_Client_Run` cross-pollinates `pipeline_run_id` across clients because it reads `$('Split_Clients').item.json` after `Create_Run` HTTP POST. In multi-client execution, paired-item association is not guaranteed. | Replace the Code-based `Merge_Client_Run` with a proper `Merge` node (mode "Combine by position", inputs: `Split_Clients` and `Create_Run`). Recompute `pipeline_run_id` from the merged item, not via `$('Split_Clients').item.json`. |
| 00-7 | No idempotency. Every nightly run re-embeds every page (~$0.00002 × 200 URLs × N clients × 365). | Before `Embed_Page`, insert `Lookup_Existing_Page` (GET `pages?client_id=eq.X&url_path=eq.Y&select=last_seen_at,content_hash`) + `IF`. If `last_seen_at > now() - 20h` AND `sha256(text_for_embedding) === existing.content_hash`, skip to a `Touch_Last_Seen` PATCH; else continue. Store `content_hash` on the upsert. |
| 00-8 | No global error path: failures leave `pipeline_runs.status = running` forever. | Attach `SYS-Error-Handler` Error Workflow (see §3.1) via Workflow Settings → Error Workflow. |

---

### 2.3 WF-01 — CSV Keyword Ingest

| # | Core Issue | Technical Fix |
|---|---|---|
| 01-1 | `Respond_Ingest` and `Complete_Ingest_Run` fire inside the chunk loop. First chunk completes the run; subsequent failures invisible; webhook caller gets a multi-respond warning. | Move `Respond_Ingest` to fire immediately after `Validate_Ingest_Payload` with `{ ok: true, status: 'processing', pipeline_run_id }`. After the chunked insert, place an `Aggregate` node that waits for all chunks, then `Complete_Ingest_Run` runs exactly once. |
| 01-2 | `Fetch_Existing_Keywords` has a `Range: 0-49999` hard cap. Clients with >50k existing keywords get duplicate inserts. | **Push dedupe to the database (Conflict Resolution Decision — see §4.1).** Replace the client-side fetch + filter Code node with: (a) a unique constraint `CREATE UNIQUE INDEX raw_keywords_client_keyword_uniq ON raw_keywords (client_id, lower(keyword));` and (b) bulk insert with `Prefer: resolution=merge-duplicates` + `on_conflict=client_id,keyword`. Keep `Fetch_Graveyard` as a small one-page lookup for the explicit graveyard exclusion. |
| 01-3 | Graveyard dedupe is dead code. `graveyard_ids` Set is built but `Dedupe_Keywords` only filters against `existingSet`. | Either: (a) modify `Dedupe_Keywords` to filter against both Sets, OR (b) move graveyard exclusion to a Supabase RPC `check_keyword_exists_or_graveyard(p_client_id, p_keywords[])`. Recommend (b) for scalability. |
| 01-4 | Custom CSV parser breaks on RFC4180 edge cases: quoted commas, escaped quotes (`""`), multi-line quoted fields, BOM. | Replace the regex parser with n8n's built-in `Spreadsheet File` node (operation: "Read from file", `inputDataFieldName: csv_content`, `options.headerRow: true`). Keep a thin Code node only for trim/lowercase/number coercion. |
| 01-5 | No client existence check. Bad `client_id` produces an FK violation surfaced as a generic 500. | After parsing, add `Verify_Client` GET `clients?id=eq.{{client_id}}&select=id`; `IF` empty → respond 400. |
| 01-6 | No `pipeline_run_id` propagation; no downstream chain to WF-02. | Accept optional `pipeline_run_id` and `chain_next` in the webhook contract (default `chain_next=true`). If `pipeline_run_id` absent, create one. After successful `Complete_Ingest_Run`, POST `/webhook/wf-02-filter` with `{ client_id, pipeline_run_id }` when `chain_next === true`. |
| 01-7 | Base64 detection heuristic `!csv_content.includes(',')` produces false positives for single-column CSVs. | Require explicit `csv_encoding: 'base64' \| 'plain'` in payload (default `'plain'`). Reject the heuristic. |
| 01-8 | No payload size guard. A 5 MB CSV pasted into JSON balloons memory after parse. | At top of `Validate_Ingest_Payload`, reject if `csv_content.length > 5_000_000` with a 413 response. |

---

### 2.4 WF-02 — Tiered Keyword Filter

| # | Core Issue | Technical Fix |
|---|---|---|
| 02-1 | **CRITICAL CORRECTNESS BUG.** Tier 1 `passed` and `rejected` decisions never reach `keyword_classifications`. `Score_Tier1` computes the arrays, but `Prep_Tier2_Items` only iterates `borderline`. 60–80% of throughput silently dropped. | After `Score_Tier1`, add `Build_Tier1_Classification_Rows` Code node that emits classification rows for both `passed_tier1` and `rejected_tier1` arrays (with `decided_by='tier1_embedding'`, `pos_score`, `neg_score`, `embedding`, `pipeline_run_id`). Add `Write_Tier1_Classifications` bulk HTTP POST. This runs **in parallel** with the borderline path, not instead. |
| 02-2 | Tier 0 does not gate Tier 1. `Tier0_Regex_Filter` runs in parallel with `Fetch_Unclassified_Keywords` (both branch off `Merge_Client_Config`); rows rejected by Tier 0 are still embedded in Tier 1. Race condition. | Restructure the graph: `Merge_Client_Config` → `Tier0a_Regex_Filter` → `Tier0b_Competitor_Filter` → fan-out to `Fetch_Unclassified_Keywords` and `Fetch_Gold_Examples`. Either (a) modify Tier 0 RPCs to set `raw_keywords.status = 'tier0_rejected'` so existing `status=eq.raw` filter excludes them, OR (b) introduce `fetch_pending_for_tier1(p_client_id, p_limit)` RPC that LEFT JOINs `keyword_classifications`. Recommend (b) — more maintainable, no schema drift on `raw_keywords`. |
| 02-3 | `Batch_For_Embedding` SplitInBatches references `$json.batchIndex` which n8n v3 does not produce; `Score_Tier1` reads `$('Prepare_Tier1').first()` which holds all keywords, not the current chunk. | (a) Restructure `Prepare_Tier1` to output one item per embedding chunk: `{ chunk_index, chunk_offset, keywords[], keyword_ids[], pos_centroid, neg_centroid, ... }`. (b) Wire SplitInBatches loop branch → `Embed_Keywords_Batch`. (c) Update `Score_Tier1` to index `keyword_ids[i]` from the **current chunk**, not `Prepare_Tier1.first()`. (d) Loop `Score_Tier1` → `Batch_For_Embedding`; done branch → final aggregation. |
| 02-4 | Slack HITL card blocks `Respond_Filter`. The `IF_Needs_HITL` true-branch goes only to `Send_HITL_Card`; items needing review never reach the response node. | Make `Send_HITL_Card` a fire-and-forget side branch — it does NOT continue to `Respond_Filter`. Both branches of `IF_Needs_HITL` must reach `Respond_Filter` through a separate path. |
| 02-5 | 500-keyword cap (and the 50k `Range` cap) with no continuation for larger ingests. | Wrap `Fetch_Unclassified_Keywords → Call_Tier1 → Flatten → (writes)` in an offset-driven SplitInBatches. After each batch, fetch the next 500; stop when fetch returns < 500. Remove the hardcoded `Range: 0-49999` in favor of paged 500-row windows. |
| 02-6 | Gold examples not validated up front. If `clients.config.gold_examples` is empty, Tier 1 silently returns degraded scores and every keyword lands in `borderline`. | After `Validate_Input`, add `Fetch_Gold_Examples_Precheck`. If empty → branch to `Respond_Filter_Skipped` returning 422 "gold examples missing — re-run onboarding". |
| 02-7 | Tier 2 LLM has no batching, no rate limit, no retry, no JSON schema enforcement. | Insert `Split_In_Batches_T2` (batch size 5–25). Use n8n node retry: 3 attempts, exponential backoff. Confirm `response_format: { type: 'json_object' }` is honored (already present in the current request — keep it). Wrap `Prepare_T2_Write` parse in try/catch; on parse failure write `decision='parse_error'` with raw response in `notes`. |
| 02-8 | Tier 1 classification rows (once 02-1 adds them) will have no `pipeline_run_id`. (Tier 2 rows already include it in the current `Parse_Tier2_Response` payload — no change needed there.) | In the new `Build_Tier1_Classification_Rows` Code node added by 02-1, include `pipeline_run_id: ctx.pipeline_run_id` in every row emitted for `passed_tier1` and `rejected_tier1`. |
| 02-9 | No idempotency on re-runs. Tier 1 fetch re-reads already-classified rows because filter is only `status=raw`. | The fetch RPC from 02-2 (b) must `EXCLUDE keyword_id IN (SELECT keyword_id FROM keyword_classifications WHERE client_id = ?)`. |
| 02-10 | `Write_Classification` uses `Prefer: return=minimal`, so Slack button payloads cannot carry the actual classification row ID. | Change to `Prefer: return=representation` for Tier 2 writes feeding HITL cards. |

---

### 2.5 WF-03 — Clustering + 3-Axis Labeling

| # | Core Issue | Technical Fix |
|---|---|---|
| 03-1 | `keyword_cluster_map` is never written. Cluster headers are inserted but the keyword↔cluster relationship is lost. WF-04 SerpAPI, WF-05 Sheets cannot reconstruct membership. | Create table if missing (see §3.3). After `Write_Cluster` returns the inserted cluster `id`, add `Merge_Cluster_Context` Code node that pairs the inserted ID with `member_ids`, then `Build_Map_Rows` emits `{ cluster_id, keyword_classification_id, pipeline_run_id, client_id }` per member, then `Bulk_Insert_Cluster_Map` HTTP POST. |
| 03-2 | Context loss after `Fetch_Passed_Classifications` and after `Write_Cluster`. `$json.client_id` is `undefined` because PostgREST returns arrays; `IF_Needs_Taxonomy_Review` checks `$json.needs_taxonomy_review` which is overwritten by the Supabase insert response. | (a) Add `Merge_Client_Context` Code node after `Fetch_Client` that re-attaches `client_id` and `pipeline_run_id` from `Validate_Cluster_Payload`. (b) Add `Merge_Cluster_Context` after `Write_Cluster` that re-attaches `needs_taxonomy_review`, `label`, `head_term`, `confidence` from before the write. (c) Move `IF_Needs_Taxonomy_Review` after the merge. |
| 03-3 | `Respond_Cluster` fires per cluster. Multi-respond warnings; only first reaches caller. | Place `Respond_Cluster` after an `Aggregate` node that waits for all per-cluster writes. Fires exactly once with `{ ok: true, clusters_written, taxonomy_suggestions_written }`. |
| 03-4 | `Send_Taxonomy_Suggestion` blocks the webhook response. | Same pattern as 02-4 — Slack post is a side branch terminating in noop; not on the response path. |
| 03-5 | Per-cluster LLM labeling with no batching, no retry, no rate-limit. N clusters = N sequential OpenRouter calls. | Wrap `LLM_Label_Cluster` in `Split_In_Batches` (size 3). Enable retry 3× with exponential backoff (2s/4s/8s). Keep `response_format: { type: 'json_object' }`. Wrap parse in try/catch; fallback label = `keywords[0].keyword + ' (unlabeled)'`. |
| 03-6 | Cannibalization check declared in sticky note but not implemented. No node queries `pages.embedding`. | **Resolution: ship behind a feature flag (see §4.3).** Add `clients.config.cannibalization_enabled` (default false). When true, after `Parse_LLM_Label`, call a new Supabase RPC `find_cannibalization_candidates(p_client_id, p_centroid vector, p_threshold float)` using pgvector cosine on `pages.embedding`. Set `clusters.cannibalization_risk_page_id` from top hit if similarity > threshold (default 0.82, from `clients.config.cannibalization_threshold`). |
| 03-7 | Hardcoded Railway worker URL `https://seo-tools-production-c347.up.railway.app/cluster`. No env var indirection. | Change `Call_Python_Worker.url` to `={{ $env.PYTHON_WORKER_URL }}/cluster`. |
| 03-8 | Worker response schema not validated. A field rename (e.g. `head_keyword` vs `head_term`) silently produces empty clusters. | In `Parse_Worker_Response`, throw a controlled error if `response.clusters` is not an array or if first cluster lacks required keys (`cluster_id`, `member_ids`). |
| 03-9 | Single-member / noise (`cluster_id === -1`) clusters still hit the LLM. | After `Parse_Worker_Response`, `IF (cluster_id === -1 OR keywords.length < 2)` → write a thin row with `label = keywords[0].keyword`, `confidence = 'low'`, skip LLM. |
| 03-10 | No `pipeline_run_id` on `keyword_cluster_map` writes. (`clusters.pipeline_run_id` is already populated by the current `Write_Cluster` payload — no change needed there.) | When adding `Bulk_Insert_Cluster_Map` (see 03-1), include `pipeline_run_id` in every map row insert. |
| 03-11 | No idempotency. Re-runs duplicate cluster rows. | Before `Build_Cluster_Payload`, GET `clusters?client_id=eq.X&pipeline_run_id=eq.Y`. If non-empty, respond 200 with `{ skipped: true }`. |
| 03-12 | `Fetch_Passed_Classifications` 1000-row default page size; 50k Range cap; no pagination. | Paged loop with `Range: 0-999`, `1000-1999`, ... stop when page < 1000. Concatenate into worker payload. |
| 03-13 | Worker payload missing keyword text (only id + embedding). If worker doesn't re-fetch, head-term derivation is unreliable. | Include `keyword` (and optionally `volume`, `kd`) in each worker payload item. |

---

### 2.6 WF-04 — ICP Scoring + Priority

| # | Core Issue | Technical Fix |
|---|---|---|
| 04-1 | `Update_Cluster_Score` PATCHes only `priority_score`. `icp_match_score`, `commercial_intent_weight`, reasoning fields, and `scored_at` are computed but discarded. | PATCH body must include: `priority_score, icp_match_score, commercial_intent_weight, icp_match_reasoning, commercial_reasoning, serp_intent_signals, scoring_inputs, scored_at, last_pipeline_run_id`. |
| 04-2 | Priority formula uses `keyword_count` as a proxy for volume and hardcodes `avgKd = 0`. A cluster of 50 low-volume keywords beats 3 high-volume keywords. KD penalty term `- (avgKd * 0.5)` is always zero. | **Resolution: upgrade to real volume/KD now (see §4.2).** Modify WF-03's `Build_Map_Rows` to also write `total_volume` (SUM) and `avg_kd` (AVG) onto the `clusters` row at insert time (via a Supabase trigger or in `Write_Cluster` payload using values aggregated from `keyword_cluster_map ⨝ raw_keywords`). WF-04 `Compute_Priority_Score` then uses `ctx.total_volume` and `ctx.avg_kd`. Lock the canonical formula in `WF-04.md`. |
| 04-3 | `Respond_Score` fires per cluster. Multi-respond warnings. | After all per-cluster PATCHes, place `Aggregate` → `Respond_Score` exactly once with `{ ok: true, scored: N, skipped: M, total_cost_usd }`. |
| 04-5 | SerpAPI and LLM calls one-per-cluster, no batching, no retry, no rate-limit Wait. 100 clusters × 2 calls = 200 sequential round-trips. | (a) Wrap `Fetch_SERP_Data` in `Split_In_Batches` (size 5) with `Wait` 1s between. Enable node retry 3× (5s/15s/45s). Set `continueOnFail = true`; on failure write synthetic empty SERP so LLM can still score on label+keywords. (b) Same pattern for `LLM_ICP_Score` (batch size 3). |
| 04-6 | Cost ceiling is naive. The current check estimates current-run cost but ignores historical `api_cost_log` and per-month budget. | Before SerpAPI, GET `api_cost_log?client_id=eq.X&created_at=gte.<month_start>&select=usd_cost`. Sum + run estimate (`serpCost = clustersToScore * 0.03` + `llmCost = clustersToScore * 0.002`). If total > `clients.config.monthly_api_budget_usd` (default $50), respond 402 and PATCH `pipeline_runs.status = budget_exceeded`. **Graceful degradation:** process the largest subset that fits the budget rather than throw. |
| 04-7 | 100-cluster hard cap. Redundant with the budget guard once 04-6 is fixed. | Remove `Math.min(100, clusters.length)`. Process all clusters within budget. |
| 04-8 | Label fallback missing. If LLM-generated cluster label is "Untitled" or weak, SerpAPI returns junk. | Before SerpAPI: `query = (label && label !== 'Untitled') ? label : top_keyword_text`. Fetch `top_keyword_text` via a single upfront Supabase call joining `keyword_cluster_map ⨝ raw_keywords` `ORDER BY volume DESC LIMIT 1` per cluster. |
| 04-9 | Idempotency gate ambiguous. Doc says `icp_score IS NULL`; partial-run safety wants `scored_at IS NULL`. | Canonical filter: `scored_at=is.null`. Update `WF-04.md` to match. |
| 04-11 | Context loss after `Fetch_Client_And_Clusters` (PostgREST array). `client_id` may be lost on each per-cluster item. | Add `Merge_Client_Context` Code node that flattens the array to one item per cluster carrying `{ client_id, pipeline_run_id, cluster_id, label, keyword_count, total_volume, avg_kd, top_keyword_text }`. |
| 04-12 | Empty-state respond missing. When no unscored clusters, `Respond_Score` may not fire. | After fetch, `IF (clusters.length === 0)` → respond `{ ok: true, status: 'no_unscored_clusters' }`. |

> Note: Draft items **04-4** (encodeURIComponent) and **04-10** (SerpAPI cost not logged) have been removed — see §0.

---

### 2.7 WF-05 — Nightly Google Sheets Sync

| # | Core Issue | Technical Fix |
|---|---|---|
| 05-1 | Race condition / cross-client data bleed via `.first()` and parallel fan-out. `Build_Sheet_Data` reads `$('Fetch_Client_Clusters').first()` etc., always returning client[0]'s data regardless of which client is being processed. | Insert `Split_In_Batches_Clients` (size 1) right after `Fetch_Active_Clients`. Every node downstream reads `$('Split_In_Batches_Clients').item.json` for the current client. Loop back from end of each iteration. Chain the three fetches **sequentially** (`Fetch_Client_Clusters` → `Fetch_Taxonomy_Suggestions` → `Fetch_API_Costs`) rather than in parallel; eliminates the multi-input-merge race. |
| 05-2 | Only the Cost tab is written. `pillar_tabs`, `themes_rows`, `tax_rows` are built in `Build_Sheet_Data` but no Google Sheets node writes them. | **Resolution: lock contract to `Clusters` + `Cost` tabs only; defer the rest (see §4.4).** Update `WF-05.md` and remove `pillar_tabs`, `themes_rows`, `tax_rows` from `Build_Sheet_Data`. Add a `Write_Clusters_Tab` Google Sheets node alongside `Write_Cost_Tab`. If reporting later demands `Themes` / `Taxonomy-Suggestions` / per-pillar tabs, re-add in a v2 sprint. |
| 05-3 | Sheets append is not idempotent. Every nightly run appends ALL 500 clusters again; after 30 nights the tab has 30× duplicate rows. | Switch to a delta-append + dedupe strategy: (a) add `Cluster_Synced_At` column; (b) Supabase fetch filter `scored_at=gt.<last_sync>`; (c) track `last_sheet_sync_at` on `clients` (PATCH after sync). For Cost tab, use a deterministic `(provider, date)` key with `appendOrUpdate` mode and unique column `provider_date`. |
| 05-4 | Slack summary may report wrong client because `Build_Summary` reads `Fetch_Active_Clients.first()`. | Inside the per-client loop, read `$('Split_In_Batches_Clients').item.json.name`. Aggregate per-iteration `{ client_name, cluster_count, cost_usd, top3 }`. After the loop, send **one** Block Kit digest naming all clients with their counts. |
| 05-5 | Slack notification fires for unconfigured clients ("sync complete" with 0 data). | Inside loop, if `Build_Sheet_Rows.length === 0` OR `sheets_view_id` is null, push to a `skipped[]` array; skip Sheets write. The final digest mentions skipped clients separately ("M clients skipped — no sheets_view_id configured"). |
| 05-6 | `Fetch_API_Costs` time window unclear ("last 200 rows" is volume-based). | Change filter to `created_at=gte.<now - 24h>`. Remove 200-row cap. |
| 05-7 | No global error path. Cron failures invisible — no `pipeline_runs` row created. | At top, create `pipeline_runs` row with `kind='sheet_sync'`. PATCH `completed` after the loop; on error via `SYS-Error-Handler` PATCH `failed`. |
| 05-8 | Parallel fetches have no error isolation. If `Fetch_Taxonomy_Suggestions` fails, `Build_Sheet_Data` may fail entirely. | Set `continueOnFail = true` on each fetch. In `Build_Sheet_Data`, default missing inputs to `[]` before use. |
| 05-9 | Hardcoded Slack channel ID `C0B43A7QG5P`. | Replace with `{{ $json.client_config?.hitl_channels?.[0] \|\| $env.SLACK_HITL_CHANNEL }}`. |
| 05-10 | No pagination on `Fetch_Client_Clusters` / `Fetch_Taxonomy_Suggestions` (default 1000-row page). | Apply paged Range loop pattern. Stop when page < 1000. |

---

## 3. Architecture & Scalability Suggestions (Cross-Workflow)

These shared additions unblock most per-workflow fixes. Implement these **first**.

### 3.1 SYS-Error-Handler (Global Error Workflow)

A new top-level workflow `SYS-Error-Handler` triggered by **n8n Error Trigger** node. On any uncaught exception:

1. Receives `$execution.error` and `$execution.workflowData.id`.
2. Extracts in-flight `pipeline_run_id` from `$execution.data.executionData` (or from the originating webhook payload if recoverable).
3. PATCHes `pipeline_runs` set `status='failed'`, `error_message=<truncated stack>`, `failed_at=now()`.
4. Posts a Slack alert to `$env.SLACK_OPS_CHANNEL` with workflow name, error class, and a deep link to the execution.
5. (For WF-ONBOARD only) Also PATCHes `onboarding_sessions.status='failed'`.

**Bind via Workflow Settings → Error Workflow → `SYS-Error-Handler`** on all seven workflows.

### 3.2 `onboarding_sessions` Table (Phase-State Persistence)

`pipeline_runs` already exists; what is missing is durable per-execution storage for the WF-ONBOARD three-phase flow (Phase A crawl + LLM → Phase B questionnaire → Phase C flag ack). Add **one new table** keyed by `pipeline_run_id`:

```sql
create table if not exists onboarding_sessions (
  pipeline_run_id uuid primary key references pipeline_runs(id) on delete cascade,
  client_url      text not null,
  client_name     text not null,
  competitors     text[] not null default '{}',
  seed_keywords   text[] not null default '{}',
  crawled_pages   jsonb not null default '[]'::jsonb,
  llm_site_analysis      jsonb,
  questionnaire_response jsonb,
  cross_validation       jsonb,
  status text not null default 'phase_a',
    -- valid: phase_a, phase_a_complete, awaiting_questionnaire,
    --        phase_b_complete, awaiting_flag_ack, completed, failed
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_onboarding_sessions_status
  on onboarding_sessions(status);
```

Phase A writes after `LLM_Site_Analysis`. Phase B re-hydrates on first node. Phase C re-hydrates on first node. Slack modal `private_metadata` carries `pipeline_run_id` as the only handle between phases.

> **Alternative considered:** storing this in `pipeline_runs.input_summary` (already a `jsonb` column). Rejected because the lifecycle of an onboarding session and the lifecycle of `pipeline_runs.status` are not the same — a session can be in `awaiting_questionnaire` (idle, days) while the `pipeline_runs.status` row should not block other runs. Separate table keeps cleanup and querying surgical.

### 3.3 `keyword_cluster_map` Traceability (ALTER existing table)

`keyword_cluster_map` **already exists** in [0001_initial_schema.sql](../../../supabase/migrations/0001_initial_schema.sql) with:

```sql
-- existing shape (do not recreate)
create table keyword_cluster_map (
    id                          uuid primary key default gen_random_uuid(),
    keyword_classification_id   uuid not null references keyword_classifications(id) on delete cascade,
    cluster_id                  uuid not null references clusters(id) on delete cascade,
    role                        cluster_member_role_enum not null default 'long_tail_supporting',
    distance_from_centroid      numeric(6, 4),
    unique (keyword_classification_id, cluster_id)
);
```

It is just never written by WF-03. The fix has two parts:

1. **Schema (Wave 1)** — add traceability columns for cross-workflow filtering by client/run:

```sql
alter table keyword_cluster_map
  add column if not exists client_id uuid references clients(id) on delete cascade,
  add column if not exists pipeline_run_id uuid references pipeline_runs(id) on delete cascade;

create index if not exists idx_keyword_cluster_map_client
  on keyword_cluster_map(client_id);
```

2. **Workflow (Wave 2)** — WF-03 03-1 wires the actual inserts (see §2.5).

### 3.3a `clusters` ALTER (small delta only)

The live `clusters` table **already has** `pipeline_run_id`, `total_volume`, `avg_kd`, `priority_score`, `cannibalization_risk_page_id`, `suggested_service_pillar`, `intent_type`, `keyword_count`. The PRD's earlier draft proposed re-adding several of these — that was wrong. The actual delta is one column:

```sql
alter table clusters
  add column if not exists worker_cluster_id int;
```

Used by WF-03 to record the integer cluster ID returned by the Python worker (for traceability when re-running HDBSCAN with different parameters).

### 3.4 Universal LLM Call Pattern

Standardize across WF-02 Tier 2, WF-03 LLM_Label, WF-04 LLM_ICP_Score, WF-ONBOARD LLM_Site_Analysis and LLM_CrossValidate:

- **Wrap in `Split_In_Batches`** (batch size 3–5).
- **Enable node retry:** 3 attempts, exponential backoff (n8n built-in: 2s base, 2× multiplier).
- **Set `response_format: { type: 'json_object' }`** on the body (already present in WF-02 and WF-03 — keep; add to WF-04 and WF-ONBOARD).
- **Wrap the JSON parse in `try/catch`**; on failure, write a fallback row marked `parse_error` and continue (never let one malformed response halt the batch).
- **Add `Wait` 1s** between batches as a soft rate-limit.
- **Log cost** to `api_cost_log` per call with `provider`, `model`, `prompt_tokens`, `completion_tokens`, `cost_usd`, `workflow`, `client_id`, `pipeline_run_id`.

### 3.5 Universal Pagination Helper

Create a reusable Code node template `Paginate_Supabase_Range`:

```javascript
const pageSize = $json.page_size || 1000;
const baseUrl = $json.base_url;
let offset = 0;
const all = [];
while (true) {
  const resp = await $helpers.httpRequest({
    method: 'GET',
    url: baseUrl,
    headers: { Range: `${offset}-${offset + pageSize - 1}`, ...$json.headers },
  });
  all.push(...resp);
  if (resp.length < pageSize) break;
  offset += pageSize;
}
return [{ json: { rows: all, count: all.length } }];
```

Replace every `Range: 0-49999` hardcoded fetch in WF-01, WF-02, WF-03, WF-05 with this pattern.

### 3.6 Universal Webhook-Response Pattern

For every webhook-triggered workflow (WF-01, WF-02, WF-03, WF-04, WF-ONBOARD Phase A):

1. **Respond immediately** after the validation/run-row-creation step, returning `{ ok: true, status: 'processing', pipeline_run_id }`.
2. **Move all heavy work behind the response.** Set `Respond to Webhook` mode to "Immediately" (not "When last node finishes").
3. **Final completion writes** PATCH `pipeline_runs.status = 'completed'` after an `Aggregate` waits for all per-item branches.
4. **Slack/HITL/Taxonomy notifications are fire-and-forget side branches** that terminate in a noop, never blocking the response or the completion PATCH.
5. **Chain to next workflow** (e.g. WF-01 → WF-02) via an `executeOnce: true` HTTP POST gated by `chain_next` flag (default `true`).

### 3.7 Universal Idempotency Markers

Every workflow that mutates rows must:

- Accept optional `pipeline_run_id` in its trigger payload; create one if absent.
- Write `pipeline_run_id` on every row insert (`keyword_classifications`, `clusters`, `keyword_cluster_map`, `pages`, `api_cost_log`).
- Before doing expensive work, check whether a row with the same `(client_id, pipeline_run_id)` already exists; if so, respond 200 with `{ skipped: true, reason: 'idempotent_replay' }`.

### 3.8 PostgREST Response Unwrap Convention

Every HTTP node fetching a single row from Supabase that downstream expressions treat as `$json.<field>` must either:

- Send header `Accept: application/vnd.pgrst.object+json` (PostgREST single-object mode), OR
- Be followed by a `Merge_<context>` Code node that explicitly unwraps `items[0]` and re-attaches needed fields.

This eliminates the entire class of "context loss after fetch" bugs observed in WF-02, WF-03, WF-04.

### 3.9 Environment Variables (Standardize)

| Variable | Replaces |
|---|---|
| `PYTHON_WORKER_URL` | `https://seo-tools-production-c347.up.railway.app` hardcoded URL in WF-03 |
| `WP_GRAPHQL_URL` | `https://cms.webleymedia.com/graphql` in WF-00 |
| `SLACK_HITL_CHANNEL` | Hardcoded channel `C0B43A7QG5P` in WF-02, WF-03, WF-05 |
| `SLACK_OPS_CHANNEL` | New, used by `SYS-Error-Handler` |
| `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` | Already standardized — keep. |

---

## 4. Conflict Log

### 4.1 WF-01 Deduplication: Client-side fetch vs. Database constraint

**Decision:** Database-side dedupe via unique index + `merge-duplicates`.

**Justification:** Client-side dedupe is bounded by n8n worker memory and the 50k Range cap; database dedupe scales to any cardinality. A single SQL constraint is the source of truth; future workflows that touch `raw_keywords` cannot accidentally create duplicates regardless of their code. Database-side is also faster (one round-trip, one index lookup per row). Trade-off accepted: loss of granular "inserted vs skipped" counts. Mitigation: log a per-chunk count of `inserted` rows from the Supabase response and approximate `skipped = chunk_size - inserted`.

### 4.2 WF-04 Priority Score: Keep proxy vs. Upgrade to real Volume/KD

**Decision:** Upgrade to real `total_volume` / `avg_kd`, rolled up at WF-03 cluster-write time.

**Justification:** The proxy formula produces inverted rankings as the keyword corpus grows (many small clusters outrank few large ones). At 10k+ keywords per client the placeholder makes WF-04 actively misleading. Rolling up at WF-03's `Write_Cluster` payload using `SUM/AVG` over the in-memory `member_ids` join costs one extra Supabase query per cluster — negligible. Dependent on §3.3 (`keyword_cluster_map`) being in place. Lock the formula in `WF-04.md` once shipped.

### 4.3 WF-03 Cannibalization Check: Ship now vs. Defer

**Decision:** Ship behind a `clients.config.cannibalization_enabled` feature flag (default `false`), implemented via the pgvector RPC `find_cannibalization_candidates`.

**Justification:** A feature flag lets us pilot on one or two clients before rolling out; the pgvector RPC offloads the math to Postgres and is O(log n) on the page set. When disabled, zero cost. When enabled, one Supabase RPC per cluster with an index-backed similarity query — sub-50ms. Dependency: WF-00 must be correctly populating `pages.embedding` (see 00-1 through 00-7) before this is useful.

### 4.4 WF-05 Sheets Tab Contract: Multi-tab vs. Minimal

**Decision:** Lock the contract to `Clusters` + `Cost` tabs only for this sprint.

**Justification:** Multi-tab writes amplify Sheets API quota usage linearly (10 clients × 7 tabs = 140 ops nightly). Two tabs (20 ops) buys 7× headroom. Locking the contract eliminates the doc/export disagreement. The `pillar_tabs`, `themes_rows`, `tax_rows` data structures are removed from `Build_Sheet_Data` entirely, simplifying the Code node. Re-introduction plan: if a stakeholder requests Themes or Taxonomy tabs in a future sprint, the data already exists in Supabase — add the writer nodes then. Do not pre-build.

---

## 5. Implementation Sequencing (Recommended Sprint Order)

**Wave 1 — Foundations (do these first, in parallel):**
- §3.1 `SYS-Error-Handler` workflow (SDK in `sdk/sys-error-handler.ts`, mirror style of `wf-onboard.ts`) + bind to all seven workflows.
- §3.2 `onboarding_sessions` table (NEW — only net-new table in Wave 1).
- §3.3 `keyword_cluster_map` traceability columns (`client_id`, `pipeline_run_id`) — table itself already exists.
- §3.3a `clusters.worker_cluster_id` column — all other PRD-proposed columns (`pipeline_run_id`, `total_volume`, `avg_kd`) already exist.
- §3.9 Environment variables (`PYTHON_WORKER_URL`, `WP_GRAPHQL_URL`, `SLACK_HITL_CHANNEL`, `SLACK_OPS_CHANNEL`) added to n8n + [README.md](../../README.md).
- DB unique constraint for WF-01: promote the existing non-unique `idx_raw_keywords_client_keyword` index on `(client_id, lower(keyword))` to a **UNIQUE** index. Pre-check for duplicates before applying.

**Wave 2 — Critical correctness (parallel after Wave 1):**
- WF-00: 00-1, 00-2, 00-3, 00-4 (SplitInBatches loop, error tolerance, sitemap-index).
- WF-02: 02-1 (Tier 1 write — the single highest-impact bug), 02-2 (Tier 0 gate), 02-3 (batch wiring).
- WF-03: 03-1 (`keyword_cluster_map` writes), 03-2 (context preservation), 03-3 (single response).
- WF-ONBOARD: O1, O2, O3, O4, O5 (session persistence + modal + batch wiring + immediate response).

**Wave 3 — Scaling & resilience:**
- §3.4 Universal LLM pattern → applied to WF-02 (02-7), WF-03 (03-5), WF-04 (04-5), WF-ONBOARD (O10).
- §3.5 Universal pagination → applied to WF-01 (01-2), WF-02 (02-5), WF-03 (03-12), WF-05 (05-10).
- §3.6 Universal webhook-response → applied to WF-01 (01-1), WF-02 (02-4), WF-03 (03-3, 03-4), WF-04 (04-3).
- WF-04: 04-1 (full PATCH body), 04-2 (real volume/KD — depends on Wave 1 schema and WF-03 03-1).
- WF-05: 05-1 (per-client loop), 05-2 (lock to 2 tabs + add Clusters writer), 05-3 (delta append).

**Wave 4 — Polish & idempotency:**
- §3.7 idempotency markers across all writers.
- WF-00 00-5, 00-6, 00-7 (WPGraphQL config, paired-item fix, embedding cache).
- WF-01 01-4, 01-5, 01-6, 01-7, 01-8 (parser, client check, chain WF-02, base64 explicit, payload guard).
- WF-02 02-6, 02-8, 02-9, 02-10 (gold examples precheck, run_id, idempotency, return=representation).
- WF-03 03-6 (cannibalization behind flag), 03-7..03-13.
- WF-04 04-6 through 04-12 (excluding removed 04-4 and 04-10).
- WF-ONBOARD O6..O14 (excluding removed O11).

**Wave 5 — Validation:**
- Smoke test each workflow with the test scenarios in each `Execution Plan` (per §2).
- End-to-end: WF-ONBOARD → WF-01 → WF-02 → WF-03 → WF-04 → confirm `pipeline_run_id` traces a single client from CSV upload to scored cluster row to Sheets-synced row.
- Chaos test: kill the Python worker mid-WF-03; verify `SYS-Error-Handler` PATCHes the run to `failed` and posts to Slack ops channel.

**Wave 6 — Voice & content-skill foundation (see §7):**
- Create `system_prompts` Supabase table and load the `human-written-blog` skill as `name='human-written-blog', version=1, is_active=true`.
- Apply the skill selectively to the four prose-producing LLM prompts identified in §7.1 (Slack questionnaire prose, completion digest, taxonomy-suggestion message, sync-summary copy). **Do not** apply it to structured-JSON producers.
- Scaffold WF-06 (`Content Draft from Cluster`) as a separate workflow stub — full implementation deferred to a follow-up sprint once the upstream pipeline (WF-01 through WF-04) is producing reliable cluster output.

---

## 6. Audit Provenance

This PRD was synthesized from four independent audit passes (Provider A, B, C, D) across 7 workflows = 28 source reports, then **re-verified against the live JSON exports** in `SEO-Tools/n8n-workflows/exports/` on 2026-05-21. Three single-model claims contradicted by the actual code were excluded (see §0). Every retained issue has been confirmed against the source files cited inline.

---

## 7. Voice & Content-Skill Integration

This section incorporates the `human-written-blog` skill (located at `SEO-Tools/n8n-workflows/skills-to-add/skill/human-written-skill.md`) into the workflow ecosystem. The skill is a long-form system prompt that forces LLM output to read like a human SEO writer instead of a chatbot: it bans roughly 200 AI-tell words/phrases, mandates varied rhythm and sentence-case headings, requires concrete specifics over vague generalities, and forbids decorative typography (em dashes, smart quotes, decorative bullets).

### 7.1 Scope decision: where the skill applies and where it does not

The seven existing workflows are **upstream data infrastructure** — they don't produce blog content. Applying the blog-voice skill globally to every LLM call would actively damage the structured-JSON producers (cluster labeler, classifier, ICP scorer) whose entire job is to return strict schemas. The skill must be applied **selectively**, by call site.

| Call site | Output type | Apply skill? |
|---|---|---|
| WF-02 `LLM_Tier2_Classify` | Strict JSON `{ status, reasoning }` | **No.** Schema is the contract. |
| WF-03 `LLM_Label_Cluster` | Strict JSON `{ label, pillar, niche, theme, confidence }` | **No.** Same reasoning. |
| WF-04 `LLM_ICP_Score` | Strict JSON with `icp_match_reasoning` field | **No.** Internal audit copy, not user-facing prose. |
| WF-ONBOARD `LLM_Site_Analysis` | Strict JSON describing pillars + ICP | **No** for the JSON. **Yes** for the `client_summary` free-text field if one is added. |
| WF-ONBOARD Slack questionnaire prose | User-facing modal copy | **Yes.** First piece of prose a paying client reads. |
| WF-ONBOARD `Send_Completion_Notification` | User-facing copy | **Yes.** |
| WF-03 `Send_Taxonomy_Suggestion` | Internal HITL channel copy | **Yes** (lower priority). |
| WF-05 nightly digest | User-facing copy | **Yes.** Daily touchpoint with stakeholders. |
| **WF-06 (future) — Content draft from scored cluster** | Full blog post | **Yes.** Native habitat. |

### 7.2 Storage pattern: `system_prompts` Supabase table

```sql
CREATE TABLE system_prompts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  version int NOT NULL DEFAULT 1,
  content text NOT NULL,
  description text,
  is_active boolean NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (name, version)
);
CREATE INDEX system_prompts_active_idx ON system_prompts (name) WHERE is_active = true;
```

**Bootstrap:** Insert one row with `name='human-written-blog'`, `version=1`, `content=<full markdown of human-written-skill.md>`, `is_active=true`.

### 7.3 n8n loading pattern

1. **`Fetch_System_Prompt`** — HTTP GET `{{$env.SUPABASE_URL}}/rest/v1/system_prompts?name=eq.human-written-blog&is_active=eq.true&select=content&limit=1`, with `Accept: application/vnd.pgrst.object+json`.
2. **`Build_LLM_Request`** — Code node that builds the OpenRouter payload with `messages: [{ role: 'system', content: $('Fetch_System_Prompt').item.json.content }, { role: 'user', content: <task-specific prompt> }]`.
3. The LLM HTTP node sends the request as usual.

**Caching:** Set `Fetch_System_Prompt` to `executeOnce: true` per execution.

### 7.4 Forward scope: WF-06 — Content Draft from Cluster

**Not in this sprint's implementation scope** but named here so the skill has a defined destination.

**Trigger:** Webhook `/wf-06-draft-from-cluster` accepting `{ client_id, cluster_id, target_word_count?, draft_purpose? }`.

**Flow sketch:**

1. `Validate_Draft_Payload` — verify client + cluster exist and cluster has `priority_score >= 0.5` (configurable).
2. `Fetch_Cluster_Context` — Supabase RPC joining `clusters ⨝ keyword_cluster_map ⨝ raw_keywords`.
3. `Fetch_Client_Voice_Sample` — if `clients.config.voice_sample_url` is set, fetch it.
4. `Fetch_System_Prompt` — pulls active `human-written-blog` row.
5. `Build_Draft_Request` — combines skill content as system message + cluster context + user prompt.
6. `LLM_Draft_Post` — OpenRouter call. `response_format` is **not** set to `json_object`. Retry 3× with backoff.
7. `Post_Process_Check` — Code node scans draft against em dashes, curly quotes, decorative bullets; logs hits to `draft_qa`.
8. `Write_Draft` — INSERT into `content_drafts`.
9. `Log_API_Cost` — same pattern as WF-04.
10. `Respond_OK` — returns `{ ok, draft_id, word_count, cluster_id }`.

**Schema for content drafts:**

```sql
CREATE TABLE content_drafts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL,
  cluster_id uuid NOT NULL REFERENCES clusters(id),
  pipeline_run_id uuid,
  version int NOT NULL DEFAULT 1,
  system_prompt_name text NOT NULL,
  system_prompt_version int NOT NULL,
  content text NOT NULL,
  word_count int,
  status text DEFAULT 'draft',   -- draft, reviewed, published, rejected
  qa_findings jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX content_drafts_client_idx ON content_drafts (client_id);
CREATE INDEX content_drafts_cluster_idx ON content_drafts (cluster_id, version DESC);
```

### 7.5 Sprint integration summary

| Wave | Skill-related work |
|---|---|
| Wave 1 (foundations) | None — keep focus on `SYS-Error-Handler`, schema changes. |
| Wave 6 (new) | (a) Create `system_prompts` table. (b) Bootstrap `human-written-blog` v1 from the markdown file. (c) Add `Fetch_System_Prompt` nodes to the four prose call sites in §7.1. (d) Scaffold `WF-06` workflow stub + `content_drafts` schema; do not yet wire the live LLM call. |
| Post-sprint | Full WF-06 implementation, voice-sample handling, multi-version A/B testing of skill variants. |

---

*Phase 2 update spec — ready for development-agent handoff. All §2 fixes have been verified against the live workflow JSON, the live Supabase schema, and the live Postgres functions. Sections §4 (conflict decisions), §5 (sprint sequencing), and §7.1 (skill application scope) require stakeholder sign-off before Wave 1 execution begins. Wave 1 work itself has no blocking decisions: it only adds one table, three columns, one unique index, four env vars, one global error workflow, and one error-workflow binding on each of the seven existing workflows.*
