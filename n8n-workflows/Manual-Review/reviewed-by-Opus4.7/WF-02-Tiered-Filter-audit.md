# Audit: WF-02 Tiered Keyword Filter

## 1. Current Logic Assessment
Webhook (`/wf-02-filter`) validates `client_id`, calls `apply_tier0_filters` RPC, fetches up to 500 unclassified `raw_keywords`, calls `tier1_embed_and_score` RPC which returns `{ passed[], borderline[], rejected[] }`, flattens to per-keyword items, then `IF_Borderline` splits: borderline → `LLM_Tier2_Classify` → `Prepare_T2_Write` → `IF_Needs_Review` → `Write_T2_Classification` → `Send_HITL_Slack_Card`; passed/rejected → `Write_T1_Classification`. All paths converge on `Respond_Filter_OK`.

Overall health: **Requires improvement**. The tier design is good but as wired the workflow has (a) a 500-row hard cap with no continuation, (b) the IF/HITL branches both write but the Slack card blocks the webhook response on the borderline path, (c) no batching for Tier 2 LLM calls, and (d) Tier 0 does not gate Tier 1 — Tier 1 reads the same `raw_keywords` set including ones Tier 0 just rejected.

## 2. Identified Shortcomings & Doubts
- [ ] **Issue 1 — Tier 0 does not gate Tier 1.** `Fetch_Unclassified_Keywords` filters on `status=raw` but Tier 0 RPC updates `keyword_classifications`, not `raw_keywords.status`. Tier-0-rejected keywords are still in the Tier 1 input set, paying for embeddings and skewing centroids.
- [ ] **Issue 2 — 500-keyword cap with no continuation.** Larger ingests are silently truncated. There is no offset loop nor a "more remaining" return signal.
- [ ] **Issue 3 — Tier 2 borderline keywords are processed serially as the items walk the graph.** For 100 borderline keywords this is 100 sequential OpenRouter calls inside one execution, with no retry on 429 and no batchIndex tracking. The whole workflow may exceed n8n execution timeout.
- [ ] **Issue 4 — `Write_T1_Classification` may never fire for passed/rejected** if `IF_Borderline` is wired such that only the borderline branch reaches the writer. Verify the false branch of `IF_Borderline` reaches `Write_T1_Classification` and not `Respond_Filter_OK` directly.
- [ ] **Issue 5 — `IF_Needs_Review` is functionally a no-op.** The doc states "both branches still write." If both branches end at `Write_T2_Classification`, the IF only exists to fork the Slack card — fine — but the writer must be downstream of both, not duplicated.
- [ ] **Issue 6 — `Send_HITL_Slack_Card` is in the response path.** The webhook response (`Respond_Filter_OK`) only fires after every borderline Slack card is posted. Slack 429s or network blips delay the response for the upstream caller (WF-01 chain). HITL notifications should be fire-and-forget side effects.
- [ ] **Issue 7 — Tier 1 RPC `tier1_embed_and_score` requires gold examples (`pos_centroid`, `neg_centroid`).** Nothing in WF-02 confirms gold examples exist or embeds them. If `clients.config.gold_examples` is empty the RPC returns degraded scores silently — every keyword may land in `borderline` and burn LLM budget.
- [ ] **Issue 8 — OpenAI/OpenRouter embedding limits not handled.** A single keyword > 8191 tokens (rare but possible with bad CSV rows) or a `null` keyword fails the whole batch on the Supabase side of `tier1_embed_and_score`.
- [ ] **Issue 9 — Tier 2 LLM has no JSON schema enforcement.** `Prepare_T2_Write` parses LLM JSON; a malformed response throws and kills the keyword. No `response_format: { type: 'json_object' }` and no try/catch.
- [ ] **Issue 10 — `pipeline_run_id` accepted but never written.** Classifications row should carry the run for traceability. None of the writers include it.
- [ ] **Issue 11 — No idempotency on re-runs.** A second call for the same client re-classifies already-classified keywords because `Fetch_Unclassified_Keywords` only filters by `status=raw`, not by "no row in `keyword_classifications`."

## 3. Scope for Improvement
Don't redesign; tighten the existing pipeline. (1) Make Tier 0 actually filter the Tier 1 input set. (2) Add a continuation loop for >500 keywords. (3) Move the Slack card off the response path. (4) Add `Split_In_Batches` around `LLM_Tier2_Classify` with Wait/retry on 429. (5) Validate gold examples up front. (6) Persist `pipeline_run_id` on every write.

## 4. Execution Plan (For Next Agent)
1. **Gate Tier 1 on Tier 0.** Either (a) modify `apply_tier0_filters` to set `raw_keywords.status = 'tier0_rejected'` for filtered rows, and keep the existing `status=eq.raw` filter; or (b) change `Fetch_Unclassified_Keywords` to a Supabase RPC `fetch_pending_for_tier1(p_client_id, p_limit)` that LEFT JOINs `keyword_classifications` and excludes any row already classified at any tier.
2. **Gold-example precheck.** After `Validate_Input`, add `Fetch_Gold_Examples` (GET `clients?id=eq.{{client_id}}&select=config->gold_examples`). If null/empty, branch to `Respond_Filter_Skipped` returning 422 with a clear message; do not proceed.
3. **Continuation loop.** Wrap `Fetch_Unclassified_Keywords → Call_Tier1_Embed_Score → Flatten_Tier1_Results → (rest)` in a `Split_In_Batches` driven by offset. After each batch completes, fetch the next 500; stop when fetch returns < 500.
4. **Move HITL off the response path.** Make `Send_HITL_Slack_Card` a fire-and-forget branch: set its connection's `index` to a separate trailing branch that does NOT continue to `Respond_Filter_OK`. The response should fire as soon as Tier 1/2 writes are durable.
5. **Batch Tier 2 LLM.** Insert `Split_In_Batches_T2` (batch size 5) before `LLM_Tier2_Classify`. After `Write_T2_Classification` loop back. Add a `Wait` node (1.5s) before each batch as a soft rate-limit; on 429 use `On Error: Continue (retry)` with exponential backoff (n8n's built-in retry: 3 attempts, 2× backoff).
6. **Tighten the LLM call.** Add `"response_format": { "type": "json_object" }` to `LLM_Tier2_Classify` body. Wrap `Prepare_T2_Write` JSON parse in `try/catch`; on failure write `decision='parse_error'` with the raw response in `notes`.
7. **Write the run id.** Plumb `pipeline_run_id` from the webhook through `Validate_Input` into every `keyword_classifications` POST body. If absent, create one via `pipeline_runs` insert at the top (kind='filter').
8. **Idempotency.** Add a Tier-0 RPC clause that no-ops on rows already in `keyword_classifications`. For the Tier 1 fetch, exclude `keyword_id IN (SELECT keyword_id FROM keyword_classifications WHERE client_id = ?)`.
9. **Error workflow.** Attach `SYS-Error-Handler` (per CW-1) so any uncaught exception PATCHes `pipeline_runs.status = failed`.
10. **Chain WF-03.** After the final batch writes complete and the response is sent, fire-and-forget POST `https://<n8n-host>/webhook/wf-03-cluster` with `{ client_id, pipeline_run_id }`. Gate behind a `chain_next` flag on the input webhook (default true).
11. Smoke test: 25-keyword payload with 8 borderline → confirm exactly 8 LLM calls, batched 5+3; 1200-keyword payload → confirm 3 fetch cycles and all are classified; missing gold examples → confirm clean 422.

---
*Written by model - [Opus 4.7 medium thinking]*
