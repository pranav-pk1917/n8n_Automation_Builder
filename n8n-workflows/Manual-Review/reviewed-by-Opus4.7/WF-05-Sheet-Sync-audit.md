# Audit: WF-05 Nightly Google Sheets Sync

## 1. Current Logic Assessment
Cron (03:00 UTC) fetches active clients, then per client fetches scored `keyword_clusters` (priority_score not null, top 500), fans into `Fetch_API_Costs` (parallel) and `Build_Sheet_Rows`, appends rows to a single `Clusters` tab in Google Sheets, builds a Slack summary, and posts it.

Overall health: **Requires improvement**. The contract is simple and that is fine — the audit is about correctness, not redesign. Defects: `executeOnce` and `.first()` patterns cause cross-client data bleed when multiple clients are active; the Sheets append duplicates rows on every nightly run (no upsert); the Slack summary may use the wrong client's totals; the workflow has no idempotency marker so re-running pollutes the sheet.

## 2. Identified Shortcomings & Doubts
- [ ] **Issue 1 — Cross-client data bleed via `.first()` / `executeOnce`.** `Fetch_Active_Clients` returns N items. Any downstream node using `executeOnce` (e.g. `Fetch_API_Costs`) runs once for client[0] and the rest reuse that result. Per-client iteration must be explicit (Split_In_Batches size 1, or a Loop construct), not implicit.
- [ ] **Issue 2 — Sheets append is not idempotent.** Each nightly run appends ALL clusters (up to 500) again. After 30 nights the `Clusters` tab has 30× duplication of unchanged clusters. There is no de-dup key and no "update if exists" path.
- [ ] **Issue 3 — Sheets append fails on nested arrays.** `Build_Sheet_Rows` per the doc flattens to scalar fields — good. Verify no field (e.g. `top_keywords[]` if ever added) leaks an array; Sheets append silently writes `[object Object]` strings.
- [ ] **Issue 4 — Slack summary aggregates may be wrong client.** If `Build_Summary` reads `$('Fetch_Active_Clients').first()` for the client name, every Slack post says client[0] regardless of which client's data is in the message.
- [ ] **Issue 5 — Top 500 cap is silent.** A client with > 500 scored clusters has the tail dropped from the sheet without warning. Either page or document the cap as a feature.
- [ ] **Issue 6 — No per-client tab and no `client` filter column enforced.** With one `Clusters` tab and multiple clients all writing in, a stakeholder filtering by client must trust the `client` column is populated for every row. Verify `Build_Sheet_Rows` always sets `client`.
- [ ] **Issue 7 — Doc/export disagreement on tab layout is not locked.** `WF-05.md` says one `Clusters` tab; the export JSON references per-pillar tabs. The build agent cannot proceed without a locked contract. **Recommended decision: `Clusters` + `Cost` tabs only**; per-pillar tabs deferred until reporting requires them.
- [ ] **Issue 8 — `Fetch_API_Costs` time window is unclear.** "Last 200 rows" is volume-based, not time-based. A high-volume client can have 200 rows in one day; a low-volume client may span months. Slack "total API cost" is meaningless without a fixed window.
- [ ] **Issue 9 — Slack post is in the success path.** A Slack 429 fails the run; no retry, no error handler.
- [ ] **Issue 10 — No "no clusters" handling.** A client with zero scored clusters still runs the Sheets append (writes nothing) and posts a Slack message saying "0 clusters synced." Either skip silently or roll up into a single multi-client digest.
- [ ] **Issue 11 — No global error path.** Cron failures are invisible — no PATCH of any `pipeline_runs` row (none is created here).

## 3. Scope for Improvement
Keep the cron + Sheets + Slack shape. Make the per-client iteration explicit, switch from "append all" to "append delta since last sync", lock the tab contract, fix the Slack-summary scoping, give Fetch_API_Costs a fixed 24h window, and consolidate the Slack digest to one message per run rather than per client.

## 4. Execution Plan (For Next Agent)
1. **Lock the contract (owner decision).** Write a one-paragraph note at the top of `WF-05.md`: tabs are `Clusters` (one row per cluster per sync) and `Cost` (one row per provider per day). No per-pillar tabs. Remove conflicting references from the export.
2. **Per-client iteration.** Insert `Split_In_Batches_Clients` (size 1) right after `Fetch_Active_Clients`. Every node from `Fetch_Scored_Clusters` through `Send_Slack_Summary` reads `$('Split_In_Batches_Clients').item.json` for the current client. Loop back from the end of each iteration.
3. **Delta append.** Add a `Cluster_Synced_At` column to the `Clusters` tab. Change the Supabase fetch filter to `scored_at=gt.<last_sync>` (track `last_sheet_sync_at` in `clients` table or in `pipeline_runs.kind='sheet_sync'`). After append, PATCH `clients.last_sheet_sync_at = now()`.
4. **Pagination over the 500 cap.** If `scored_at > last_sync` returns > 500 rows, page in 500-row chunks; append each chunk.
5. **Fix Slack scoping.** In `Build_Summary` read `$('Split_In_Batches_Clients').item.json.name` for the client name; aggregate counts from the current iteration's `Build_Sheet_Rows` output only. Never call `.first()` on `Fetch_Active_Clients`.
6. **Cost window.** Change `Fetch_API_Costs` filter to `created_at=gte.<now - 24h>` and remove the 200-row cap (24h × per-cluster cost rarely exceeds 1000 rows).
7. **Consolidate Slack to one digest per run.** Replace per-client `Send_Slack_Summary` with: after the loop, an Aggregate that collects every iteration's `{ client_name, cluster_count, cost_usd, top3 }`, formats them into one Slack Block Kit message, and posts once.
8. **Skip empty clients.** Inside the loop, if `Build_Sheet_Rows` produces 0 rows, skip the Sheets append entirely and add `{ client_name, cluster_count: 0 }` to the aggregate so the digest still mentions them.
9. **Make Slack retryable + fire-and-forget for non-critical errors.** Enable node retry (3×, 5s backoff). The Slack failure must not fail the whole run.
10. **Run tracking.** At the top, create a `pipeline_runs` row with `kind='sheet_sync'`, `client_id=null` (or per-iteration). PATCH to `completed` after the loop, `failed` on error (via error workflow per CW-1).
11. **Cost tab writes.** Add a second Sheets append step that writes one row per `(provider, date, total_cost_usd, request_count)` to the `Cost` tab, derived from the 24h `api_cost_log` rollup.
12. Smoke test: 3 active clients, one with no new clusters → Sheets gets only delta rows, Cost tab gets 3 provider rows for today, Slack posts exactly one digest naming all three clients with the correct counts.

---
*Written by model - [Opus 4.7 medium thinking]*
