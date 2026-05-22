# Audit: WF-01-Ingest

## 1. Current Logic Assessment
This workflow receives CSV keyword data by webhook, validates and parses the payload, creates an ingest pipeline run, fetches graveyard IDs, fetches existing keywords, removes existing keywords, chunks new records into groups of 500, bulk inserts each chunk into `raw_keywords`, marks the run complete, and responds to the webhook.

Overall health: mostly sound for small CSVs, but requires improvement before larger production imports. The main data path is clear, but graveyard filtering is incomplete and multi-chunk completion/respond behavior is unsafe.

Current logic map:
1. `Webhook_Ingest` receives `{ client_id, csv_content, pipeline_run_label? }`.
2. `Validate_Ingest_Payload` decodes raw or base64 CSV.
3. `Create_Ingest_Run` creates a `pipeline_runs` row.
4. `Parse_CSV` parses rows into `records`.
5. `Fetch_Graveyard_IDs` loads graveyard classification IDs.
6. `Build_Graveyard_Set` stores those IDs in `graveyard_ids`.
7. `Fetch_Existing_Keywords` loads existing raw keyword text up to range `0-49999`.
8. `Dedupe_Keywords` filters against existing keyword text only.
9. `Chunk_Records` creates one n8n item per insert chunk.
10. `Bulk_Insert_Keywords` inserts each chunk, then `Complete_Ingest_Run` and `Respond_Ingest` run downstream.

## 2. Identified Shortcomings & Doubts
- [ ] Issue 1: `graveyard_ids` is never used in `Dedupe_Keywords`. The workflow claims to skip graveyard keywords, but only skips existing `raw_keywords`.
- [ ] Issue 2: Graveyard filtering by `raw_keyword_id` cannot catch newly re-imported keyword text unless the workflow first maps text to the historical raw keyword ID. This makes rejected keywords eligible to return.
- [ ] Issue 3: `Fetch_Existing_Keywords` uses a fixed `Range: 0-49999`; clients above 50,000 keywords can reinsert duplicates unless Supabase constraints reject them.
- [ ] Issue 4: For multiple chunks, `Complete_Ingest_Run` and `Respond_Ingest` execute once per chunk. A webhook should respond once after all chunks complete.
- [ ] Issue 5: The custom CSV parser handles simple quoted commas but not escaped quotes or multiline CSV fields, which are common in exports with keyword annotations.
- [ ] Issue 6: `Bulk_Insert_Keywords` uses plain POST without `Prefer: resolution=merge-duplicates` or `on_conflict`, so race conditions can fail the run if another ingest inserts the same keyword between dedupe and insert.

## 3. Scope for Improvement
Keep the webhook and bulk insert structure. Move dedupe enforcement closer to the database, make graveyard filtering text-aware, and make completion run once after all chunks. Do not add a complex queue system unless imports are regularly larger than 50k rows.

## 4. Execution Plan (For Next Agent)
1. Replace `Fetch_Graveyard_IDs` with a Supabase RPC or view that returns rejected keyword text for the client, for example `graveyard_keywords(keyword)`, not only `raw_keyword_id`.
2. Update `Build_Graveyard_Set` to output `graveyard_keywords: string[]`.
3. Update `Dedupe_Keywords` to build both `existingSet` and `graveyardSet`, then filter with `!existingSet.has(r.keyword) && !graveyardSet.has(r.keyword)`.
4. Replace the fixed `Fetch_Existing_Keywords` range with one of these concrete options: a paginated loop using `Range` windows of 50,000 until fewer than 50,000 rows return, or a database-side insert RPC that accepts parsed records and handles dedupe internally.
5. Add a unique index in Supabase if not already present: `(client_id, keyword)` on `raw_keywords`.
6. Change `Bulk_Insert_Keywords` to use an upsert-compatible request with `Prefer: resolution=merge-duplicates` and the appropriate `on_conflict=client_id,keyword` query string if using PostgREST upsert.
7. Insert a SplitInBatches loop for chunks: connect chunk output to `Bulk_Insert_Keywords`, connect `Bulk_Insert_Keywords` back to the chunk loop, and connect the done output to a single `Complete_Ingest_Run`.
8. Remove any connection that lets `Respond_Ingest` run per chunk. It must run once after `Complete_Ingest_Run`.
9. Replace the custom CSV parser with a Code node parser that supports escaped quotes and CRLF. If external packages are unavailable in n8n, implement RFC4180 handling in the Code node and add sample rows with quoted commas and escaped quotes to the node's pinned test data.

---
*Written by model - [GPT-5.5 HIgh Reasoning]*
