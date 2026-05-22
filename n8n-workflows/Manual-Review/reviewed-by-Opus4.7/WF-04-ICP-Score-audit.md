# Audit: WF-04 ICP Scoring + Priority Score

## 1. Current Logic Assessment
Webhook (`/wf-04-icp-score`) validates `client_id`, fetches up to 100 `keyword_clusters` with `icp_score IS NULL`, checks a $50/$0.005 cost ceiling, calls SerpAPI per cluster, calls OpenRouter (Gemini) per cluster with SERP snippets, computes a weighted `priority_score`, PATCHes the cluster row, logs cost to `api_cost_log`, and responds.

Overall health: **Requires improvement**. The pipeline is conceptually clean and the cost ceiling is a nice touch, but execution suffers from the same per-item LLM/SERP pattern as WF-03 with no batching or retry, context loss across the `Fetch_Client_And_Clusters` array, an incomplete update PATCH, and a priority formula in code that does not match the documented formula in `WF-04.md`. The `Respond_Score_OK` placement risks multi-respond warnings.

## 2. Identified Shortcomings & Doubts
- [ ] **Issue 1 — Context loss after `Fetch_Client_And_Clusters`.** The fetch returns an array (PostgREST). Downstream `Check_Cost_Ceiling` re-attaches `client_id` per cluster per the doc, which implies the raw response loses it. Verify the array is properly flattened to one item per cluster with `client_id` preserved before SerpAPI.
- [ ] **Issue 2 — Per-cluster SerpAPI and LLM with no batching, no retry, no rate-limit.** 100 clusters × 2 external calls = 200 sequential round-trips per execution. SerpAPI free tier rate-limits hard; OpenRouter 429s are common. No `Wait` node, no n8n retry, no Split_In_Batches.
- [ ] **Issue 3 — `Respond_Score_OK` may fire per cluster.** If the responder is on the post-PATCH branch without an Aggregate, it triggers multi-respond warnings and only the first reaches the caller.
- [ ] **Issue 4 — `Update_Cluster_Scores` likely PATCHes only `priority_score`.** Per the doc the audit set previously flagged this. The PATCH body should also set `icp_score`, `commercial_intent_score`, `icp_reasoning`, `commercial_reasoning`, `scored_at`. Verify all five are present.
- [ ] **Issue 5 — Priority formula mismatch.** Per `WF-04.md` the canonical formula is `(icp × 0.35) + (commercial × 0.25) + (volume_norm × 0.20) + 0.20` with `volume_norm = min(keyword_count / 100, 1.0)` and `0.20` as a fixed KD placeholder. The code node must implement exactly this; any drift (e.g. using `total_volume / avg_kd`) is a silent product bug. Owner decision required: keep placeholder OR upgrade to real volume/KD (requires WF-03 to roll up `total_volume` and `avg_kd` per cluster, which it currently does not).
- [ ] **Issue 6 — Gate field is ambiguous.** Doc says `icp_score IS NULL`. For idempotency on partial runs `scored_at IS NULL` is safer. Pick one and stick.
- [ ] **Issue 7 — Cost ceiling is naive.** `$0.005 × clusters_count > $50` blocks at ~10k clusters but does not account for SerpAPI cost ($0.003+ per query depending on plan) or actual LLM cost (varies by model). It also does not consult `api_cost_log` to enforce a monthly budget.
- [ ] **Issue 8 — No cluster context for SerpAPI/LLM.** The cluster's `label` is the search query. If the LLM-generated label is bad (e.g. "Untitled") SerpAPI returns junk and ICP score is meaningless. There is no fallback to top keyword text.
- [ ] **Issue 9 — `Log_API_Cost` only logs LLM cost.** SerpAPI calls are also a cost and should be logged with `provider='serpapi'` for full visibility.
- [ ] **Issue 10 — No `pipeline_run_id` PATCH.** Cluster rows should carry `last_pipeline_run_id` for audit; not done.
- [ ] **Issue 11 — Per-cluster `Respond to Webhook`** if present (see Issue 3) means WF-05 / downstream cannot trust the success signal.

## 3. Scope for Improvement
Architecture is fine. Tightening: batch SerpAPI/LLM with retry+wait, fix the PATCH body to include every score field, lock the formula to docs (with owner decision recorded), align idempotency on `scored_at`, log SerpAPI cost, ensure one webhook response, and preserve `client_id`/`pipeline_run_id` through the chain.

## 4. Execution Plan (For Next Agent)
1. **Owner decision required (gate).** Confirm priority formula: keep deployed placeholder (`+0.20` KD literal, `volume_norm = keyword_count/100`) OR upgrade to `total_volume`/`avg_kd`. If upgrade, add a step in WF-03 to populate `keyword_clusters.total_volume` (sum) and `keyword_clusters.avg_kd` (mean) from `keyword_cluster_map ⨝ raw_keywords`.
2. **Unwrap and flatten.** After `Fetch_Client_And_Clusters`, add a Code node that splits the PostgREST array into one item per cluster and explicitly carries `{ client_id, pipeline_run_id, cluster_id, label, keyword_count, total_volume, avg_kd }` forward.
3. **Idempotency gate.** Change fetch filter to `scored_at=is.null` (canonical) and update `WF-04.md` to match. Drop `icp_score IS NULL` ambiguity.
4. **Budget guard from history.** Before SerpAPI, GET `api_cost_log?client_id=eq.X&created_at=gte.<month_start>&select=cost_usd`; sum and add the run estimate. If total > `clients.config.monthly_api_budget` (default $50), respond 402 and PATCH `pipeline_runs.status = budget_exceeded`.
5. **Batch SerpAPI.** Wrap `Fetch_SERP_Data` in `Split_In_Batches` (size 5). Add a `Wait` of 1s between batches. On 429 set node retry: 3 attempts, exponential backoff 5s/15s/45s. Use `continueOnFail: true` and on failure write a synthetic empty SERP so the LLM step can still score on label+keywords alone.
6. **Label fallback.** Before SerpAPI, set `query = label && label !== 'Untitled' ? label : top_keyword_text`. Fetch `top_keyword_text` by joining `keyword_cluster_map ⨝ raw_keywords` ordered by `volume DESC LIMIT 1` per cluster (one Supabase call up front, attached to each cluster item).
7. **Batch LLM.** Wrap `LLM_ICP_Score` in `Split_In_Batches` (size 3) with the same retry pattern. Add `response_format: { type: 'json_object' }`. Wrap `Compute_Priority_Score` JSON parse in try/catch; on failure mark cluster `scored_at = now, icp_score = null, scoring_error = 'parse_failed'` and continue.
8. **Lock the formula.** In `Compute_Priority_Score` enforce the canonical formula exactly. Add a unit-test Code branch (manual-trigger only) with known inputs to verify the output.
9. **Fix the PATCH body.** `Update_Cluster_Scores` JSON body must be:
   ```json
   {
     "icp_score": ...,
     "commercial_intent_score": ...,
     "priority_score": ...,
     "icp_reasoning": "...",
     "commercial_reasoning": "...",
     "scored_at": "<iso>",
     "last_pipeline_run_id": "<uuid>"
   }
   ```
10. **Log SerpAPI cost.** After `Fetch_SERP_Data` (success branch), POST `api_cost_log` with `provider='serpapi'`, `cost_usd=<plan_rate>`, `workflow='wf-04-icp-score'`, `client_id`, `pipeline_run_id`.
11. **Single response.** After all per-cluster PATCHes, place an Aggregate node, then `Respond_Score_OK` exactly once with `{ ok: true, scored: N, skipped: M, total_cost_usd: $X }`.
12. **Error workflow** per CW-1 to PATCH `pipeline_runs.status = failed`.
13. Smoke test: 5 unscored clusters, 1 with bad label → confirm fallback query, all 5 PATCHed with five fields each, 1 SerpAPI + 1 LLM log per cluster in `api_cost_log`, single webhook response.

---
*Written by model - [Opus 4.7 medium thinking]*
