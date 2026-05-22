# Audit: WF-04-ICP-Score

## 1. Current Logic Assessment
This workflow receives a client ID, fetches client config, fetches unscored clusters, checks an estimated cost ceiling, calls SerpAPI for each cluster, asks an LLM to score ICP and commercial intent, computes a priority score, updates the cluster, logs costs, and responds to the webhook.

Overall health: requires improvement. The scoring concept is useful and budget-aware, but the current implementation can lose `client_id`, respond multiple times, and computes priority using placeholders instead of the actual metrics described by the workflow.

Current logic map:
1. `Webhook_ICP_Score` receives `{ client_id, pipeline_run_id? }`.
2. `Validate_Score_Payload` validates and stores request context.
3. `Fetch_Client_Config` loads the client config.
4. `Fetch_Unscored_Clusters` attempts to query clusters using `$json.client_id`.
5. `Check_Cost_Ceiling` estimates SerpAPI cost and emits up to 100 cluster items.
6. `SerpAPI_Search` fetches organic results for each head term.
7. `Build_ICP_Request` builds one LLM request per cluster.
8. `LLM_ICP_Score` returns scoring JSON.
9. `Compute_Priority_Score` calculates priority with keyword count as volume and `avgKd = 0`.
10. `Update_Cluster_Score` patches only `priority_score`.
11. `Log_ICP_Costs` writes cost rows.
12. `Respond_Score` responds downstream of each item.

## 2. Identified Shortcomings & Doubts
- [ ] Issue 1: `Fetch_Unscored_Clusters` uses `{{$json.client_id}}` immediately after `Fetch_Client_Config`. If the client fetch returns an array/object without `client_id`, the cluster query becomes invalid.
- [ ] Issue 2: Empty cluster sets return no items from `Check_Cost_Ceiling`, which can prevent `Respond_Score` from running.
- [ ] Issue 3: `Respond_Score` is downstream of per-cluster processing, so multi-cluster runs can attempt multiple webhook responses.
- [ ] Issue 4: `Compute_Priority_Score` uses `keyword_count` as a proxy for volume and hardcodes `avgKd = 0`. This does not match the documented priority formula.
- [ ] Issue 5: `Update_Cluster_Score` only patches `priority_score`; it does not persist `icp_match_score`, `commercial_intent_weight`, LLM reasoning, scored timestamp, or SERP signals.
- [ ] Issue 6: Cost ceiling estimates only SerpAPI cost in `Check_Cost_Ceiling`, but the workflow also incurs OpenRouter LLM cost per cluster.
- [ ] Issue 7: SerpAPI is called once per cluster without throttling or retries. This is acceptable for small batches but risky at the current cap of 100 clusters.
- [ ] Issue 8: The workflow scores `canonical_head_term` only. If head terms are weak, it ignores member keywords that could improve ICP scoring context.

## 3. Scope for Improvement
Do not redesign scoring. Fix context handling, single-response behavior, and actual score inputs. Add a modest rate-limit delay or batch cap if SerpAPI failures appear in execution logs.

## 4. Execution Plan (For Next Agent)
1. Insert `Merge_Client_Context` after `Fetch_Client_Config`. It should read the client row and merge it with `Validate_Score_Payload`, outputting `{ client_id, pipeline_run_id, client_config }`.
2. Update `Fetch_Unscored_Clusters` to use `$json.client_id` from `Merge_Client_Context`, not directly from the raw client fetch.
3. Add an empty-state branch after `Fetch_Unscored_Clusters`: if no clusters are returned, go to `Respond_Score` with `{ ok: true, status: "no_unscored_clusters" }`.
4. Add or reuse a Supabase RPC/view that returns cluster scoring inputs: `cluster_id`, `canonical_head_term`, `theme_label`, `keyword_count`, `total_volume`, `avg_kd`, `member_keywords`, `suggested_service_pillar`, `pillar_assignment_confidence`, `content_theme`, and `cannibalization_risk_page_id`.
5. Update `Check_Cost_Ceiling` to estimate both SerpAPI and LLM costs. Use conservative defaults such as `serpCost = clustersToScore * 0.03` and `llmCost = clustersToScore * 0.002` unless exact pricing is configured.
6. Update `Build_ICP_Request` to include the top member keywords and the actual `total_volume` and `avg_kd` in the prompt.
7. Update `Compute_Priority_Score` to use `ctx.total_volume` and `ctx.avg_kd` instead of `keyword_count` and `0`.
8. Update `Update_Cluster_Score` to patch `priority_score`, `icp_match_score`, `commercial_intent_weight`, `icp_match_reasoning`, `serp_intent_signals`, and `scored_at`.
9. Add a `Wait` node or node-level retry settings before/inside `SerpAPI_Search` if testing shows 429 or transient failures.
10. Aggregate processed cluster results before `Respond_Score`. The response should run once with `{ ok: true, scored_count, skipped_count, estimated_cost, actual_logged_cost }`.
11. Test with 0, 1, and 3 unscored clusters. Confirm the 0-cluster path responds, and the 3-cluster path updates three rows but sends one webhook response.

---
*Written by model - [GPT-5.5 HIgh Reasoning]*
