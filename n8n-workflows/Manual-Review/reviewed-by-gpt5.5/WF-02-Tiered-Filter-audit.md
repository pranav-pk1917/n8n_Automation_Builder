# Audit: WF-02-Tiered-Filter

## 1. Current Logic Assessment
This workflow receives a client ID, fetches client configuration, attempts Tier 0 database filtering, fetches raw keywords and gold examples, prepares embedding inputs, calls OpenRouter embeddings, scores Tier 1, sends borderline keywords to an LLM classifier, writes Tier 2 classifications, optionally posts HITL Slack cards, and responds to the webhook.

Overall health: requires major correction. The intended tiered design is good, but the current graph does not reliably gate Tier 1 behind Tier 0, does not split embedding batches correctly, and does not write passed/rejected Tier 1 classifications.

Current logic map:
1. `Webhook_Filter` receives `{ client_id, pipeline_run_id? }`.
2. `Validate_Filter_Payload` validates the client ID.
3. `Fetch_Client_Config` loads the client record.
4. `Merge_Client_Config` fans out to `Tier0a_Regex_Filter`, `Fetch_Unclassified_Keywords`, and `Fetch_Gold_Examples`.
5. `Tier0a_Regex_Filter` feeds `Tier0b_Competitor_Filter`, but `Tier0b_Competitor_Filter` is terminal.
6. `Fetch_Unclassified_Keywords` and `Fetch_Gold_Examples` both feed `Prepare_Tier1`.
7. `Prepare_Tier1` returns one item containing arrays of all keyword text and IDs.
8. `Batch_For_Embedding` feeds `Embed_Keywords_Batch`, then `Score_Tier1`, then borderline-only Tier 2 classification.
9. `Write_Classification` writes only Tier 2 results, then `IF_Needs_HITL` posts Slack or responds.

## 2. Identified Shortcomings & Doubts
- [ ] Issue 1: Tier 0 does not gate Tier 1. `Fetch_Unclassified_Keywords` can run in parallel with `Tier0a_Regex_Filter`, and `Tier0b_Competitor_Filter` is terminal.
- [ ] Issue 2: `Fetch_Unclassified_Keywords` fetches all raw keywords for the client, not only still-unclassified or still-raw keywords. This can reprocess already classified rows.
- [ ] Issue 3: `Prepare_Tier1` has two incoming branches but no explicit Merge node. Multi-source data should be merged deterministically before building the Tier 1 payload.
- [ ] Issue 4: `Batch_For_Embedding` receives one item containing arrays, so it does not create one item per 100 keywords. The downstream expression references `$json.batchIndex`, but no node creates `batchIndex`.
- [ ] Issue 5: `Batch_For_Embedding` is wired from output 0 into the processing body. For SplitInBatches v3, use output 1 for each batch and output 0 for done.
- [ ] Issue 6: `Score_Tier1` indexes `ctx.keywords_to_embed[i]` from the start of the full list for every embedding response. Even after batching is fixed, later batches would map embeddings to the wrong keyword IDs unless chunk offsets are carried forward.
- [ ] Issue 7: Passed and rejected Tier 1 results are never written to `keyword_classifications`; only borderline Tier 2 items are written.
- [ ] Issue 8: If `IF_Needs_HITL` routes true, `Send_HITL_Card` is terminal and the webhook may never reach `Respond_Filter`.
- [ ] Issue 9: Slack button values use `raw_keyword_id` as `classification_id`, while `Write_Classification` uses `Prefer: return=minimal`. The later HITL handler will not have the actual classification row ID.

## 3. Scope for Improvement
Preserve the tiered filtering strategy. Fix node ordering, deterministic input merging, batch construction, and classification writes. Do not broaden the LLM pass beyond borderline keywords; that cost-saving design is correct.

## 4. Execution Plan (For Next Agent)
1. Rewire the Tier 0 path so `Merge_Client_Config -> Tier0a_Regex_Filter -> Tier0b_Competitor_Filter -> Fetch_Unclassified_Keywords`.
2. Keep `Fetch_Gold_Examples` after `Tier0b_Competitor_Filter` as a parallel branch with `Fetch_Unclassified_Keywords`, or fetch it before Tier 0 and join later. Do not let Tier 1 start until both keyword rows and gold examples are available.
3. Add a `Merge_Tier1_Inputs` node before `Prepare_Tier1` to combine the keyword rows and gold examples deterministically.
4. Change `Fetch_Unclassified_Keywords` to fetch only eligible rows. Use a filter such as `status=eq.raw` if `raw_keywords.status` exists, or an RPC that excludes rows already present in `keyword_classifications`.
5. Replace `Prepare_Tier1` output with one item per embedding chunk: `{ chunk_index, chunk_offset, keywords, keyword_ids, pos_centroid, neg_centroid, client_id, pipeline_run_id, client_config }`.
6. Remove the `$json.batchIndex` expression from `Embed_Keywords_Batch`. Send `input: $json.keywords`.
7. If SplitInBatches is kept, connect output 1 to `Embed_Keywords_Batch`, loop `Score_Tier1` back to `Batch_For_Embedding`, and connect output 0 to a final aggregation node.
8. Update `Score_Tier1` to map each embedding using `$json.keyword_ids[i]` and `$json.keywords[i]` from the current chunk, not from `Prepare_Tier1.first()`.
9. Add `Build_Tier1_Classification_Rows` after `Score_Tier1` to emit classifications for `passed_tier1` and `rejected_tier1`.
10. Add `Write_Tier1_Classifications` to bulk insert those rows into `keyword_classifications`.
11. Keep `Prep_Tier2_Items` only for `borderline` rows, then write Tier 2 rows as the workflow already intends.
12. Change `Write_Classification` for Tier 2 to `Prefer: return=representation` so the actual classification ID is available for Slack button values.
13. Connect both outputs of `IF_Needs_HITL` to a single completion path. The true branch should be `Send_HITL_Card -> Respond_Filter`; the false branch should also go to `Respond_Filter`.
14. Verify with a 250-keyword test CSV that embeddings are sent in three chunks, Tier 1 rows are written, Tier 2 runs only for borderline rows, and the webhook responds once.

---
*Written by model - [GPT-5.5 HIgh Reasoning]*
