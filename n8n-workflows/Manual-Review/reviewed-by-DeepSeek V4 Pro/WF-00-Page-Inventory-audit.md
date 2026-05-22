# Audit: WF-00-Page-Inventory

## 1. Current Logic Assessment
This workflow runs daily at 02:00 UTC to crawl every active client's sitemap, fetch page HTML, extract metadata (title, meta description), generate vector embeddings via OpenRouter (`text-embedding-3-small`), and upsert pages into the Supabase `pages` table. The overall health is **poor** — a broken SplitInBatches loop means only the first 10 pages of a client's sitemap are ever processed. This workflow is the foundation for cannibalization checks in WF-03. If it doesn't run correctly, downstream similarity matching fails silently.

## 2. Identified Shortcomings & Doubts
- [ ] Issue 1: **Broken SplitInBatches Loop (CRITICAL):** The `Batch_Pages` (SplitInBatches) node splits pages into batches of 10, but the downstream path chains straight to `Complete_Run` without looping back to `Batch_Pages`. Only the first batch of 10 pages is ever processed; the remaining batches are silently dropped.
- [ ] Issue 2: **No Error Handling on Page Fetch:** The `Fetch_Page_HTML` node has no `continueOnFail` or timeout error handler. A single 404 or timeout from any page halts the entire client's sync. For sitemaps with 200+ URLs, at least a few will be broken.
- [ ] Issue 3: **Naive Sitemap Parsing:** The regex `/<loc>([^<]+)<\/loc>/gi` only handles flat sitemaps with `<url>`/`<loc>` structure. It cannot parse sitemap index files (which use `<sitemap>`/`<loc>`) — a common pattern for sites with >50K pages. The workflow would parse zero URLs from a sitemap index.
- [ ] Issue 4: **Hardcoded WPGraphQL Endpoint:** The `Fetch_WP_Posts` node calls `https://cms.webleymedia.com/graphql` regardless of the client. This is a single-agency assumption that will not scale to multi-tenant scenarios where each client has their own CMS.
- [ ] Issue 5: **No Embedding Cache/Change Detection:** Embeddings are regenerated every night for every page, even pages whose content hasn't changed. For a client with 500 pages, this wastes ~$0.03/night in OpenRouter embedding costs and provides no value.
- [ ] Issue 6: **Merge Node Data Loss:** The `Merge_Pages` node merges sitemap pages and WP blog posts, but both input streams come from the same `Merge_Client_Run` context. If either stream fails (e.g., sitemap unreachable but WP posts OK), the merge node may not receive both inputs and could timeout or produce incomplete data.

## 3. Scope for Improvement
The loop fix is trivial — reconnect one wire. Error handling on the HTTP fetch prevents a single bad URL from crashing the entire sync. Adding sitemap index awareness makes the workflow compatible with large sites (which are exactly the clients who need this tool most). An embedding cache (hash-based change detection on title/meta) would cut nightly embedding costs by 80-90% for unchanged clients.

## 4. Execution Plan (For Next Agent)
1. **Fix the SplitInBatches loop:** Disconnect `Complete_Run` from `Upsert_Page`. Connect the main output of `Upsert_Page` back to the input of `Batch_Pages` (the SplitInBatches node). Then connect the `done` output branch (index 1 or the "done" handle) of `Batch_Pages` to `Complete_Run`. This ensures `Complete_Run` fires once after ALL batches finish.
2. **Enable Continue on Fail:** On `Fetch_Page_HTML`, set `options.continueOnFail` to `true`. In `Extract_Page_Meta`, add a null/empty check on the HTML input: if `$input.first().json` is empty or has no body/data, return an item with `text_for_embedding: ''` and `title: '[fetch failed]'` so the pipeline doesn't break but marks the page as needing attention.
3. **Add Sitemap Index Parsing:** In `Parse_Sitemap`, after the initial `<loc>` regex, check if `locs.length === 0`. If so, search for `<sitemap>` elements (regex: `/<sitemap>[\s\S]*?<loc>([^<]+)<\/loc>[\s\S]*?<\/sitemap>/gi`) and if found, set a flag. The current architecture can't recursively fetch sub-sitemaps within a single execution — as a pragmatic fix, add a Code node after Sitemap Parse that, if the sitemap is an index, throws a clear error: `Sitemap is an index. Add index URL to client config and re-run.` Alternatively, add a second HTTP Request node to fetch the first sub-sitemap if an index is detected.
4. **Make WPGraphQL URL Configurable:** Replace the hardcoded URL with `{{ $json.client_config?.wp_graphql_url || $env.WP_GRAPHQL_URL }}` — this pulls the CMS endpoint from the client's config or an environment variable fallback.
5. **Add Embedding Change Detection:** In `Build_Page_Record`, hash the `text_for_embedding` field (using a simple hash like `$helpers.httpRequest` or a Code node with a basic hash). Before calling `Embed_Page`, check if the hash matches the stored page's hash from Supabase via a GET to `pages?client_id=eq.&url_path=eq.&select=content_hash`. Skip embedding if unchanged — just update `last_seen_at`.

---
*Written by model - [DeepSeek V4 Pro]*
