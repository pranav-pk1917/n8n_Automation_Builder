# Audit: WF-00-Page-Inventory

## 1. Current Logic Assessment
This workflow runs daily, fetches active clients, creates a `page_sync` pipeline run, fetches each client's sitemap, also fetches WordPress posts from a fixed GraphQL endpoint, merges both page sources, crawls each page, creates an embedding, upserts the page into Supabase, then marks the pipeline run complete.

Overall health: requires improvement. The purpose is sound, but the loop wiring and completion logic can prematurely complete runs, miss batches, or fail an entire client because of one bad page.

Current logic map:
1. `Cron_Daily_0200` triggers `Fetch_Active_Clients`.
2. `Split_Clients` converts the returned client array into one item per client.
3. `Create_Run` inserts a `pipeline_runs` row for each client.
4. `Merge_Client_Run` fans out to `Fetch_Sitemap` and `Fetch_WP_Posts`.
5. `Parse_Sitemap` extracts `<loc>` URLs; `Map_WP_Posts` converts WP posts to page-shaped records.
6. `Merge_Pages` feeds `Batch_Pages`.
7. `Batch_Pages` currently connects output 0 directly to `Fetch_Page_HTML`, then `Extract_Page_Meta`, `Embed_Page`, `Build_Page_Record`, `Upsert_Page`, and `Complete_Run`.

## 2. Identified Shortcomings & Doubts
- [ ] Issue 1: `Batch_Pages` is wired from output 0 to `Fetch_Page_HTML`. In SplitInBatches v3, output 0 is the done output and output 1 is the per-batch output. The workflow should process pages from output 1 and complete from output 0.
- [ ] Issue 2: There is no loop-back from the page processing chain to `Batch_Pages`, so even if the first batch runs, later batches are not guaranteed to process.
- [ ] Issue 3: `Complete_Run` is connected immediately after `Upsert_Page`, which marks the client run completed per page instead of once after all pages are processed.
- [ ] Issue 4: `Fetch_Page_HTML` has no per-page failure tolerance. One timeout, 404, or blocked page can stop the whole client inventory.
- [ ] Issue 5: `Parse_Sitemap` says it dedupes URLs but does not actually dedupe. It also reads only a direct sitemap and does not expand sitemap indexes.
- [ ] Issue 6: `Fetch_WP_Posts` uses the fixed URL `https://cms.webleymedia.com/graphql` for every client. Confirm this is intended; otherwise it mixes global WP posts into all client inventories.
- [ ] Issue 7: `Embed_Page` sends one embedding request per page item. For many active clients, this becomes the main cost and rate-limit bottleneck.

## 3. Scope for Improvement
Keep the workflow's existing architecture. Fix the SplitInBatches loop, move completion to the done path, and add lightweight page-level fault tolerance. Only batch embeddings if page volume is consistently high; otherwise leave per-page embedding intact after the loop fix.

## 4. Execution Plan (For Next Agent)
1. In `Batch_Pages`, connect output 1 to `Fetch_Page_HTML`.
2. Connect `Upsert_Page` back into `Batch_Pages` so the loop continues until all page items have been processed.
3. Connect `Batch_Pages` output 0 to a new `Limit_One_Run_Completion` node, then connect that node to `Complete_Run`.
4. Remove the direct `Upsert_Page -> Complete_Run` connection.
5. Add `continueOnFail: true` or equivalent error output handling to `Fetch_Page_HTML`. Route failures to a new `Build_Page_Error_Record` Code node that writes a minimal `pages` row or `pipeline_run_events` row with `page_url`, `client_id`, and error message.
6. Update `Parse_Sitemap` to dedupe with `const uniqueLocs = [...new Set(locs)]` before mapping page records.
7. If sitemap indexes are expected, add a small branch after `Fetch_Sitemap`: detect `<sitemap><loc>` entries, fetch each child sitemap, then pass the combined URLs into `Parse_Sitemap`.
8. Confirm whether `Fetch_WP_Posts` should be per-client. If yes, replace the hardcoded GraphQL URL with a field from `client.config.wp_graphql_url` and skip the branch when that field is missing.
9. After changes, run one manual execution with a client containing more than 10 sitemap URLs and verify `Complete_Run` executes exactly once per client.

---
*Written by model - [GPT-5.5 HIgh Reasoning]*
