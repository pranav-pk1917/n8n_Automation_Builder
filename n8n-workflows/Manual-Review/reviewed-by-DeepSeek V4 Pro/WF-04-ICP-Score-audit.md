# Audit: WF-04-ICP-Score

## 1. Current Logic Assessment
This workflow fetches unscored clusters from WF-03, runs a SerpAPI search for the top 3 organic results of each cluster's head term, sends those SERP results to Gemini for ICP scoring, computes a priority_score using a weighted formula, and updates the cluster record in Supabase. Cost tracking logs SerpAPI and OpenRouter expenses. Overall health is **fair** — the core scoring logic works but has wasteful patterns (throwing away LLM outputs), a potentially broken expression syntax, and a misleading volume proxy in the priority score formula.

## 2. Identified Shortcomings & Doubts
- [ ] Issue 1: **`encodeURIComponent` in n8n Expression May Fail:** In the `SerpAPI_Search` URL: `?q={{ encodeURIComponent($json.head_term) }}`. The n8n expression system does NOT have a built-in `encodeURIComponent` function. This expression will either evaluate as `undefined` (sending an empty query to SerpAPI) or throw an error at runtime. The fix is to URL-encode in a Code node before the SerpAPI call.
- [ ] Issue 2: **LLM Scoring Outputs Are Thrown Away:** The `LLM_ICP_Score` call returns `icp_match_reasoning`, `serp_intent_signals`, and a full `priority_score_inputs` object. `Compute_Priority_Score` extracts only `icp_match_score` and `commercial_intent_weight` — the reasoning and signals are discarded. `Update_Cluster_Score` only patches `priority_score`. None of the intermediate scoring factors (reasoning, SERP signals) are persisted, making it impossible to audit why a cluster got its score.
- [ ] Issue 3: **Volume Proxy Is Misleading:** The priority formula uses `const totalVolume = ctx.keyword_count || 1` as a stand-in for search volume. But `keyword_count` is the number of keywords in the cluster, not their aggregate search volume. A cluster of 50 low-volume keywords (10 searches/month each) gets boosted more than a cluster of 3 high-volume keywords (10,000 searches/month each). Volume data exists in `raw_keywords` but is never joined.
- [ ] Issue 4: **KD (Keyword Difficulty) Always 0:** The formula uses `avgKd = 0` with the comment "Would need to join keyword_classifications." KD data from SEMrush is available in `raw_keywords` (the `kd` field is parsed in WF-01). Not using it means the penalty term `- (avgKd * 0.5)` always evaluates to 0, inflating scores for difficult keywords.
- [ ] Issue 5: **Hard 100-Cluster Cap:** `Check_Cost_Ceiling` uses `Math.min(100, clusters.length)`. For clients with 150+ unscored clusters, 50 clusters are silently dropped from scoring with no notification.
- [ ] Issue 6: **No Retry on SerpAPI Rate Limiting:** If SerpAPI returns a rate limit error (429), the workflow crashes the entire execution. There's no exponential backoff or retry logic. For 100 clusters × 3 results each, this is 300 SerpAPI calls — a rate limit is plausible.
- [ ] Issue 7: **Cost Ceiling Throws Instead of Downgrading:** When the estimated cost exceeds the ceiling, `Check_Cost_Ceiling` throws a hard error. A better approach would be to scale down (process fewer clusters) or notify Slack without crashing the workflow, so at least some clusters get scored.

## 3. Scope for Improvement
The `encodeURIComponent` fix is urgent — without it, every SerpAPI call may fail. Persisting the LLM's reasoning in the clusters table enables cost-justifiable auditing. Joining actual volume/KD from `raw_keywords` makes the priority score accurate. Adding a retry mechanism and graceful degredation on cost ceiling makes the workflow resilient.

## 4. Execution Plan (For Next Agent)
1. **Fix URL Encoding for SerpAPI:** In `Check_Cost_Ceiling`, add a URL-encoded version of the head term:
   ```
   const encodedQuery = encodeURIComponent(item.head_term);
   return [{ json: { ...item, encoded_query: encodedQuery } }];
   ```
   Then in `SerpAPI_Search`, change the URL to: `https://serpapi.com/search.json?q={{ $json.encoded_query }}&num=3&api_key={{ $env.SERPAPI_KEY }}`. This avoids the broken expression.
2. **Persist Full Scoring Details:** Modify `Update_Cluster_Score` to write more fields. Change the JSON body to include:
   ```
   {
     priority_score: $json.priority_score,
     icp_match_score: $json.icp_match_score,
     commercial_intent_weight: $json.commercial_intent_weight,
     scoring_inputs: $json.scoring_inputs,
     serp_intent_signals: $json.serp_intent_signals,
     icp_match_reasoning: $json.icp_match_reasoning
   }
   ```
   Ensure the `Compute_Priority_Score` node passes all these fields through in its output.
3. **Join Actual Volume and KD from Supabase:** Before `Check_Cost_Ceiling`, add a Supabase query: `GET /rest/v1/keyword_cluster_map?cluster_id=in.(cluster_ids)&select=raw_keyword(volume,kd)`. In `Compute_Priority_Score`, compute `avgVolume` and `avgKd` from the joined data instead of using the keyword_count proxy and 0 for KD.
4. **Remove the 100-Cluster Hard Cap:** Replace `Math.min(100, clusters.length)` with the actual cost ceiling logic. Process all clusters that fit within the budget. If 150 clusters × $0.03 = $4.50 and the ceiling is $10, process all 150. The existing cost check already handles the budget — the hard cap is redundant.
5. **Add SerpAPI Retry with Exponential Backoff:** In `SerpAPI_Search`, set `options.retry` or use a Code node to implement retry logic. If the SerpAPI response contains an HTTP 429, wait 2 seconds, retry once. If it fails again, wait 5 seconds, retry once. If it still fails, log the keyword to a failed_items array and continue with the next cluster (don't crash).
6. **Graceful Degradation on Cost Ceiling:** In `Check_Cost_Ceiling`, instead of `throw new Error(...)`, compute the maximum number of clusters that fit within the ceiling and process only those. Send a Slack notification with: `"Budget ceiling reached: processing N/M clusters. Remaining clusters will be scored on next run."`

---
*Written by model - [DeepSeek V4 Pro]*
