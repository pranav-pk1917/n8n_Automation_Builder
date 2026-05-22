# Master PRD & Technical Specification: Workflow Optimizations

## 1. Executive Consensus Summary
The core architecture behind the SEO automation pipeline (tiered filtering, LLM scoring, HDBSCAN clustering, and human-in-the-loop flows) is conceptually sound and modular. However, across all audited workflows, there are systemic structural flaws preventing production readiness. The collective intelligence of multiple models universally highlighted the following critical failures:
- **Pagination & Truncation Constraints:** Hardcoded limits (e.g., `Range: 0-49999`) and single-page Supabase reads cause silent data dropping at scale.
- **Node Wiring & Batching Defects:** Severe `SplitInBatches` misconfigurations result in incomplete loops, processing only the first chunk of data while discarding the rest.
- **Context Loss & Data Bleed:** Incorrect use of `.first()` and PostgREST array outputs lead to downstream nodes executing with missing data or, worse, cross-pollinating data between clients during cron operations.
- **Data Persistence Gaps:** Heavy operations are executed (e.g., embeddings, classifications, clustering), but critical mapping relationships (like Tier 1 pass/reject lists and `keyword_cluster_map` rows) are never written to the database.
- **Brittle Webhook Responses & Lack of Resilience:** Placing responses at the end of heavy loops causes timeout errors. Unbatched external API calls (SerpAPI, OpenRouter) lack rate-limiting and retry safeguards. 
- **Missing Global Error Handling:** Workflows create `pipeline_runs` entries but lack global error catchers to update them to `failed` upon unhandled exceptions.

## 2. Consolidate System Shortcomings & Fixes

### WF-ONBOARD Client Onboarding
- **Core Issue:** Webhook triggers misused as "wait" nodes break execution context. Competitors and gold examples are collected but never persisted.
- **Consensus Level:** High Consensus
- **Technical Fix:**
  1. Inspect Supabase schema for `pipeline_runs.context_jsonb` or create an `onboarding_sessions` table to persist state across asynchronous Phase A/B/C webhooks.
  2. Implement a Slack modal (`views.open`) instead of dropping input blocks into a chat message.
  3. Ensure `competitors` and `gold_examples` are accurately written to their respective Supabase tables.
  4. Fix sitemap index detection and deduplication.

### WF-00-Page-Inventory
- **Core Issue:** Broken batch loop only processes the first 10 pages. Cron lacks idempotency, pointlessly re-embedding unchanged pages every night. 
- **Consensus Level:** High Consensus
- **Technical Fix:**
  1. Re-wire `SplitInBatches`: Use Output 1 for the loop and Output 0 to trigger `Complete_Run`. Connect `Upsert_Page` back into the batch node.
  2. Implement an idempotency check: Skip OpenRouter embedding if a page's `last_seen_at` is recent and its content hash has not changed.
  3. Enforce proper sitemap index detection (`<sitemapindex><loc>`).
  4. Explicitly merge `Create_Run` responses with the client item to prevent `pipeline_run_id` cross-client bleed.

### WF-01-Ingest
- **Core Issue:** Hardcoded 50k limits truncate CSVs. Graveyard deduplication fails to properly evaluate keyword text. Per-chunk webhook responses cause race conditions.
- **Consensus Level:** High Consensus
- **Technical Fix:**
  1. Replace the hand-rolled Code node regex CSV parser with the n8n `Spreadsheet File` node.
  2. Implement pagination for the Supabase fetch (or utilize a Supabase RPC to handle deduplication natively).
  3. Update `Dedupe_Keywords` to properly check both `existingSet` and `graveyardSet` against the raw keyword text.
  4. Respond to the webhook immediately upon payload validation, separating it from the batch insertion loop.

### WF-02-Tiered-Filter
- **Core Issue:** Tier 1 passed/rejected keywords are silently dropped and never written. Tier 0 RPCs race against keyword fetching.
- **Consensus Level:** High Consensus
- **Technical Fix:**
  1. Add explicit nodes to bulk insert `passed_tier1` and `rejected_tier1` records into the `keyword_classifications` table.
  2. Sequentialize execution: Guarantee Tier 0 RPCs complete before fetching unclassified keywords.
  3. Embed gold examples *before* `Prepare_Tier1` starts to allow for valid centroid calculations.
  4. Wrap the Tier 2 `LLM_Classify` calls in a `Split_In_Batches` loop with Wait/Retry nodes to handle OpenRouter rate limits gracefully.

### WF-03-Cluster
- **Core Issue:** The crucial `keyword_cluster_map` join table is never written. Fetch limitations truncate data to 1000 rows.
- **Consensus Level:** High Consensus
- **Technical Fix:**
  1. Standardize PostgREST data unwrapping (accessing `$json.rows` safely) to prevent `client_id` nullification.
  2. Add pagination for `Fetch_Passed_Classifications`.
  3. Add `Build_Map_Rows` and `Bulk_Insert` nodes immediately after cluster creation to write all `member_ids` to `keyword_cluster_map`.
  4. Batch the per-cluster LLM labeling calls and implement exponential backoff on 429 errors.

### WF-04-ICP-Score
- **Core Issue:** Incorrect implementation of the priority formula. Missing URL encoding breaks SerpAPI queries. Unbatched external API calls.
- **Consensus Level:** High Consensus
- **Technical Fix:**
  1. URL-encode the head term via a Code node before passing it to SerpAPI.
  2. Wrap `SerpAPI_Search` and `LLM_ICP_Score` inside dedicated `Split_In_Batches` loops with robust 429 retry capabilities.
  3. Persist all LLM outputs (reasoning, commercial intent weight, etc.) by expanding the PATCH payload, rather than just updating `priority_score`.
  4. Correct the priority logic: Revert to the documented `volume_norm = min(keyword_count / 100, 1.0)` with a fixed 0.20 KD placeholder (unless official product upgrades to actual volume/KD are approved).

### WF-05-Sheet-Sync
- **Core Issue:** Use of `.first()` causes cross-client data bleeding in cron jobs. Sheets operations perform blind appends, creating massive row duplication.
- **Consensus Level:** Conflicting approaches noted, resolved strictly.
- **Technical Fix:**
  1. Lock the operational contract: Sync only the `Clusters` and `Cost` tabs. Drop unnecessary multi-pillar logic.
  2. Ensure strict per-client iteration via a `Split_In_Batches` (size 1) immediately following `Fetch_Active_Clients`.
  3. Use clear-and-write logic on the target Sheet ranges (or strict delta-appends based on `scored_at > last_sync`) to prevent row duplication.

## 3. Architecture & Scalability Suggestions
- **SYS-Error-Handler Sub-Workflow:** A universal error-handling routine must be created and bound to the "Error Workflow" setting of every pipeline. Upon any uncaught exception, this workflow will intercept the execution and PATCH the relevant `pipeline_runs` record's status to `failed` to maintain database hygiene.
- **Strict PostgREST Unwrapping Protocol:** PostgREST GET requests often return an array `[{...}]`, which breaks n8n expressions like `{{$json.client_id}}`. We must enforce a standard `Unwrap_PostgREST` Code node pattern directly following these fetches.
- **Idempotency Standards:** All nodes responsible for expensive compute (LLMs, external APIs, embeddings) must be guarded by strict gating logic (e.g., verifying `scored_at IS NULL` or checking `last_seen_at` hash timestamps) to ensure cron overlaps or manual restarts do not incur duplicate billing.
- **Decoupling Webhook Responses:** Webhook responses must be isolated and fired immediately after payload validation to prevent client timeouts, allowing subsequent data chunks and LLM calls to process asynchronously.
- **LLM Content Quality & Voice Protocol:** Any AI agent or LLM node tasked with generating, expanding, or drafting content must adopt the `human-written-blog` skill (defined in `skills-to-add/skill/human-written-skill.md`). This establishes strict guidelines to avoid AI-generated tells (e.g., banned words like "delve", "leverage", "transformative"), formulaic structures, and generic transitions. Adopting this protocol ensures all generated outputs remain engaging, specific, and authentically human.

## 4. Conflict Log

*   **Conflict 1: CSV Parsing Overhead (WF-01)**
    *   **Contradiction:** Models suggested engineering a custom, hand-rolled RFC4180 CSV parser inside an n8n Code node to deal with multi-line/quoted elements.
    *   **Resolution:** *Maintainability > Execution Speed*. Hand-rolling a complex CSV parser is a maintenance risk. The solution is to utilize the native n8n `Spreadsheet File` node, or transition the webhook contract entirely to expect a pre-parsed JSON `records[]` payload.
*   **Conflict 2: Cannibalization Checks (WF-03)**
    *   **Contradiction:** Some audits proposed computing cosine similarity directly in n8n memory using Javascript arrays to compare against existing page embeddings. 
    *   **Resolution:** *Scalability > Execution Speed*. Executing heavy vector math in node memory scales extremely poorly with thousands of pages. We will defer this calculation entirely to the database layer via a Supabase pgvector RPC: `find_cannibalization_candidates(centroid, threshold)`.
*   **Conflict 3: Priority Formula Drift (WF-04)**
    *   **Contradiction:** The currently implemented code calculates priority using a naive keyword count proxy and zeros out Keyword Difficulty, contrasting with documented specs.
    *   **Resolution:** *Maintainability > Execution Speed*. The system will rigidly follow the documented placeholder formula (`volume_norm = min(keyword_count / 100, 1.0)`, `avgKd = 0.20`). Any upgrades to query real `total_volume` and `avg_kd` metrics will be deferred pending formal business sign-off to ensure predictability.
*   **Conflict 4: Tab Formatting Ambiguity (WF-05)**
    *   **Contradiction:** Workflow documentation prescribes a single flat 'Clusters' tab, whereas exported code reveals orphaned logic attempting to write across 7 dynamic pillar/theme tabs.
    *   **Resolution:** *Maintainability > Scalability*. We lock the execution contract to exactly two output tabs: `Clusters` and `Cost`. The orphaned multi-pillar sorting code will be deprecated until business reporting explicitly requires it.