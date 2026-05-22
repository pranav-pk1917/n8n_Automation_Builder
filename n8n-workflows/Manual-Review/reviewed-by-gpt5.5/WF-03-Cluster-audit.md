# Audit: WF-03-Cluster

## 1. Current Logic Assessment
This workflow receives a client ID, fetches the client, fetches passed keyword classifications, builds a clustering payload, calls the Python worker, sends each returned cluster to an LLM labeler, writes cluster rows, optionally creates taxonomy suggestions, optionally alerts Slack, and responds to the webhook.

Overall health: requires improvement. The clustering concept is correct, but the implementation loses context after `Write_Cluster`, does not write keyword-to-cluster mappings, and does not implement the promised cannibalization check.

Current logic map:
1. `Webhook_Cluster` receives `{ client_id, pipeline_run_id? }`.
2. `Validate_Cluster_Payload` validates and stores the request context.
3. `Fetch_Client` loads client config.
4. `Fetch_Passed_Classifications` loads passed classification rows.
5. `Build_Cluster_Request` filters rows with embeddings and builds `{ items: [{ id, embedding }] }`.
6. `Call_Python_Worker` posts to `/cluster`.
7. `Parse_Worker_Response` emits one item per returned cluster.
8. `LLM_Label_Cluster` labels each cluster.
9. `Parse_Cluster_Label` computes review flags.
10. `Write_Cluster` inserts the cluster row.
11. `IF_Needs_Taxonomy_Review` decides whether to write a taxonomy suggestion.
12. `Respond_Cluster` responds after each no-review cluster or after taxonomy Slack alert.

## 2. Identified Shortcomings & Doubts
- [ ] Issue 1: `Fetch_Passed_Classifications` runs after `Fetch_Client` and uses `{{$json.client_id}}`. If `Fetch_Client` outputs the PostgREST client array, `$json.client_id` is undefined. Use the validated request context instead.
- [ ] Issue 2: `Build_Cluster_Request` allows an empty `items` array when classifications exist but embeddings are null. The worker is then called with no clusterable data.
- [ ] Issue 3: The worker payload contains only classification IDs and embeddings. If the Python worker does not re-fetch keyword text, it cannot produce reliable head terms or member labels.
- [ ] Issue 4: The workflow claims to write `keyword_cluster_map`, but no node writes member mappings from `member_ids` to the inserted cluster ID.
- [ ] Issue 5: `Write_Cluster` changes the current item to the Supabase insert response. `IF_Needs_Taxonomy_Review` then checks `$json.needs_taxonomy_review`, which is no longer present.
- [ ] Issue 6: `Write_Taxonomy_Suggestion` references `$json.label` and `$json.head_term` after `Write_Cluster`, but those fields are lost unless they are returned by Supabase.
- [ ] Issue 7: The sticky note promises cannibalization checks against `pages.embedding`; no node fetches pages or computes similarity, so `cannibalization_risk_page_id` is never set for WF-04.
- [ ] Issue 8: `Respond_Cluster` can run once per cluster. A webhook should respond once after all clusters and taxonomy suggestions are processed.
- [ ] Issue 9: The worker URL is hardcoded to the Railway production URL instead of using an environment variable or credential-backed base URL.

## 3. Scope for Improvement
Keep the Python worker and per-cluster LLM labeling. Add the missing persistence and context-preservation nodes, and only add cannibalization logic at the cluster level so the workflow does not become overcomplicated.

## 4. Execution Plan (For Next Agent)
1. In `Fetch_Passed_Classifications`, replace `{{$json.client_id}}` with a reference to `Validate_Cluster_Payload`, for example `{{$node["Validate_Cluster_Payload"].json.client_id}}`, or insert a `Merge_Client_Context` Code node after `Fetch_Client` that restores `client_id`.
2. Update `Fetch_Passed_Classifications` to include keyword text and useful metrics. Fetch via a Supabase view or RPC that returns `classification_id`, `raw_keyword_id`, `keyword`, `volume`, `kd`, `embedding`, `intent_type`, `niche_hint`, and `content_theme_hint`.
3. In `Build_Cluster_Request`, throw a controlled error or return a successful "nothing to cluster" response when `items.length === 0`.
4. Include keyword text in `worker_payload.items`, for example `{ id, raw_keyword_id, keyword, embedding, volume, kd }`, unless the worker is explicitly documented to fetch text itself.
5. Change `Call_Python_Worker.url` to `={{ $env.PYTHON_WORKER_URL }}/cluster` or an equivalent n8n credential/config value.
6. After `Write_Cluster`, add a `Merge_Cluster_Context` Code node that combines the inserted cluster ID with the pre-write context from `Parse_Cluster_Label`.
7. Move `IF_Needs_Taxonomy_Review` after `Merge_Cluster_Context`, and update downstream references to read from the merged item.
8. Add `Build_Keyword_Cluster_Map_Rows` after `Merge_Cluster_Context`. It must map each `member_id` to `{ client_id, cluster_id: inserted_cluster_id, keyword_classification_id: member_id, pipeline_run_id }`.
9. Add `Write_Keyword_Cluster_Map` to bulk insert those rows into the correct mapping table.
10. Add a cannibalization subflow before `Write_Cluster`: fetch candidate `pages` for the client with embeddings, compute max cosine similarity between the cluster centroid and page embeddings, and set `cannibalization_risk_page_id` only when similarity exceeds the agreed threshold, such as `0.82`.
11. Aggregate per-cluster results before responding. Use an accumulator or final Merge/Aggregate node so `Respond_Cluster` returns once with `{ ok: true, clusters_written, taxonomy_suggestions_written }`.
12. Test with at least three returned clusters, including one low-confidence taxonomy label, and verify one webhook response, one cluster row per cluster, and mapping rows for every member ID.

---
*Written by model - [GPT-5.5 HIgh Reasoning]*
