# Audit: WF-03 Clustering + 3-Axis Labeling

## 1. Current Logic Assessment
Webhook (`/wf-03-cluster`) validates `client_id`, fetches `keyword_classifications.decision = passed` joined to `raw_keywords` (limit 1000), builds a payload, POSTs to the Python worker `/cluster`, parses the worker's `clusters[]` into per-cluster items, runs `LLM_Label_Cluster` per cluster for 3-axis taxonomy, parses + cost-estimates, writes `keyword_clusters`, and conditionally sends a Slack taxonomy-suggestion message. Final node is `Respond_Cluster_OK`.

Overall health: **Requires improvement**. Architecture is sound (offload heavy math to Python, label per cluster, write back). The defects are smaller but compounding: context loss across `Fetch_Passed_Keywords`, missing `keyword_cluster_map` writes (cluster-to-keyword join), no cannibalization wiring despite the doc promising it, per-cluster LLM with no batching or retry, and the Slack alert blocking the webhook response.

## 2. Identified Shortcomings & Doubts
- [ ] **Issue 1 — `$json.client_id` after a Supabase GET returns an array.** Standard PostgREST returns `[{ ... }]`. Downstream expressions reading `$json.client_id` after `Fetch_Passed_Keywords` will be `undefined` unless the response is unwrapped (PostgREST single-row `Accept: application/vnd.pgrst.object+json` or a Code-node unwrap).
- [ ] **Issue 2 — 1000-row cap.** Any client with > 1000 passed keywords is silently truncated. No pagination, no `Range` header.
- [ ] **Issue 3 — `keyword_cluster_map` (or equivalent join table) is never written.** `Write_Cluster` inserts a `keyword_clusters` row with `keyword_count` but not the list of `keyword_id`s belonging to it. Downstream (WF-04 SerpAPI, WF-05 Sheets) cannot reconstruct which keywords belong to which cluster.
- [ ] **Issue 4 — Cannibalization check is documented but not implemented.** The README/doc mention pages.embedding comparison; the workflow does not call any Supabase RPC or compute similarity. Either the feature should ship or the doc should be updated.
- [ ] **Issue 5 — Per-cluster LLM calls with no batching, no retry, no rate-limit.** N clusters = N sequential OpenRouter calls. On 429 the whole execution dies mid-stream and partially-written clusters are stranded.
- [ ] **Issue 6 — Cluster id collision risk.** Python worker emits its own `cluster_id` (likely an int per response). If `keyword_clusters.id` is the DB primary key (UUID auto-generated) the worker's `cluster_id` should be stored separately (e.g. `worker_cluster_id`) — otherwise re-runs collide.
- [ ] **Issue 7 — Context loss after `Write_Cluster`.** `Send_Taxonomy_Suggestion` and `Respond_Cluster_OK` likely need `client_id` and the inserted cluster id; if `Write_Cluster` returns the Supabase insert response only, downstream context is dropped.
- [ ] **Issue 8 — `Send_Taxonomy_Suggestion` blocks the webhook response.** Same pattern as WF-02 HITL — Slack post should be fire-and-forget.
- [ ] **Issue 9 — `Respond_Cluster_OK` fires per cluster.** If `Respond to Webhook` is downstream of the per-cluster fan, it may attempt to respond multiple times (n8n logs warnings; only the first reaches the caller).
- [ ] **Issue 10 — Single-member clusters not handled.** If HDBSCAN returns clusters with 1 keyword (or noise label `-1`), the LLM labeler still pays for them. No filter step.
- [ ] **Issue 11 — `pipeline_run_id` accepted but not persisted.** Same trace gap as WF-02.
- [ ] **Issue 12 — No idempotency.** Re-running for the same client creates duplicate `keyword_clusters` rows; no `ON CONFLICT` or "skip if recent run exists" guard.

## 3. Scope for Improvement
Keep the worker offload — that part is right. Tighten everything around it: unwrap PostgREST responses, paginate, persist the keyword-to-cluster mapping, batch the LLM labeler with retries, move Slack off the response path, and either ship cannibalization via a pgvector RPC or remove the promise.

## 4. Execution Plan (For Next Agent)
1. **Unwrap PostgREST.** On `Fetch_Passed_Keywords`, add header `Accept: application/vnd.pgrst.object+json` is NOT correct here (returns array). Instead, add a one-line `Unwrap` Code node: `return items.map(i => ({ json: { rows: Array.isArray(i.json) ? i.json : [i.json] } }));`. Downstream reads `$json.rows`.
2. **Paginate.** Replace the single GET with a paged loop: `Range: 0-999`, `1000-1999`, etc. Stop when a page returns < 1000 rows. Concatenate into the worker payload.
3. **Build cluster→keyword map.** After `Parse_Clusters`, before `LLM_Label_Cluster`, retain `keywords[]` on each cluster item. After `Write_Cluster` returns the inserted cluster's `id`, fan out into a `Build_Map_Rows` Code node that emits `{ cluster_id: inserted.id, keyword_id }` for each `keyword.id` in the cluster, then a `Bulk_Insert_Cluster_Map` HTTP POST to `keyword_cluster_map`.
4. **Schema.** Confirm `keyword_cluster_map(cluster_id uuid, keyword_id uuid, primary key(cluster_id, keyword_id))` exists; if not, create it. Also add `keyword_clusters.worker_cluster_id int` and `keyword_clusters.pipeline_run_id uuid`.
5. **Cannibalization decision.** Pick one:
   - **Ship:** Add Supabase RPC `find_cannibalization_candidates(p_client_id uuid, p_centroid vector, p_threshold float)` using pgvector cosine on `pages.embedding`. Call it after `Parse_LLM_Label` with the cluster centroid (have worker return centroid in response). Set `keyword_clusters.cannibalization_risk_page_id` from the top hit. Threshold from `clients.config.cannibalization_threshold` (default `0.82`).
   - **Defer:** Remove cannibalization references from `WF-03.md` and the README.
6. **Batch + retry the LLM labeler.** Wrap `LLM_Label_Cluster` in `Split_In_Batches` (size 3). Enable n8n node retry: 3 attempts, exponential backoff 2s/4s/8s. Add `response_format: { type: 'json_object' }`. Wrap parse in try/catch and write a fallback label `cluster_label = keywords[0].keyword + ' (unlabeled)'` if parse fails.
7. **Skip single-member / noise clusters.** After `Parse_Clusters`, add `IF (cluster_id === -1 OR keywords.length < 2)` → write a thin row with `label = keywords[0].keyword` and `confidence = 'low'`, skip LLM.
8. **Persist `pipeline_run_id`.** Plumb it into every `keyword_clusters` and `keyword_cluster_map` insert.
9. **Move Slack off the response path.** `Send_Taxonomy_Suggestion` should be a side branch terminating in a noop; `Respond_Cluster_OK` should fire after all `Write_Cluster` writes are durable.
10. **Single response.** Place `Respond_Cluster_OK` AFTER an Aggregate node that waits for all per-cluster writes to finish. It must execute exactly once.
11. **Idempotency.** Before `Build_Cluster_Payload`, check `keyword_clusters` for any row with `client_id` AND `pipeline_run_id`. If found, return 409 (or 200 with `skipped: true`) instead of re-clustering.
12. **Error workflow** per CW-1 → PATCH `pipeline_runs.status = failed`.
13. **Chain WF-04.** After response, fire-and-forget POST `/webhook/wf-04-icp-score` with `{ client_id, pipeline_run_id }`.
14. Smoke test: 200 passed keywords producing ~12 clusters → confirm `keyword_clusters` count, `keyword_cluster_map` row count = sum of cluster sizes, exactly one webhook response, one taxonomy Slack only when LLM sets the flag.

---
*Written by model - [Opus 4.7 medium thinking]*
