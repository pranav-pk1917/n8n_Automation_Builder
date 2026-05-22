# Audit: WF-00 Page Inventory Sync

## 1. Current Logic Assessment
Daily cron (02:00 UTC) fetches `clients` where `onboarding_status = active`, creates a `pipeline_runs` row per client (`kind = page_sync`), then for each client merges two page sources — `Fetch_Sitemap` and `Fetch_WP_Posts` (WPGraphQL) — through `Merge_Pages` into `Batch_Pages` (size 10) and runs `Fetch_Page_HTML → Extract_Page_Meta → Embed_Page → Build_Page_Record → Upsert_Page → Complete_Run`.

Overall health: **Requires improvement**. Intent is correct, but the SplitInBatches wiring, run-completion placement, paired-item references after HTTP POSTs, and lack of idempotency make this workflow both incorrect on multi-client runs and silently expensive on every nightly tick.

## 2. Identified Shortcomings & Doubts
- [ ] **Issue 1 — `Batch_Pages` wired from done output (output 0) instead of loop output (output 1).** In `splitInBatches` v3, output 0 fires after the loop is exhausted; output 1 fires per batch. The current connection `"Batch_Pages": { "main": [[{ "node": "Fetch_Page_HTML", "index": 0 }]] }` (only one output array) means processing happens on the wrong branch and no second batch ever runs.
- [ ] **Issue 2 — No loop-back from `Upsert_Page` to `Batch_Pages`.** Even after fixing Issue 1, the chain must re-enter `Batch_Pages` to advance to the next batch. There is currently no edge back.
- [ ] **Issue 3 — `Complete_Run` fires after every `Upsert_Page`.** This PATCHes `pipeline_runs.status = completed` once per page rather than once per client, so the run is marked complete on the first page and any later failure is invisible.
- [ ] **Issue 4 — `Merge_Client_Run` cross-pollinates `pipeline_run_id` across clients.** It reads `$('Split_Clients').item.json` after the `Create_Run` HTTP POST. In a multi-client execution n8n cannot guarantee the paired item, so client B can receive client A's `pipeline_run_id`. This also breaks `Parse_Sitemap` and `Map_WP_Posts` which both rely on `$('Merge_Client_Run').item.json`.
- [ ] **Issue 5 — `Parse_Sitemap` does not dedupe** despite the comment claiming it. It also does not detect sitemap index files (`<sitemapindex><sitemap><loc>`) which WordPress emits by default, so for any WP client the workflow only sees the index and writes zero pages.
- [ ] **Issue 6 — `Fetch_Page_HTML` has no per-page failure tolerance.** A single 404, timeout, or 403 aborts the entire client's chain (and would orphan the run as `running` once Issue 3 is fixed).
- [ ] **Issue 7 — Hardcoded WPGraphQL URL `https://cms.webleymedia.com/graphql` for every client.** Either every client is being polluted with Webley Media's own blog posts, or this is a debugging leftover. There is no per-client toggle.
- [ ] **Issue 8 — No idempotency.** Every nightly run re-fetches, re-embeds, and re-upserts every page even when nothing changed. At ~$0.00002/embedding and 200 URLs × N clients × 365 nights that is real money for no signal. There is no skip on recent `last_seen_at` or unchanged content hash.
- [ ] **Issue 9 — No global error path.** Uncaught failures (sitemap 5xx, OpenRouter 429, Supabase 503) leave `pipeline_runs.status = running` forever. There is no Error Workflow configured to PATCH the run to `failed`.
- [ ] **Issue 10 — Embedding cost not logged.** `Build_Page_Record` reads `embed_tokens` but nothing writes to `api_cost_log` (the sticky note advertises it).
- [ ] **Issue 11 — Per-page Supabase POST is the slowest step.** For 200 URLs × dozens of clients × per-page round-trip this can exceed n8n's default execution timeout. Batched upserts (`Prefer: resolution=merge-duplicates` already in place) accept arrays.

## 3. Scope for Improvement
Do not redesign — the architecture is sound. The fixes are surgical: correct the SplitInBatches wiring, move `Complete_Run` to the done branch, replace the paired-item reference with an explicit merge, add a sitemap-index branch and dedupe, add `continueOnFail` plus a fail-row writer for crawl errors, gate embedding on a content hash, and configure an Error Workflow. Batching the Supabase upsert and recording embedding cost can wait unless current runs are already timing out.

## 4. Execution Plan (For Next Agent)
1. Open `Batch_Pages`. Connect **output index 1** (loop) → `Fetch_Page_HTML`. Leave the existing output 0 connection in place ONLY if it goes to the "done" path; otherwise remove it.
2. Wire `Upsert_Page → Batch_Pages` (loop-back) so subsequent batches process.
3. From `Batch_Pages` **output 0** (done), add a new node `Aggregate_Run` (Aggregate, mode "Combine") → connect to `Complete_Run`. Delete the existing `Upsert_Page → Complete_Run` edge.
4. Replace `Merge_Client_Run` (Code) with a real `Merge` node (mode "Combine by position", inputs: `Split_Clients` output and `Create_Run` output). Recompute `pipeline_run_id` from the merged item, not via `$('Split_Clients').item.json`.
5. In `Parse_Sitemap`:
   a. Detect `<sitemapindex>`; if present, emit one item per child sitemap URL, then add a follow-up `Fetch_Child_Sitemap` HTTP node and a second `Parse_Child_Sitemap` Code node that re-emits child `<loc>`s.
   b. Dedupe URLs: `const uniqueLocs = [...new Set(locs)]`.
   c. Strip query strings and fragments before dedupe to avoid `?utm=` duplicates.
6. On `Fetch_Page_HTML` set `continueOnFail: true` and route the error output to a new `Log_Page_Fetch_Error` Code node that POSTs `{ client_id, page_url, error, run_id }` to a `pipeline_run_events` table (or upserts a `pages` row with `crawl_status = error`). Then loop back into `Batch_Pages`.
7. Decide WP intent: either (a) delete `Fetch_WP_Posts` and `Map_WP_Posts` entirely, or (b) gate them behind `IF $json.config.wp_graphql_url IS NOT NULL` and use `={{ $json.config.wp_graphql_url }}` in the request URL.
8. Add idempotency: before `Embed_Page`, insert a `Lookup_Existing_Page` HTTP GET (`pages?client_id=eq.X&url_path=eq.Y&select=last_seen_at,content_hash`) followed by an `IF` node. Skip to a `Touch_Last_Seen` PATCH if `last_seen_at > now() - 20h` AND `sha256(text_for_embedding) === existing.content_hash`; otherwise continue to `Embed_Page`. Store `content_hash` in the `pages` upsert payload.
9. Create a dedicated **Error Workflow** (`SYS-Error-Handler`) that receives `$execution.error` + `$execution.workflowData.id`, looks up the in-flight `pipeline_run_id` from execution data, and PATCHes `pipeline_runs.status = failed` with `error_message`. In WF-00 Workflow Settings, set "Error Workflow" → `SYS-Error-Handler`.
10. (Optional, only if runs exceed 5 min) Batch the Supabase upsert: replace per-iteration `Upsert_Page` with an Aggregate of `page_record` items then a single bulk POST per batch of 10.
11. Smoke test: run manually with a WP client that has a sitemap-index. Verify exactly one `pipeline_runs` row per client transitions `running → completed`, `pages` row count equals deduped URL count, and a repeat run within 20h does not call OpenRouter.

---
*Written by model - [Opus 4.7 medium thinking]*
