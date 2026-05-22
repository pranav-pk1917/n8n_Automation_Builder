# Audit: WF-01 CSV Keyword Ingest

## 1. Current Logic Assessment
Webhook (`/wf-01-ingest`) receives `{ client_id, csv_content }`. `Validate_And_Parse_CSV` (Code) emits one item per row. Two parallel fan-outs (`Fetch_Existing_Keywords`, `Fetch_Graveyard`) run with `executeOnce`, then `Dedupe_And_Prepare_Insert` filters out duplicates, `Bulk_Insert_Raw_Keywords` writes the survivors, and `Respond_Insert_OK` returns `{ ok: true }`.

Overall health: **Requires improvement**. The shape is right (parse → dedupe → bulk insert → respond), but at meaningful CSV sizes the workflow is silently incorrect: the graveyard fetch is ignored, the Supabase range cap truncates the dedupe key set, the response races the insert, and the parser is fragile against any quoted field. None of these surface as visible errors.

## 2. Identified Shortcomings & Doubts
- [ ] **Issue 1 — Graveyard data is fetched but not used.** `Fetch_Graveyard` runs but `Dedupe_And_Prepare_Insert` either consumes only the first input or has no edge to it. Verify the dedupe code reads both `$items(0)` (existing) and `$items(1)` (graveyard); the doc claims graveyard dedupe but most n8n Code patterns only read `$input.all()` which collapses to one branch.
- [ ] **Issue 2 — `Fetch_Existing_Keywords` has no `Range`/pagination.** Supabase PostgREST returns max 1000 rows by default and caps at the configured `db-max-rows`. A client with >1000 existing keywords will silently re-insert apparent "new" keywords that already exist, then fail on the unique constraint (if one exists) or duplicate-load the row (if not).
- [ ] **Issue 3 — No `(client_id, keyword)` unique index is guaranteed.** Without it, repeated CSV uploads create soft duplicates that pollute Tier 0/1 scoring downstream. The audit must verify schema before relying on dedupe.
- [ ] **Issue 4 — CSV parser is hand-rolled / fragile.** Per the docs the Code node does naive `split(',')`. Any keyword containing a comma in quotes (common in Semrush exports), a CRLF inside a quoted field, or a UTF-8 BOM will corrupt the row. There is no RFC4180 handling and no `csv-parse` library available in Code.
- [ ] **Issue 5 — `Respond_Insert_OK` does not wait on `Bulk_Insert_Raw_Keywords`.** If `Respond to Webhook` is not chained strictly after the insert, n8n can respond before Supabase confirms. Verify the connection order in the export: caller should only see 200 once rows are durable.
- [ ] **Issue 6 — No `pipeline_run_id` written.** The downstream chain (WF-02/03/04) is supposed to share a `pipeline_run_id`. WF-01 neither accepts one in the webhook contract nor creates one in `pipeline_runs`, so traceability is broken from the start.
- [ ] **Issue 7 — No downstream kick.** After successful insert the workflow returns and stops. WF-02 must be triggered manually, which contradicts the README's "Typical order" of WF-01 → WF-02 → WF-03 → WF-04.
- [ ] **Issue 8 — No payload size guard.** A 5MB CSV pasted into a single JSON field passes through n8n's webhook body parser, balloons in memory after parse, and may exceed worker memory before dedupe even runs. There is no row-count cap or `csv_content.length` rejection.
- [ ] **Issue 9 — No client existence check.** A bad `client_id` passes validation, dedupe returns zero matches, and the insert fails with an FK violation that surfaces as a generic 500 to the caller.

## 3. Scope for Improvement
Keep the linear shape; do not split into sub-workflows. Replace the regex parser with the built-in `Spreadsheet File` node (or change the contract to accept pre-parsed JSON `records[]`), add proper paging on the existing-keyword fetch, ensure the graveyard input is actually consumed, create a `pipeline_run_id` at the top, and trigger WF-02 at the end. Cost-free fixes only; no architectural change.

## 4. Execution Plan (For Next Agent)
1. **Schema check (prereq).** Run `SELECT indexname FROM pg_indexes WHERE tablename = 'raw_keywords';` in Supabase. If no unique index on `(client_id, lower(keyword))`, create one:
   ```sql
   CREATE UNIQUE INDEX raw_keywords_client_keyword_uniq
     ON raw_keywords (client_id, lower(keyword));
   ```
2. **Webhook contract.** Add optional fields to `Ingest_Webhook`: `pipeline_run_id` (UUID, optional) and `chain_next` (boolean, default true). Document in `WF-01.md`.
3. **Replace the parser.** Delete the regex split inside `Validate_And_Parse_CSV`. Insert an n8n `Spreadsheet File` node (operation: "Read from file", inputDataFieldName: `csv_content`, options.headerRow: true) immediately after `Ingest_Webhook`. Keep a thin Code node afterward only to trim/lowercase the `keyword` field, coerce `volume`/`kd` to numbers, and inject `client_id` from the webhook body.
4. **Client validation.** After parsing, add `Verify_Client` HTTP GET `clients?id=eq.{{client_id}}&select=id` and an `IF` that responds 400 if empty.
5. **Create a `pipeline_runs` row** if `pipeline_run_id` was not supplied: POST `pipeline_runs` with `kind='ingest'`, `status='running'`, return ID, attach to every downstream item.
6. **Paginate existing keywords.** Replace `Fetch_Existing_Keywords` single GET with a paged Code+HTTP loop using `Range: 0-999`, `1000-1999`, etc. until response length < page size. Aggregate into one Set. Same for `Fetch_Graveyard` (usually small; one page is fine if you verify `< 1000`).
7. **Fix dedupe input wiring.** Ensure `Dedupe_And_Prepare_Insert` receives both branches. Either (a) put a `Merge` (mode "Combine") between the two fetches and the dedupe node, then read `$input.all()` and partition by `source` field, or (b) explicitly read `$('Fetch_Existing_Keywords').all()` and `$('Fetch_Graveyard').all()` inside the Code node. Verify by logging final dedupe rejection counts.
8. **Wrap insert.** Send `Bulk_Insert_Raw_Keywords` with `Prefer: resolution=ignore-duplicates` so any leaked duplicates are silently skipped instead of 409-ing the whole batch.
9. **Order the response strictly after the insert.** Confirm the edge `Bulk_Insert_Raw_Keywords → Respond_Insert_OK` is direct (no parallel branches). Include `{ ok: true, inserted: N, skipped: M, pipeline_run_id }` in the response.
10. **PATCH the run** to `status='completed'` after the insert; on error path PATCH to `failed`. Wire an Error Workflow (see CW-1).
11. **Chain WF-02.** After the successful PATCH, add an HTTP POST to `https://<n8n-host>/webhook/wf-02-filter` with `{ client_id, pipeline_run_id }`, gated by `chain_next === true`. Use `executeOnce: true`.
12. **Add a payload guard** at the top: reject if `csv_content.length > 5_000_000` (~50k rows) or row count > 50_000 with a clear 413 response.
13. Smoke test: 10-row CSV (chain enabled) → confirm raw_keywords inserts and WF-02 starts; 1100-row CSV with 50 existing keywords → confirm pagination dedupe; CSV with quoted commas → confirm parser correctness.

---
*Written by model - [Opus 4.7 medium thinking]*
