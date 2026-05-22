# Audit: WF-03-Cluster

## 1. Current Logic Assessment
This workflow fetches passed keywords from `keyword_classifications`, sends them to a Python worker on Railway for HDBSCAN clustering, then runs an LLM (Gemini) per cluster to label it on three axes: service_pillar, vertical_niche, and content_theme. Clusters are written to Supabase. Low-confidence pillar/niche assignments trigger Slack taxonomy suggestion alerts. Overall health is **poor** — the workflow has a critical external dependency (Railway Python worker) flagged as broken, the keyword fetch has a 50K hard limit, and the architecture assumes the worker handles data that it may not.

## 2. Identified Shortcomings & Doubts
- [ ] Issue 1: **External Worker Dependency Is a Blocker (CRITICAL):** The sticky note explicitly states: "Requires Railway /cluster fix to be complete before this workflow will succeed." If the Python worker (`https://seo-tools-production-c347.up.railway.app/cluster`) is unavailable or returning errors, this entire workflow is dead. The worker is expected to: accept keyword embeddings, run HDBSCAN, return cluster assignments. If embedding fetch is also handled by the worker (which the export JSON implies), the worker needs its own Supabase credentials and network access.
- [ ] Issue 2: **Hard 50K Range Cap on Passed Classifications:** `Fetch_Passed_Classifications` uses `Range: 0-49999`, the same pattern across all workflows. For clients with >50K passed keywords, keywords beyond position 50,000 are silently excluded from clustering.
- [ ] Issue 3: **Sequential LLM Labeling Bottleneck:** `LLM_Label_Cluster` processes one cluster at a time. With 60 clusters (a realistic number for a medium-sized client), the workflow makes 60 sequential OpenRouter API calls. At ~2 seconds per call, this takes 2+ minutes just for LLM labeling, during which the execution holds memory.
- [ ] Issue 4: **No keyword_cluster_map Writes:** The workflow writes to `clusters` table and `taxonomy_suggestions` table, but the JSON export version has **no code that writes to `keyword_cluster_map`** (mapping individual keyword_classification IDs to their cluster). This means after clustering completes, there's no way to determine which keywords belong to which cluster — the relationship is lost unless the worker writes it back directly.
- [ ] Issue 5: **Cannibalization Check Is Declared but Never Implemented:** The sticky note and workflow name mention "Cannibalization Check" but no node in the workflow queries `pages.embedding` or computes similarity between cluster keywords and existing pages. This feature is a placeholder.
- [ ] Issue 6: **Parse_Worker_Response Assumes Worker Output Shape:** The code references `cluster.canonical_head_term`, `cluster.head_term`, and `cluster.member_ids` — but if the worker returns a slightly different shape (e.g., `head_keyword` instead of `head_term`), every cluster will have empty head terms and zero member IDs. There's no schema validation on the worker response.
- [ ] Issue 7: **No Cost Tracking for Worker Calls:** The Python worker call (`Call_Python_Worker`) has no cost logging. While Railway charges by compute time, there's no `api_cost_log` entry recording the worker's execution duration or cost, making cost auditing incomplete.

## 3. Scope for Improvement
The worker dependency needs validation before anything else. The LLM labeling bottleneck can be solved by batching multiple clusters into a single Gemini call (similar to the WF-02 Tier 2 fix). The keyword_cluster_map write is essential — without it, clusters are orphaned labels with no members. Cannibalization can be deferred to a separate workflow or added as a post-clustering step in WF-04.

## 4. Execution Plan (For Next Agent)
1. **Validate or Replace Worker Dependency:** First, test the Railway `/cluster` endpoint with a curl/Postman call sending the exact payload shape: `{ items: [{ id, embedding }] }`. If the worker returns 200 with valid cluster data, proceed. If it's broken, either: (a) fix the worker, or (b) replace it with an n8n-native clustering approach using a Code node with a lightweight JS library, or (c) move clustering logic to a Supabase Edge Function.
2. **Add Worker Response Schema Validation:** In `Parse_Worker_Response`, add a validation check on the response shape before mapping:
   ```
   if (!workerResp.clusters || !Array.isArray(workerResp.clusters)) {
     throw new Error(`Worker returned unexpected format: ${JSON.stringify(Object.keys(workerResp))}`);
   }
   ```
   Check that each cluster has at least `cluster_id` and `member_ids` fields.
3. **Write keyword_cluster_map Records:** After `Write_Cluster`, add a new Code node that builds `keyword_cluster_map` records. For each cluster, iterate `member_ids` and map each `classification_id` to the new cluster ID (returned from the Write_Cluster Supabase response). Bulk insert into `keyword_cluster_map` using a Supabase POST.
4. **Batch LLM Cluster Labeling:** Merge `LLM_Label_Cluster` into a batched approach. Before the LLM call, aggregate 10-15 clusters into one prompt. The system prompt should accept an array of clusters and return an array of labels: `{ labels: [{ cluster_id, theme_label, suggested_service_pillar, ... }] }`. This reduces API calls from N to N/12.
5. **Add Pagination for Passed Classifications:** Same as WF-01/WF-02 — check `content-range` header, loop if needed, accumulate all passed classifications before building the worker request.
6. **Log Worker Cost:** After `Call_Python_Worker`, add a Code node that computes an approximate cost (Railway charges ~$0.000231/minute for the base tier). Log this to `api_cost_log` using the pattern from WF-04 (`Log_ICP_Costs`), with `provider: 'railway'`, `model: 'python-hdbscan'`, `operation: 'cluster_hdbscan'`.
7. **Add Cannibalization Check as Optional Follow-up:** Defer the cannibalization check to a separate WF-03-Post-Process workflow (or a Code node at the end of WF-03). The logic: for each cluster, compute cosine similarity between the cluster's centroid embedding and each page in `pages` for the client. Flag clusters where similarity > 0.85 with a page URL as potential cannibalization risks. Write the `cannibalization_risk_page_id` to the clusters record.

---
*Written by model - [DeepSeek V4 Pro]*
