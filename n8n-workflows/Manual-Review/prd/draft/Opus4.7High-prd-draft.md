# Master PRD & Technical Specification: Workflow Optimizations

**Version:** 1.0 (Draft — Opus 4.7 High Reasoning consensus synthesis)
**Date:** 2026-05-21
**Inputs:** 4 independent audit passes (Provider A, B, C, D — anonymized) × 7 workflows (WF-ONBOARD, WF-00, WF-01, WF-02, WF-03, WF-04, WF-05). 28 source reports.
**Codebase verified against:** `SEO-Tools/n8n-workflows/exports/*.json`, `SEO-Tools/n8n-workflows/sdk/wf-onboard.ts`, `SEO-Tools/n8n-workflows/README.md`.
**Conflict resolution priority:** Scalability > Maintainability > Execution Speed.

---

## 1. Executive Consensus Summary

The seven-workflow keyword pipeline is **architecturally correct but operationally broken at production scale.** All four reviewers converged on the same diagnosis: the *shape* of the assembly line (Onboard → 00 → 01 → 02 → 03 → 04 → 05) is sound and should not be redesigned; what is broken is the wiring, idempotency, and persistence inside each station. The system today silently truncates data, double-writes the wrong rows, and reports success on partial runs — meaning every downstream metric (cluster quality, ICP scores, Slack digests) is computed on incomplete inputs.

**Universal-consensus critical defects (all 4 reviewers, all severities high):**

1. **SplitInBatches v3 loop is mis-wired in WF-00 and WF-ONBOARD.** Output 0 = "done", output 1 = "per batch". Both workflows currently process only the first batch (10 pages and 5 pages respectively), then fire run-completion as if the entire client was synced. Every nightly page-inventory run produces fraudulent `pipeline_runs.status = completed` rows.
2. **Webhook responses fire inside per-item loops** in WF-01, WF-02, WF-03, and WF-04. The first item's response wins; the caller is told "ok" before downstream work finishes, and n8n logs a multi-respond warning that goes unmonitored.
3. **The `Range: 0-49999` cap is replicated across WF-01, WF-02, WF-03, and WF-05** with no pagination loop. Any client crossing 50k rows is silently truncated. The same pattern (default 1000-row Supabase page size, never opted out of) appears on smaller fetches.
4. **`pipeline_run_id` is accepted at every webhook but never persisted on the actual row writes** (`keyword_classifications`, `keyword_clusters`, `api_cost_log`, etc.). Cross-workflow traceability is broken from WF-01 onward.
5. **There is no global error workflow.** Any uncaught exception leaves `pipeline_runs.status = 'running'` forever; operators cannot distinguish a stuck run from a live one.
6. **WF-02 silently drops 60–80% of throughput.** Tier 1 `passed` and `rejected` decisions are computed but never written to `keyword_classifications` — only the borderline → Tier-2 path persists. This is the single highest-impact correctness bug in the pipeline.
7. **WF-03 writes cluster headers but no `keyword_cluster_map` rows.** WF-04 and WF-05 cannot reconstruct which keywords belong to which cluster.
8. **WF-ONBOARD chains three n8n webhook triggers as if they were Wait nodes.** They are not — each webhook starts a new execution, so Phase B's expressions referencing Phase A nodes (`$('Build_Slack_Questionnaire').first()...`) evaluate to `undefined`. No durable session state exists to re-hydrate from.

**Universal architectural gaps (all 4 reviewers, raised in ≥3 workflows):**

- No idempotency markers; re-runs re-embed, re-classify, re-cluster, re-append the same rows.
- LLM and SerpAPI calls fan out one-per-item with no batching, no retry, no rate-limit Wait nodes.
- Slack interactive cards block the response path (HITL, taxonomy alerts, Sheets-sync digest) when they should be fire-and-forget.
- Cost ceilings exist but ignore historical `api_cost_log` and ignore SerpAPI costs.

**Headline recommendation:** Do not redesign any workflow. Execute the optimization sprint described in §2 as surgical fixes plus four shared architectural additions described in §3. The shared additions (`SYS-Error-Handler`, `onboarding_sessions` table, `keyword_cluster_map` table, pagination helper Code node) unblock the majority of per-workflow fixes.

---

## 2. Consolidated System Shortcomings & Fixes (Per Workflow)

### 2.1 WF-ONBOARD — Client Onboarding (Phases A/B/C)

| # | Core Issue | Consensus | Technical Fix |
|---|---|---|---|
| O1 | Webhook trigger nodes used as wait/resume points. Each `wf-onboard-*` webhook starts a fresh execution; Phase B/C expressions reading Phase A nodes resolve to `undefined`. | **High (4/4)** | Keep three webhooks but persist all Phase A context to a new `onboarding_sessions` table keyed by `pipeline_run_id` (see §3.2). Phase B and Phase C must begin with `Fetch_Onboarding_Session` (GET on the session row) and reference only fields from that fetched row — never `$('<PhaseA_Node>').first()`. |
| O2 | No `onboarding_sessions` table; Phase A crawl results and LLM site analysis exist only in Phase A's execution log. | **High (4/4)** | Create `onboarding_sessions` (schema in §3.2). After `Aggregate_Page_Data` and `LLM_Site_Analysis`, write `crawled_pages`, `llm_site_analysis`, `competitors`, `seed_keywords`, `client_url`, `client_name`, `status='phase_a_complete'`. |
| O3 | `SplitInBatches_Pages` wired from output 0 (done) into `Crawl_Page`; no loop-back from `Extract_Page_Content` → `SplitInBatches_Pages`. Only first 5 of 20 pages crawl. | **High (4/4)** | Connect `SplitInBatches_Pages` output **1** → `Crawl_Page`. Loop `Extract_Page_Content` → `SplitInBatches_Pages` input. Connect `SplitInBatches_Pages` output **0** → `Aggregate_Page_Data`. |
| O4 | Phase A returns 200 only after Slack card is posted (10+ seconds). Caller times out; subsequent retry creates a duplicate `pipeline_runs` row. | **High (3/4)** | Move `Respond_OK` to fire immediately after `Create_Pipeline_Run` returning `{ pipeline_run_id }`. Use n8n's "Respond to Webhook: Immediately" mode; the rest of Phase A continues asynchronously. |
| O5 | Slack questionnaire posts `input` blocks inside a `chat.postMessage`. Slack input blocks only render inside **modals**, not channel messages — fields are non-editable. | **High (3/4)** | Replace `Send_Questionnaire_Card` with a Slack message containing an "Open Onboarding Form" button. Add new webhook `wf-onboard-modal-trigger` that handles the button click, fetches the session row, and calls Slack `views.open` with a modal pre-filled from `llm_site_analysis`. Modal submit_url → `wf-onboard-questionnaire-response`. Phase B parses `payload.view.state.values` and `payload.view.private_metadata.pipeline_run_id`. |
| O6 | `competitors[]`, `seed_keywords[]`, and `gold_examples` are received/built but never written to any Supabase table. | **High (3/4)** | After `Write_Niches` add: (a) `Write_Competitor_Brand_Names` HTTP POST to `competitor_brand_names`, (b) `Write_Gold_Examples` HTTP POST to `gold_examples` with `source='onboarding_llm_seed'`, (c) update `Build_DB_Writes` so `clients.config.competitors`, `clients.config.seed_keywords`, and `clients.config.gold_examples` are also set (denormalized for WF-02 fast-read). |
| O7 | WF-02 requires `pos_centroid` / `neg_centroid` gold examples; onboarding never collects them. | **High (3/4)** | Add two required modal sections: "5 keywords your ICP would search" (positive) and "5 keywords that look related but are not your ICP" (negative). Persist to `clients.config.gold_examples = { positive: [...], negative: [...] }`. |
| O8 | `Parse_Sitemap_XML` does not detect `<sitemapindex>` (WP default), does not dedupe, no fallback when sitemap is blocked. | **High (3/4)** | (a) Detect `<sitemapindex>`; if present, emit child `<loc>` URLs, fetch each, parse, concat. (b) Strip query/fragments, dedupe with `[...new Set(locs)]`. (c) If sitemap returns 0 URLs, fall back to a static path list `['/', '/services', '/about', '/case-studies']`. |
| O9 | `Fetch_Sitemap` and `Crawl_Page` have no `continueOnFail`. Any 5xx aborts onboarding; `pipeline_runs.status = running` forever. | **High (3/4)** | Set `options.continueOnFail = true` on both nodes. Route their error output to a `Log_Crawl_Error` Code node that writes a `pipeline_run_events` row, then loops back into the batch. |
| O10 | LLM calls (`LLM_Site_Analysis`, `LLM_CrossValidate`) have no retry on 429 and no JSON schema enforcement; one parse error halts Phase A. | **High (3/4)** | (a) Enable node retry: 3 attempts, exponential backoff (2s/4s/8s). (b) Add `response_format: { type: 'json_object' }`. (c) Wrap JSON parse in try/catch; on failure write a fallback row with `status='parse_error'` and continue. |
| O11 | `Build_DB_Writes` ignores `monthly_api_budget_usd` and `navigational_competitor_strategy` from the questionnaire — uses hardcoded defaults `$50` and `allow_comparison_only`. | **High (2/4 — single-model insight from one reviewer, validated against `sdk/wf-onboard.ts:Build_DB_Writes`)** | Read both fields from `q` (parsed questionnaire) into the `config` object: `monthly_api_budget_usd: q.monthly_api_budget_usd ?? 50, navigational_competitor_strategy: q.navigational_competitor_strategy ?? 'allow_comparison_only'`. |
| O12 | Client slug collision: `slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-')` will unique-violate for two clients with similar names. | **Single-Model Insight (1/4)** | Before insert, GET `clients?slug=eq.<slug>&select=id`. If exists, append `-<random4>` until free. |
| O13 | `cross_validation_events` table promised in the sticky note but never written. | **Single-Model Insight (1/4)** | After `Parse_CrossVal_Response` add POST to `cross_validation_events` with `client_id`, `pipeline_run_id`, `validation_result`, `had_flags`, `summary`. Write **always**, even when no flags raised (audit completeness). |
| O14 | Idempotent re-onboarding: if a `clients` row with the same `canonical_domain` exists, Phase C inserts a duplicate. | **High (2/4)** | In Phase C `Write_Client`, change to upsert: PATCH if `canonical_domain` matches; else INSERT. Use Supabase `Prefer: resolution=merge-duplicates` with `on_conflict=canonical_domain`. |

---

### 2.2 WF-00 — Page Inventory Sync

| # | Core Issue | Consensus | Technical Fix |
|---|---|---|---|
| 00-1 | **`Batch_Pages` SplitInBatches v3 mis-wired:** Output 0 (done) goes to `Fetch_Page_HTML`, and there is no loop-back from `Upsert_Page` → `Batch_Pages`. Only the first 10 pages are processed; the rest are silently dropped. | **High (4/4)** | Connect `Batch_Pages` output **1** (loop) → `Fetch_Page_HTML`. Connect `Upsert_Page` → `Batch_Pages` (loop-back input). Connect `Batch_Pages` output **0** (done) → new `Aggregate_Run` (Aggregate, mode "Combine") → `Complete_Run`. Delete the existing direct `Upsert_Page → Complete_Run` edge. |
| 00-2 | **`Complete_Run` fires per page** rather than once per client. Run is marked completed on first page; later failures invisible. | **High (4/4)** | Resolved by 00-1 (Complete_Run moves to done-branch of Batch_Pages). |
| 00-3 | **`Fetch_Page_HTML` has no per-page fault tolerance.** A single 404 or timeout aborts the whole client. | **High (4/4)** | Set `options.continueOnFail = true`. Route error output to `Log_Page_Fetch_Error` Code node that POSTs `{ client_id, page_url, error, run_id }` to `pipeline_run_events` (or sets `pages.crawl_status = 'error'`), then loop back into `Batch_Pages`. |
| 00-4 | **`Parse_Sitemap` does not handle sitemap-index files** (`<sitemapindex>`) — WP default. Workflow sees zero URLs for any WP client. Also does not dedupe despite comment claiming so. | **High (4/4)** | (a) Detect `<sitemapindex>`; emit child URLs; add `Fetch_Child_Sitemap` HTTP node + `Parse_Child_Sitemap` Code node. (b) Strip query/fragments. (c) `const uniqueLocs = [...new Set(locs)]`. |
| 00-5 | **Hardcoded WPGraphQL URL** `https://cms.webleymedia.com/graphql` for every client — every client's inventory polluted with Webley's blog. | **High (3/4)** | Replace with `={{ $json.client_config?.wp_graphql_url \|\| $env.WP_GRAPHQL_URL }}`. Wrap `Fetch_WP_Posts` in an `IF` gate: skip when `wp_graphql_url` is null. |
| 00-6 | **`Merge_Client_Run` cross-pollinates `pipeline_run_id` across clients** because it reads `$('Split_Clients').item.json` after `Create_Run` HTTP POST. In multi-client execution, paired-item association is not guaranteed. | **Single-Model Insight (1/4)** — validated against `wf-00-page-inventory.json` | Replace the Code-based Merge_Client_Run with a proper `Merge` node (mode "Combine by position", inputs: `Split_Clients` and `Create_Run`). Recompute `pipeline_run_id` from the merged item, not via `$('Split_Clients').item.json`. |
| 00-7 | **No idempotency.** Every nightly run re-embeds every page (~$0.00002 × 200 URLs × N clients × 365). | **High (2/4)** | Before `Embed_Page`, insert `Lookup_Existing_Page` (GET `pages?client_id=eq.X&url_path=eq.Y&select=last_seen_at,content_hash`) + `IF`. If `last_seen_at > now() - 20h` AND `sha256(text_for_embedding) === existing.content_hash`, skip to a `Touch_Last_Seen` PATCH; else continue. Store `content_hash` on the upsert. |
| 00-8 | No global error path: failures leave `pipeline_runs.status = running` forever. | **High (3/4)** | Attach `SYS-Error-Handler` Error Workflow (see §3.1) via Workflow Settings → Error Workflow. |

---

### 2.3 WF-01 — CSV Keyword Ingest

| # | Core Issue | Consensus | Technical Fix |
|---|---|---|---|
| 01-1 | **`Respond_Ingest` and `Complete_Ingest_Run` fire inside the chunk loop.** First chunk completes the run; subsequent failures invisible; webhook caller gets a multi-respond warning. | **High (4/4)** | Move `Respond_Ingest` to fire immediately after `Validate_Ingest_Payload` with `{ ok: true, status: 'processing', pipeline_run_id }`. After the chunked insert, place an `Aggregate` node that waits for all chunks, then `Complete_Ingest_Run` runs exactly once. |
| 01-2 | **`Fetch_Existing_Keywords` `Range: 0-49999` hard cap.** Clients with >50k existing keywords get duplicate inserts. | **High (4/4)** | **Push dedupe to the database (Conflict Resolution Decision — see §4.1).** Replace the client-side fetch + filter Code node with: (a) a unique constraint `CREATE UNIQUE INDEX raw_keywords_client_keyword_uniq ON raw_keywords (client_id, lower(keyword));` and (b) bulk insert with `Prefer: resolution=merge-duplicates` + `on_conflict=client_id,keyword`. Keep `Fetch_Graveyard` as a small one-page lookup for the explicit graveyard exclusion. |
| 01-3 | **Graveyard dedupe is dead code.** `graveyard_ids` Set is built but `Dedupe_Keywords` only filters against `existingSet`. | **High (4/4)** | Either: (a) modify `Dedupe_Keywords` to filter against both Sets, OR (b) move graveyard exclusion to a Supabase RPC `check_keyword_exists_or_graveyard(p_client_id, p_keywords[])`. Recommend (b) for scalability. |
| 01-4 | **Custom CSV parser breaks on RFC4180 edge cases:** quoted commas, escaped quotes (`""`), multi-line quoted fields, BOM. | **High (3/4)** | Replace the regex parser with n8n's built-in `Spreadsheet File` node (operation: "Read from file", `inputDataFieldName: csv_content`, `options.headerRow: true`). Keep a thin Code node only for trim/lowercase/number coercion. |
| 01-5 | **No client existence check.** Bad `client_id` produces an FK violation surfaced as a generic 500. | **High (2/4)** | After parsing, add `Verify_Client` GET `clients?id=eq.{{client_id}}&select=id`; `IF` empty → respond 400. |
| 01-6 | **No `pipeline_run_id` propagation; no downstream chain to WF-02.** | **High (2/4)** | Accept optional `pipeline_run_id` and `chain_next` in the webhook contract (default `chain_next=true`). If `pipeline_run_id` absent, create one. After successful `Complete_Ingest_Run`, POST `/webhook/wf-02-filter` with `{ client_id, pipeline_run_id }` when `chain_next === true`. |
| 01-7 | **Base64 detection heuristic `!csv_content.includes(',')` produces false positives for single-column CSVs.** | **Single-Model Insight (1/4)** | Require explicit `csv_encoding: 'base64' \| 'plain'` in payload (default `'plain'`). Reject the heuristic. |
| 01-8 | **No payload size guard.** A 5 MB CSV pasted into JSON balloons memory after parse. | **Single-Model Insight (1/4)** | At top of `Validate_Ingest_Payload`, reject if `csv_content.length > 5_000_000` with a 413 response. |

---

### 2.4 WF-02 — Tiered Keyword Filter

| # | Core Issue | Consensus | Technical Fix |
|---|---|---|---|
| 02-1 | **Tier 1 `passed` and `rejected` decisions never reach `keyword_classifications`.** Only borderline → Tier-2 results are persisted. 60–80% of throughput silently dropped. | **High (3/4)** — **CRITICAL CORRECTNESS BUG** | After `Score_Tier1`, add `Build_Tier1_Classification_Rows` Code node that emits classification rows for both `passed_tier1` and `rejected_tier1` arrays (with `decided_by='tier1_embedding'`, `pos_score`, `neg_score`, `embedding`, `pipeline_run_id`). Add `Write_Tier1_Classifications` bulk HTTP POST. This runs **in parallel** with the borderline path, not instead. |
| 02-2 | **Tier 0 does not gate Tier 1.** `Tier0_Regex_Filter` runs in parallel with `Fetch_Unclassified_Keywords`; rows rejected by Tier 0 are still embedded in Tier 1. Race condition. | **High (4/4)** | Restructure the graph: `Merge_Client_Config` → `Tier0a_Regex_Filter` → `Tier0b_Competitor_Filter` → fan-out to `Fetch_Unclassified_Keywords` and `Fetch_Gold_Examples`. Either (a) modify Tier 0 RPCs to set `raw_keywords.status = 'tier0_rejected'` so existing `status=eq.raw` filter excludes them, OR (b) introduce `fetch_pending_for_tier1(p_client_id, p_limit)` RPC that LEFT JOINs `keyword_classifications`. Recommend (b) — more maintainable, no schema drift on `raw_keywords`. |
| 02-3 | **`Batch_For_Embedding` SplitInBatches mis-wired** (output 0 vs output 1) and downstream references `$json.batchIndex` which is not produced. | **High (3/4)** | (a) Restructure `Prepare_Tier1` to output one item per embedding chunk: `{ chunk_index, chunk_offset, keywords[], keyword_ids[], pos_centroid, neg_centroid, ... }`. (b) Connect SplitInBatches output **1** → `Embed_Keywords_Batch`. (c) Update `Score_Tier1` to index `keyword_ids[i]` from the **current chunk**, not `Prepare_Tier1.first()`. (d) Loop `Score_Tier1` → `Batch_For_Embedding`; output **0** → final aggregation. |
| 02-4 | **Slack HITL card blocks `Respond_Filter`.** A Slack 429 delays the webhook response and breaks WF-01 → WF-02 chain. | **High (4/4)** | Make `Send_HITL_Card` a fire-and-forget branch — it does NOT continue to `Respond_Filter`. Both branches of `IF_Needs_HITL` must reach `Respond_Filter` through a separate path. |
| 02-5 | **500-keyword cap with no continuation** for larger ingests. | **High (3/4)** | Wrap `Fetch_Unclassified_Keywords → Call_Tier1 → Flatten → (writes)` in an offset-driven SplitInBatches. After each batch, fetch the next 500; stop when fetch returns < 500. Remove the hardcoded `Range: 0-49999` in favor of paged 500-row windows. |
| 02-6 | **Gold examples not validated up front.** If `clients.config.gold_examples` is empty, Tier 1 silently returns degraded scores and every keyword lands in `borderline`. | **High (3/4)** | After `Validate_Input`, add `Fetch_Gold_Examples_Precheck`. If empty → branch to `Respond_Filter_Skipped` returning 422 "gold examples missing — re-run onboarding". |
| 02-7 | **Tier 2 LLM has no batching, no rate limit, no retry, no JSON schema enforcement.** | **High (4/4)** | Insert `Split_In_Batches_T2` (batch size 5–25, prefer **5 sequential per batch with parallel processing inside a single LLM call** — see §4.2). Use n8n node retry: 3 attempts, exponential backoff. Add `response_format: { type: 'json_object' }`. Wrap `Prepare_T2_Write` parse in try/catch; on parse failure write `decision='parse_error'` with raw response in `notes`. |
| 02-8 | **`pipeline_run_id` accepted but never written on classification rows.** | **High (3/4)** | Plumb `pipeline_run_id` through `Validate_Input` into every `keyword_classifications` POST body (Tier 1 and Tier 2). |
| 02-9 | **No idempotency on re-runs.** Tier 1 fetch re-reads already-classified rows because filter is only `status=raw`. | **High (3/4)** | The fetch RPC from 02-2 (b) must `EXCLUDE keyword_id IN (SELECT keyword_id FROM keyword_classifications WHERE client_id = ?)`. |
| 02-10 | **`Write_Classification` uses `Prefer: return=minimal`**, so Slack button payloads cannot carry the actual classification row ID. | **Single-Model Insight (1/4)** | Change to `Prefer: return=representation` for Tier 2 writes feeding HITL cards. |
| 02-11 | **Cosine function duplicated** in `Prepare_Tier1` and `Score_Tier1`. | **Single-Model Insight (1/4)** | Compute similarity in a single node (`Score_Tier1`), or extract to a shared workflow if other workflows ever need it. Defer; cosmetic. |

---

### 2.5 WF-03 — Clustering + 3-Axis Labeling

| # | Core Issue | Consensus | Technical Fix |
|---|---|---|---|
| 03-1 | **`keyword_cluster_map` is never written.** Cluster headers are inserted but the keyword↔cluster relationship is lost. WF-04 SerpAPI, WF-05 Sheets cannot reconstruct membership. | **High (4/4)** | Create table if missing (see §3.3). After `Write_Cluster` returns the inserted cluster `id`, add `Merge_Cluster_Context` Code node that pairs the inserted ID with `member_ids`, then `Build_Map_Rows` emits `{ cluster_id, keyword_classification_id, pipeline_run_id, client_id }` per member, then `Bulk_Insert_Cluster_Map` HTTP POST. |
| 03-2 | **Context loss after `Fetch_Passed_Classifications`** and after `Write_Cluster`. `$json.client_id` is `undefined` because PostgREST returns arrays; `IF_Needs_Taxonomy_Review` checks `$json.needs_taxonomy_review` which is overwritten by the Supabase insert response. | **High (4/4)** | (a) Add `Merge_Client_Context` Code node after `Fetch_Client` that re-attaches `client_id` and `pipeline_run_id` from `Validate_Cluster_Payload`. (b) Add `Merge_Cluster_Context` after `Write_Cluster` that re-attaches `needs_taxonomy_review`, `label`, `head_term`, `confidence` from before the write. (c) Move `IF_Needs_Taxonomy_Review` after the merge. |
| 03-3 | **`Respond_Cluster` fires per cluster.** Multi-respond warnings; only first reaches caller. | **High (4/4)** | Place `Respond_Cluster` after an `Aggregate` node that waits for all per-cluster writes. Fires exactly once with `{ ok: true, clusters_written, taxonomy_suggestions_written }`. |
| 03-4 | **`Send_Taxonomy_Suggestion` blocks the webhook response.** | **High (3/4)** | Same pattern as 02-4 — Slack post is a side branch terminating in noop; not on the response path. |
| 03-5 | **Per-cluster LLM labeling with no batching, no retry, no rate-limit.** N clusters = N sequential OpenRouter calls. | **High (4/4)** | Wrap `LLM_Label_Cluster` in `Split_In_Batches` (size 3). Enable retry 3× with exponential backoff (2s/4s/8s). Add `response_format: { type: 'json_object' }`. Wrap parse in try/catch; fallback label = `keywords[0].keyword + ' (unlabeled)'`. **Future:** batch 10–15 clusters into one LLM call (see §3.4). |
| 03-6 | **Cannibalization check declared in sticky note but not implemented.** No node queries `pages.embedding`. | **High (4/4)** — **Conflict (see §4.3)** | **Resolution: defer behind a feature flag.** Add `clients.config.cannibalization_enabled` (default false). When true, after `Parse_LLM_Label`, call a new Supabase RPC `find_cannibalization_candidates(p_client_id, p_centroid vector, p_threshold float)` using pgvector cosine on `pages.embedding`. Set `keyword_clusters.cannibalization_risk_page_id` from top hit if similarity > threshold (default 0.82, from `clients.config.cannibalization_threshold`). |
| 03-7 | **Hardcoded Railway worker URL.** No env var indirection. | **High (3/4)** | Change `Call_Python_Worker.url` to `={{ $env.PYTHON_WORKER_URL }}/cluster`. |
| 03-8 | **Worker response schema not validated.** A field rename (e.g. `head_keyword` vs `head_term`) silently produces empty clusters. | **High (2/4)** | In `Parse_Worker_Response`, throw a controlled error if `response.clusters` is not an array or if first cluster lacks required keys (`cluster_id`, `member_ids`). |
| 03-9 | **Single-member / noise (`cluster_id === -1`) clusters still hit the LLM.** | **High (2/4)** | After `Parse_Worker_Response`, `IF (cluster_id === -1 OR keywords.length < 2)` → write a thin row with `label = keywords[0].keyword`, `confidence = 'low'`, skip LLM. |
| 03-10 | **No `pipeline_run_id` on `keyword_clusters` or `keyword_cluster_map` writes.** | **High (3/4)** | Plumb into both insert payloads. |
| 03-11 | **No idempotency.** Re-runs duplicate cluster rows. | **High (2/4)** | Before `Build_Cluster_Payload`, GET `keyword_clusters?client_id=eq.X&pipeline_run_id=eq.Y`. If non-empty, respond 200 with `{ skipped: true }`. |
| 03-12 | **`Fetch_Passed_Classifications` 1000-row default page size; no pagination.** | **High (3/4)** | Paged loop with `Range: 0-999`, `1000-1999`, ... stop when page < 1000. Concatenate into worker payload. |
| 03-13 | **Worker payload missing keyword text** (only id + embedding). If worker doesn't re-fetch, head-term derivation is unreliable. | **Single-Model Insight (1/4)** | Include `keyword` (and optionally `volume`, `kd`) in each worker payload item. |

---

### 2.6 WF-04 — ICP Scoring + Priority

| # | Core Issue | Consensus | Technical Fix |
|---|---|---|---|
| 04-1 | **`Update_Cluster_Score` PATCHes only `priority_score`.** `icp_match_score`, `commercial_intent_weight`, reasoning fields, and `scored_at` are computed but discarded. | **High (4/4)** | PATCH body must include: `priority_score, icp_match_score, commercial_intent_weight, icp_match_reasoning, commercial_reasoning, serp_intent_signals, scoring_inputs, scored_at, last_pipeline_run_id`. |
| 04-2 | **Priority formula uses `keyword_count` as a proxy for volume and hardcodes `avgKd = 0`.** A cluster of 50 low-volume keywords beats 3 high-volume keywords. KD penalty term `- (avgKd * 0.5)` always zero. | **High (4/4)** — **Conflict (see §4.2)** | **Resolution: upgrade to real volume/KD now.** Modify WF-03's `Build_Map_Rows` to also write `total_volume` (SUM) and `avg_kd` (AVG) onto the `keyword_clusters` row at insert time (via a Supabase trigger or in `Write_Cluster` payload using values aggregated from `keyword_cluster_map ⨝ raw_keywords`). WF-04 `Compute_Priority_Score` then uses `ctx.total_volume` and `ctx.avg_kd`. Lock the canonical formula in `WF-04.md`. |
| 04-3 | **`Respond_Score` fires per cluster.** Multi-respond warnings. | **High (4/4)** | After all per-cluster PATCHes, place `Aggregate` → `Respond_Score` exactly once with `{ ok: true, scored: N, skipped: M, total_cost_usd }`. |
| 04-4 | **`encodeURIComponent` used inside an n8n expression.** n8n's expression engine does not expose `encodeURIComponent`; the SerpAPI URL becomes `undefined`. | **Single-Model Insight (1/4)** — **VALIDATED, CRITICAL** | In `Check_Cost_Ceiling` (or a preceding Code node), compute `encoded_query = encodeURIComponent(item.head_term)`. In `SerpAPI_Search` URL use `{{ $json.encoded_query }}`. |
| 04-5 | **SerpAPI and LLM calls one-per-cluster, no batching, no retry, no rate-limit Wait.** 100 clusters × 2 calls = 200 sequential round-trips. | **High (4/4)** | (a) Wrap `Fetch_SERP_Data` in `Split_In_Batches` (size 5) with `Wait` 1s between. Enable node retry 3× (5s/15s/45s). Set `continueOnFail = true`; on failure write synthetic empty SERP so LLM can still score on label+keywords. (b) Same pattern for `LLM_ICP_Score` (batch size 3). |
| 04-6 | **Cost ceiling is naive.** `$0.005 × clusters > $50` blocks at 10k clusters but ignores SerpAPI cost ($0.003+) and doesn't query historical `api_cost_log`. | **High (3/4)** | Before SerpAPI, GET `api_cost_log?client_id=eq.X&created_at=gte.<month_start>&select=cost_usd`. Sum + run estimate (`serpCost = clustersToScore * 0.03` + `llmCost = clustersToScore * 0.002`). If total > `clients.config.monthly_api_budget_usd` (default $50), respond 402 and PATCH `pipeline_runs.status = budget_exceeded`. **Graceful degradation:** process the largest subset that fits the budget rather than throw. |
| 04-7 | **100-cluster hard cap.** Redundant with the budget guard once 04-6 is fixed. | **High (3/4)** | Remove `Math.min(100, clusters.length)`. Process all clusters within budget. |
| 04-8 | **Label fallback missing.** If LLM-generated cluster label is "Untitled" or weak, SerpAPI returns junk. | **High (2/4)** | Before SerpAPI: `query = (label && label !== 'Untitled') ? label : top_keyword_text`. Fetch `top_keyword_text` via a single upfront Supabase call joining `keyword_cluster_map ⨝ raw_keywords` `ORDER BY volume DESC LIMIT 1` per cluster. |
| 04-9 | **Idempotency gate ambiguous.** Doc says `icp_score IS NULL`; partial-run safety wants `scored_at IS NULL`. | **High (2/4)** | Canonical filter: `scored_at=is.null`. Update `WF-04.md` to match. |
| 04-10 | **SerpAPI cost not logged.** `Log_API_Cost` only writes OpenRouter cost. | **High (2/4)** | After successful `Fetch_SERP_Data`, POST `api_cost_log` with `provider='serpapi'`, `cost_usd=<plan_rate>`, `workflow='wf-04-icp-score'`, `client_id`, `pipeline_run_id`. |
| 04-11 | **Context loss after `Fetch_Client_And_Clusters`** (PostgREST array). `client_id` may be lost on each per-cluster item. | **High (3/4)** | Add `Merge_Client_Context` Code node that flattens the array to one item per cluster carrying `{ client_id, pipeline_run_id, cluster_id, label, keyword_count, total_volume, avg_kd, top_keyword_text }`. |
| 04-12 | **Empty-state respond missing.** When no unscored clusters, `Respond_Score` may not fire. | **Single-Model Insight (1/4)** | After fetch, `IF (clusters.length === 0)` → respond `{ ok: true, status: 'no_unscored_clusters' }`. |

---

### 2.7 WF-05 — Nightly Google Sheets Sync

| # | Core Issue | Consensus | Technical Fix |
|---|---|---|---|
| 05-1 | **Race condition / cross-client data bleed via `.first()` and parallel fan-out.** `Build_Sheet_Data` reads `$('Fetch_Client_Clusters').first()` etc., always returning client[0]'s data regardless of which client is being processed. | **High (4/4)** | Insert `Split_In_Batches_Clients` (size 1) right after `Fetch_Active_Clients`. Every node downstream reads `$('Split_In_Batches_Clients').item.json` for the current client. Loop back from end of each iteration. Chain the three fetches **sequentially** (`Fetch_Client_Clusters` → `Fetch_Taxonomy_Suggestions` → `Fetch_API_Costs`) rather than in parallel; eliminates the multi-input-merge race. |
| 05-2 | **Only the Cost tab is written.** `pillar_tabs`, `themes_rows`, `tax_rows` are built in `Build_Sheet_Data` but no Google Sheets node writes them. | **High (4/4)** — **Conflict (see §4.4)** | **Resolution: lock contract to `Clusters` + `Cost` tabs only; defer the rest.** Update `WF-05.md` and remove `pillar_tabs`, `themes_rows`, `tax_rows` from `Build_Sheet_Data`. If reporting later demands `Themes` / `Taxonomy-Suggestions` / per-pillar tabs, re-add in a v2 sprint. |
| 05-3 | **Sheets append is not idempotent.** Every nightly run appends ALL 500 clusters again; after 30 nights the tab has 30× duplicate rows. | **High (3/4)** | Switch to a **delta-append + dedupe** strategy: (a) add `Cluster_Synced_At` column; (b) Supabase fetch filter `scored_at=gt.<last_sync>`; (c) track `last_sheet_sync_at` on `clients` (PATCH after sync). For Cost tab, use a deterministic `(provider, date)` key with `appendOrUpdate` mode and unique column `provider_date`. |
| 05-4 | **Slack summary may report wrong client** because `Build_Summary` reads `Fetch_Active_Clients.first()`. | **High (2/4)** | Inside the per-client loop, read `$('Split_In_Batches_Clients').item.json.name`. Aggregate per-iteration `{ client_name, cluster_count, cost_usd, top3 }`. After the loop, send **one** Block Kit digest naming all clients with their counts. |
| 05-5 | **Slack notification fires for unconfigured clients** ("sync complete" with 0 data). | **High (2/4)** | Inside loop, if `Build_Sheet_Rows.length === 0` OR `sheets_view_id` is null, push to a `skipped[]` array; skip Sheets write. The final digest mentions skipped clients separately ("M clients skipped — no sheets_view_id configured"). |
| 05-6 | **`Fetch_API_Costs` time window unclear** ("last 200 rows" is volume-based). | **High (2/4)** | Change filter to `created_at=gte.<now - 24h>`. Remove 200-row cap. |
| 05-7 | **No global error path.** Cron failures invisible — no `pipeline_runs` row created. | **High (3/4)** | At top, create `pipeline_runs` row with `kind='sheet_sync'`. PATCH `completed` after the loop; on error via `SYS-Error-Handler` PATCH `failed`. |
| 05-8 | **Parallel fetches have no error isolation.** If `Fetch_Taxonomy_Suggestions` fails, `Build_Sheet_Data` may fail entirely. | **High (2/4)** | Set `continueOnFail = true` on each fetch. In `Build_Sheet_Data`, default missing inputs to `[]` before use. |
| 05-9 | **Hardcoded Slack channel ID `C0B43A7QG5P`.** | **Single-Model Insight (1/4)** | Replace with `{{ $json.client_config?.hitl_channels?.[0] \|\| $env.SLACK_HITL_CHANNEL }}`. |
| 05-10 | **No pagination on `Fetch_Client_Clusters` / `Fetch_Taxonomy_Suggestions`** (default 1000-row page). | **High (3/4)** | Apply paged Range loop pattern. Stop when page < 1000. |

---

## 3. Architecture & Scalability Suggestions (Cross-Workflow)

These are the **shared additions** that unblock the majority of per-workflow fixes and prevent the same defects from recurring as the system grows. Implement these **first**; the per-workflow patches in §2 depend on them.

### 3.1 SYS-Error-Handler (Global Error Workflow)

A new top-level workflow `SYS-Error-Handler` triggered by **n8n Error Trigger** node. On any uncaught exception in any of the seven workflows, it:

1. Receives `$execution.error` and `$execution.workflowData.id`.
2. Extracts in-flight `pipeline_run_id` from `$execution.data.executionData` (or from the originating webhook payload if recoverable).
3. PATCHes `pipeline_runs` set `status='failed'`, `error_message=<truncated stack>`, `failed_at=now()`.
4. Posts a Slack alert to `$env.SLACK_OPS_CHANNEL` with workflow name, error class, and a deep link to the execution.
5. (For WF-ONBOARD only) Also PATCHes `onboarding_sessions.status='failed'`.

**Bind via Workflow Settings → Error Workflow → `SYS-Error-Handler`** on all seven workflows.

### 3.2 `onboarding_sessions` Table (Phase-State Persistence)

```sql
CREATE TABLE onboarding_sessions (
  pipeline_run_id uuid PRIMARY KEY REFERENCES pipeline_runs(id),
  client_url text NOT NULL,
  client_name text NOT NULL,
  competitors text[] DEFAULT '{}',
  seed_keywords text[] DEFAULT '{}',
  crawled_pages jsonb DEFAULT '[]',
  llm_site_analysis jsonb,
  questionnaire_response jsonb,
  cross_validation jsonb,
  status text DEFAULT 'phase_a',
    -- valid: phase_a, phase_a_complete, awaiting_questionnaire,
    --        phase_b_complete, awaiting_flag_ack, completed, failed
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
```

Phase A writes after `LLM_Site_Analysis`. Phase B re-hydrates on first node. Phase C re-hydrates on first node. Slack modal `private_metadata` carries `pipeline_run_id` as the only handle between phases.

### 3.3 `keyword_cluster_map` Table (Cluster Membership)

```sql
CREATE TABLE IF NOT EXISTS keyword_cluster_map (
  cluster_id uuid NOT NULL REFERENCES keyword_clusters(id) ON DELETE CASCADE,
  keyword_classification_id uuid NOT NULL REFERENCES keyword_classifications(id) ON DELETE CASCADE,
  client_id uuid NOT NULL,
  pipeline_run_id uuid,
  PRIMARY KEY (cluster_id, keyword_classification_id)
);
CREATE INDEX keyword_cluster_map_client_idx ON keyword_cluster_map(client_id);
CREATE INDEX keyword_cluster_map_classification_idx ON keyword_cluster_map(keyword_classification_id);
```

Also add to `keyword_clusters`:

```sql
ALTER TABLE keyword_clusters
  ADD COLUMN IF NOT EXISTS worker_cluster_id int,
  ADD COLUMN IF NOT EXISTS pipeline_run_id uuid,
  ADD COLUMN IF NOT EXISTS total_volume bigint,
  ADD COLUMN IF NOT EXISTS avg_kd numeric;
```

### 3.4 Universal LLM Call Pattern

Standardize across WF-02 Tier 2, WF-03 LLM_Label, WF-04 LLM_ICP_Score, WF-ONBOARD LLM_Site_Analysis and LLM_CrossValidate:

- **Wrap in `Split_In_Batches`** (batch size 3–5).
- **Enable node retry:** 3 attempts, exponential backoff (n8n built-in: 2s base, 2× multiplier).
- **Set `response_format: { type: 'json_object' }`** on the body.
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
- Write `pipeline_run_id` on every row insert (`keyword_classifications`, `keyword_clusters`, `keyword_cluster_map`, `pages`, `api_cost_log`).
- Before doing expensive work, check whether a row with the same `(client_id, pipeline_run_id)` already exists; if so, respond 200 with `{ skipped: true, reason: 'idempotent_replay' }`.

### 3.8 PostgREST Response Unwrap Convention

Every HTTP node fetching a single row from Supabase that downstream expressions treat as `$json.<field>` must either:

- Send header `Accept: application/vnd.pgrst.object+json` (PostgREST single-object mode), OR
- Be followed by a `Merge_<context>` Code node that explicitly unwraps `items[0]` and re-attaches needed fields.

This eliminates the entire class of "context loss after fetch" bugs observed in WF-02, WF-03, WF-04.

### 3.9 Environment Variables (Standardize)

Move every hardcoded URL behind `$env`:

| Variable | Replaces |
|---|---|
| `PYTHON_WORKER_URL` | Railway hardcoded URL in WF-03 |
| `WP_GRAPHQL_URL` | `cms.webleymedia.com/graphql` in WF-00 |
| `SLACK_HITL_CHANNEL` | Hardcoded channel `C0B43A7QG5P` in WF-05 |
| `SLACK_OPS_CHANNEL` | New, used by `SYS-Error-Handler` |
| `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` | Already standardized — keep. |

---

## 4. Conflict Log

Reviewers disagreed on four substantive architectural choices. Each conflict was resolved using the **Scalability > Maintainability > Execution Speed** hierarchy.

### 4.1 WF-01 Deduplication: Client-side fetch vs. Database constraint

**Conflict:**
- Reviewer A (paginate the client-side fetch + filter): retains visibility into "skipped" vs "inserted" counts; explicit dedupe logic in n8n; easy debugging.
- Reviewer B/C/D (push dedupe to Supabase via `UNIQUE INDEX (client_id, lower(keyword))` + `Prefer: resolution=merge-duplicates`): eliminates the 50k cap entirely; database enforces correctness regardless of n8n logic; reduces n8n memory footprint.

**Decision: Database-side dedupe via unique index + `merge-duplicates`.**

**Justification:**
- **Scalability (decisive):** Client-side dedupe is bounded by n8n worker memory and the 50k Range cap; database dedupe scales to any cardinality.
- **Maintainability:** A single SQL constraint is the source of truth; future workflows that touch `raw_keywords` cannot accidentally create duplicates regardless of their code.
- **Execution speed:** Database-side is also faster (one round-trip, one index lookup per row).
- **Trade-off accepted:** Loss of granular "inserted vs skipped" counts. Mitigation: log a per-chunk count of `inserted` rows from the Supabase response and approximate `skipped = chunk_size - inserted`.

### 4.2 WF-04 Priority Score: Keep proxy vs. Upgrade to real Volume/KD

**Conflict:**
- Reviewer A (keep deployed placeholder formula: `volume_norm = keyword_count/100`, `KD = 0.20` literal): minimizes ripple changes; ships faster; matches the existing `WF-04.md` docs.
- Reviewer B/C/D (upgrade to `total_volume` SUM and `avg_kd` AVG via `keyword_cluster_map ⨝ raw_keywords`): produces an accurate priority score that correctly weights high-volume clusters; aligns with the product intent stated in `WF-04.md`.

**Decision: Upgrade to real `total_volume` / `avg_kd`, rolled up at WF-03 cluster-write time.**

**Justification:**
- **Scalability (decisive):** The proxy formula produces inverted rankings as the keyword corpus grows (many small clusters outrank few large ones). At 10k+ keywords per client, the placeholder makes WF-04 actively misleading.
- **Maintainability:** A formula that matches the documented formula is easier to reason about; the proxy requires a "why is it like this?" footnote forever.
- **Execution speed:** Rolling up at WF-03's `Write_Cluster` payload (using `SUM/AVG` over the in-memory `member_ids` join) costs one extra Supabase query per cluster — negligible.
- **Implementation order:** This change is dependent on §3.3 (`keyword_cluster_map` table) being in place. Lock the formula in `WF-04.md` once shipped.

### 4.3 WF-03 Cannibalization Check: Ship now vs. Defer

**Conflict:**
- Reviewer A (defer to a separate `WF-03-Post-Process` workflow): keeps WF-03 lean; cannibalization can mature independently.
- Reviewer B/C (ship now using pgvector cosine against `pages.embedding`): the sticky note already promises it; users expect it.
- Reviewer D (delete the promise from docs entirely): if it isn't shipping, don't claim it.

**Decision: Ship behind a `clients.config.cannibalization_enabled` feature flag (default `false`), implemented via the pgvector RPC `find_cannibalization_candidates`.**

**Justification:**
- **Scalability (decisive):** A feature flag lets us pilot on one or two clients before rolling out; the pgvector RPC offloads the math to Postgres and is O(log n) on the page set.
- **Maintainability:** A flag preserves the architectural intent expressed in the sticky note while preventing untested code from running for clients who don't need it. We avoid the "promise without delivery" anti-pattern (Reviewer D's concern) and the "added complexity for no benefit" anti-pattern (Reviewer A's concern).
- **Execution speed:** When disabled, zero cost. When enabled, one Supabase RPC per cluster with an index-backed similarity query — sub-50ms.
- **Dependency:** WF-00 must be correctly populating `pages.embedding` (see 00-1 through 00-7) before this is useful.

### 4.4 WF-05 Sheets Tab Contract: Multi-tab vs. Minimal

**Conflict:**
- Reviewer A (implement all promised tabs: Clusters, Per-Pillar, Themes, Taxonomy-Suggestions, Cost, Audit, Cross-Val): completes the sticky-note contract.
- Reviewer B/C/D (lock to `Clusters` + `Cost` only; defer the rest): minimizes scope and risk; per-pillar tabs are speculative until stakeholders ask for them.

**Decision: Lock the contract to `Clusters` + `Cost` tabs only for this sprint.**

**Justification:**
- **Scalability (decisive):** Multi-tab writes amplify Sheets API quota usage (each tab = at least one read + one write per night per client). With 10 clients and 7 tabs, that's 140 Sheets operations nightly — well within free tier today but linear-scaling toward the quota wall. Two tabs (20 ops) buys 7× headroom.
- **Maintainability:** Locking the contract eliminates the doc/export disagreement that all four reviewers flagged. The `pillar_tabs`, `themes_rows`, `tax_rows` data structures are removed from `Build_Sheet_Data` entirely, simplifying the Code node.
- **Execution speed:** Fewer writes = faster nightly job.
- **Re-introduction plan:** If a stakeholder requests Themes or Taxonomy tabs in a future sprint, the data already exists in Supabase — add the writer nodes then. Do not pre-build.

---

## 5. Implementation Sequencing (Recommended Sprint Order)

The fixes have cross-dependencies; executing in the order below avoids re-work.

**Wave 1 — Foundations (do these first, in parallel):**
- 3.1 `SYS-Error-Handler` workflow + bind to all seven workflows.
- 3.2 `onboarding_sessions` table.
- 3.3 `keyword_cluster_map` table + `keyword_clusters` ALTER (adds `total_volume`, `avg_kd`, `pipeline_run_id`).
- 3.9 Environment variables (`PYTHON_WORKER_URL`, `WP_GRAPHQL_URL`, `SLACK_HITL_CHANNEL`, `SLACK_OPS_CHANNEL`).
- DB unique index for WF-01 (`raw_keywords (client_id, lower(keyword))`).

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
- WF-05: 05-1 (per-client loop), 05-2 (lock to 2 tabs), 05-3 (delta append).

**Wave 4 — Polish & idempotency:**
- §3.7 idempotency markers across all writers.
- WF-00 00-5, 00-6, 00-7 (WPGraphQL config, paired-item fix, embedding cache).
- WF-01 01-4, 01-5, 01-6, 01-7, 01-8 (parser, client check, chain WF-02, base64 explicit, payload guard).
- WF-02 02-6, 02-8, 02-9, 02-10 (gold examples precheck, run_id, idempotency, return=representation).
- WF-03 03-6 (cannibalization behind flag), 03-7..03-13.
- WF-04 04-4 (encodeURIComponent — small but critical), 04-6 through 04-12.
- WF-ONBOARD O6..O14.

**Wave 5 — Validation:**
- Smoke test each workflow with the test scenarios in each `Execution Plan` (per §2).
- End-to-end: WF-ONBOARD → WF-01 → WF-02 → WF-03 → WF-04 → confirm `pipeline_run_id` traces a single client from CSV upload to scored cluster row to Sheets-synced row.
- Chaos test: kill the Python worker mid-WF-03; verify `SYS-Error-Handler` PATCHes the run to `failed` and posts to Slack ops channel.

**Wave 6 — Voice & content-skill foundation (see §7):**
- Create `system_prompts` Supabase table and load the `human-written-blog` skill as `name='human-written-blog', version=1, is_active=true`.
- Apply the skill selectively to the four prose-producing LLM prompts identified in §7.2 (Slack questionnaire prose, completion digest, taxonomy-suggestion message, sync-summary copy). **Do not** apply it to structured-JSON producers.
- Scaffold WF-06 (`Content Draft from Cluster`) as a separate workflow stub — full implementation deferred to a follow-up sprint once the upstream pipeline (WF-01 through WF-04) is producing reliable cluster output.

---

## 6. Appendix — Per-Reviewer Coverage Matrix

| Workflow | Reviewer A | Reviewer B | Reviewer C | Reviewer D |
|---|---|---|---|---|
| WF-ONBOARD | 14 issues | 3 issues | 10 issues | 10 issues |
| WF-00 | 11 issues | 3 issues | 7 issues | 6 issues |
| WF-01 | 9 issues | 4 issues | 6 issues | 6 issues |
| WF-02 | 11 issues | 4 issues | 9 issues | 7 issues |
| WF-03 | 12 issues | 3 issues | 9 issues | 7 issues |
| WF-04 | 11 issues | 3 issues | 8 issues | 7 issues |
| WF-05 | 11 issues | 2 issues | 7 issues | 7 issues |

Reviewer A's reports were the most exhaustive per workflow; Reviewer B's were the most terse but identified the highest-impact issues with high precision; Reviewers C and D landed in between with strong corroboration on the same critical defects. **The consensus across four independent passes makes the issues catalogued in §2 high-confidence and ready for execution.**

---

## 7. Voice & Content-Skill Integration

This section incorporates the `human-written-blog` skill (located at `SEO-Tools/n8n-workflows/skills-to-add/skill/human-written-skill.md`) into the workflow ecosystem. The skill is a long-form system prompt that forces LLM output to read like a human SEO writer instead of a chatbot: it bans roughly 200 AI-tell words/phrases, mandates varied rhythm and sentence-case headings, requires concrete specifics over vague generalities, and forbids decorative typography (em dashes, smart quotes, decorative bullets).

### 7.1 Scope decision: where the skill applies and where it does not

The seven existing workflows (`WF-ONBOARD` through `WF-05`) are **upstream data infrastructure** — they don't produce blog content. They produce a prioritized cluster list. Applying the blog-voice skill globally to every LLM call would actively damage the structured-JSON producers (cluster labeler, classifier, ICP scorer) whose entire job is to return strict schemas. The skill must be applied **selectively**, by call site.

| Call site | Output type | Apply skill? |
|---|---|---|
| WF-02 `LLM_Tier2_Classify` | Strict JSON `{ status, reasoning }` | **No.** Schema is the contract. Forcing first-person voice or banning "ultimately" inside a reasoning string adds zero value and risks breaking JSON parse. |
| WF-03 `LLM_Label_Cluster` | Strict JSON `{ label, pillar, niche, theme, confidence }` | **No.** Same reasoning. |
| WF-04 `LLM_ICP_Score` | Strict JSON with `icp_match_reasoning` field | **No** for the structure. The `icp_match_reasoning` text is internal audit copy, not user-facing prose; the skill's blog rhythm would make it harder to skim in the Sheets view. |
| WF-ONBOARD `LLM_Site_Analysis` | Strict JSON describing pillars + ICP | **No** for the JSON. **Yes** for the `client_summary` free-text field if one is added (currently absent — see O5). |
| WF-ONBOARD Slack questionnaire prose (`Build_Slack_Questionnaire`) | User-facing copy in the modal | **Yes.** This is the first piece of prose a paying client reads. Currently hand-written; rewrite via LLM with the skill loaded. |
| WF-ONBOARD `Send_Completion_Notification` Slack copy | User-facing copy | **Yes.** |
| WF-03 `Send_Taxonomy_Suggestion` Slack message | User-facing copy to internal HITL channel | **Yes** (lower priority — internal audience). |
| WF-05 `Send_Slack_Summary` / nightly digest | User-facing copy | **Yes.** This is the daily touchpoint with stakeholders. |
| **WF-06 (future) — Content draft from scored cluster** | Full blog post | **Yes.** This is the skill's native habitat. |

### 7.2 Storage pattern: `system_prompts` Supabase table

Hardcoding the skill's ~230 lines of markdown into every n8n node would be unmaintainable — every voice tweak would require redeploying multiple workflows. Store skills in Supabase and load them at runtime.

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

**Future variants** (e.g., `human-written-technical`, `human-written-finance-vertical`, per-client tone overrides) become additional rows. Only one row per `name` can be active at a time — enforced by a partial unique index or a check trigger.

### 7.3 n8n loading pattern

Every workflow node that uses a system-prompt skill follows the same pattern:

1. **`Fetch_System_Prompt`** — HTTP GET `{{$env.SUPABASE_URL}}/rest/v1/system_prompts?name=eq.human-written-blog&is_active=eq.true&select=content&limit=1`, with `Accept: application/vnd.pgrst.object+json`.
2. **`Build_LLM_Request`** — Code node that builds the OpenRouter payload with `messages: [{ role: 'system', content: $('Fetch_System_Prompt').item.json.content }, { role: 'user', content: <task-specific prompt> }]`.
3. The LLM HTTP node sends the request as usual.

**Caching:** To avoid hitting Supabase on every LLM call, set `Fetch_System_Prompt` to `executeOnce: true` per execution. For very high-frequency workflows, cache in a workflow-scoped static variable or a Redis layer (out of scope for this sprint).

### 7.4 Forward scope: WF-06 — Content Draft from Cluster

This workflow is **not in this sprint's implementation scope** but is named here so the skill has a defined destination and the cluster output's downstream consumer is clear.

**Trigger:** Webhook `/wf-06-draft-from-cluster` accepting `{ client_id, cluster_id, target_word_count?, draft_purpose? }`.

**Flow sketch:**

1. `Validate_Draft_Payload` — verify client + cluster exist and cluster has `priority_score >= 0.5` (configurable).
2. `Fetch_Cluster_Context` — Supabase RPC joining `keyword_clusters ⨝ keyword_cluster_map ⨝ raw_keywords` to pull the cluster label, top 20 member keywords by volume, total volume, ICP reasoning, SERP intent signals, and (if cannibalization is enabled) the `cannibalization_risk_page_id` and its existing page metadata.
3. `Fetch_Client_Voice_Sample` — if `clients.config.voice_sample_url` is set, fetch it; otherwise default voice.
4. `Fetch_System_Prompt` — pulls active `human-written-blog` row from `system_prompts`.
5. `Build_Draft_Request` — combines: the skill content as system message, the cluster context + voice sample + a user prompt of the form *"Write a [target_word_count]-word blog post targeting these search intents: ..."*.
6. `LLM_Draft_Post` — OpenRouter call (model from `clients.config.draft_model`, default `anthropic/claude-3.5-sonnet` or equivalent strong-prose model). `response_format` is **not** set to `json_object` — output is markdown prose. Retry 3× with backoff.
7. `Post_Process_Check` — Code node that scans the draft against §3.3 of the skill (em dashes, curly quotes, decorative bullets) as a belt-and-suspenders pass; logs hits to a `draft_qa` table without modifying the draft.
8. `Write_Draft` — INSERT into a new `content_drafts(id, client_id, cluster_id, pipeline_run_id, version, content, status, created_at)` table.
9. `Log_API_Cost` — same pattern as WF-04.
10. `Respond_OK` — returns `{ ok, draft_id, word_count, cluster_id }`.

**Schema for content drafts:**

```sql
CREATE TABLE content_drafts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL,
  cluster_id uuid NOT NULL REFERENCES keyword_clusters(id),
  pipeline_run_id uuid,
  version int NOT NULL DEFAULT 1,
  system_prompt_name text NOT NULL,
  system_prompt_version int NOT NULL,
  content text NOT NULL,
  word_count int,
  status text DEFAULT 'draft',   -- draft, reviewed, published, rejected
  qa_findings jsonb,             -- output of Post_Process_Check
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX content_drafts_client_idx ON content_drafts (client_id);
CREATE INDEX content_drafts_cluster_idx ON content_drafts (cluster_id, version DESC);
```

### 7.5 Why the PRD itself is not rewritten in this voice

A reasonable reader might ask: "If we have a human-voice skill, why isn't the PRD written that way?" The skill is explicitly scoped to **SEO blog posts** for a public audience. A technical PRD has different obligations:

- **Banned discourse markers** (`additionally`, `furthermore`, `notably`, `critically`) are load-bearing in a spec — they signal logical relationships between sections that engineers parse on first read.
- **First-person voice and casual asides** undermine the authority a build agent needs from a spec.
- **Banned "inflation adjectives"** (`critical`, `pivotal`) overlap with words the spec genuinely needs to mark severity (e.g., "Tier 1 writes never persist — **critical correctness bug**"). The skill's exception clause covers this, but consistently applying the exception in a 20+ page spec creates more cognitive overhead than just writing the spec normally.
- **The skill bans em dashes**, which this PRD uses as a primary readability device for inline definitions. Removing them would force longer, less scannable sentences across ~100 tables and bullet points.

The skill's value comes from how *consistently* it shapes prose at the word and sentence level. A document that is 30% applicable and 70% exempt loses that consistency and produces worse output than just letting each document type follow its own conventions. **Skill scope is a feature, not a limitation.**

### 7.6 Sprint integration summary

| Wave | Skill-related work |
|---|---|
| Wave 1 (foundations) | None — keep focus on `SYS-Error-Handler`, schema changes. |
| Wave 6 (new) | (a) Create `system_prompts` table. (b) Bootstrap `human-written-blog` v1 from the markdown file. (c) Add `Fetch_System_Prompt` nodes to the four prose call sites in §7.1. (d) Scaffold `WF-06` workflow stub + `content_drafts` schema; do not yet wire the live LLM call. |
| Post-sprint | Full WF-06 implementation, voice-sample handling, multi-version A/B testing of skill variants. |

---

*PRD synthesized 2026-05-21 by Opus 4.7 High Reasoning, treating all four source reports as anonymized peers. Conflict resolutions are explicit and traceable. §7 added on the same date to integrate the `human-written-blog` skill scoped to its proper habitat. Ready for implementation-agent handoff after stakeholder sign-off on §4 (conflict decisions), §5 (sprint sequencing), and §7.1 (skill application scope).*
