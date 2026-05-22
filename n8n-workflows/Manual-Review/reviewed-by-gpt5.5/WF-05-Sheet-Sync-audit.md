# Audit: WF-05-Sheet-Sync

## 1. Current Logic Assessment
This workflow runs daily, fetches active clients, splits them into items, fetches clusters, taxonomy suggestions, and API costs, builds sheet data arrays, checks for a configured sheet ID, writes to Google Sheets, and posts a Slack notification.

Overall health: requires improvement. The workflow is optional/reporting-only, so it is not pipeline-critical, but the exported implementation currently builds many tab datasets and writes only the Cost tab. It also risks mixing first-client data into every client during multi-client runs.

Current logic map:
1. `Cron_Daily_0300` triggers `Fetch_Active_Clients`.
2. `Split_Clients` emits one item per active client.
3. The client item fans out to `Fetch_Client_Clusters`, `Fetch_Taxonomy_Suggestions`, and `Fetch_API_Costs`.
4. All three branches feed `Build_Sheet_Data`.
5. `Build_Sheet_Data` reads `Split_Clients.item.json` and `.first()` output from each fetch node.
6. `IF_Has_Sheets_ID` routes true to `Write_Cost_Tab` and false to `Send_Sync_Notification`.
7. `Write_Cost_Tab` appends or updates the `Cost` sheet, then sends a Slack notification.

## 2. Identified Shortcomings & Doubts
- [ ] Issue 1: `Build_Sheet_Data` uses `$('Fetch_Client_Clusters').first()`, `$('Fetch_Taxonomy_Suggestions').first()`, and `$('Fetch_API_Costs').first()`. In multi-client runs, this can reuse the first client's data for later clients.
- [ ] Issue 2: The workflow builds `pillar_tabs`, `themes_rows`, `tax_rows`, and `cost_rows`, but only writes `Cost`.
- [ ] Issue 3: `Write_Cost_Tab` receives one item containing nested arrays. Google Sheets `appendOrUpdate` with auto-map expects flat row objects, so `cost_rows` may not write as intended.
- [ ] Issue 4: Per-pillar tabs are generated in memory but no nodes create missing tabs or write those rows.
- [ ] Issue 5: The false branch of `IF_Has_Sheets_ID` sends a "sync complete" notification even when no sheet was configured. That should be a skipped/configuration notice.
- [ ] Issue 6: The workflow appends/updates without clearing stale rows. Removed clusters or changed rankings can leave old data in stakeholder sheets.
- [ ] Issue 7: The docs and export disagree: docs say a single `Clusters` tab; export says multi-tab per pillar, taxonomy, themes, and costs. The next agent must choose one output contract before editing nodes.

## 3. Scope for Improvement
Keep WF-05 as a simple nightly reporting workflow. Choose either the single-tab report from the docs or the multi-tab export, then implement that one completely. The lowest-risk path is a single deterministic `Clusters` tab plus `Cost` tab.

## 4. Execution Plan (For Next Agent)
1. Decide the output contract before node edits. Recommended: `Clusters`, `Themes`, `Taxonomy-Suggestions`, and `Cost` tabs only. Do not create one tab per pillar until reporting needs prove it is necessary.
2. Replace the fan-out into `Build_Sheet_Data` with deterministic per-client aggregation. Add a `Merge_Report_Data` node that combines clusters, taxonomy suggestions, and costs for the current client item.
3. Update `Build_Sheet_Data` to read from the merged current item, not `.first()` from prior nodes.
4. Change `Build_Sheet_Data` to output one item per sheet tab with this shape: `{ sheets_id, tab_name, rows, mode }`.
5. Add `Build_Clusters_Rows`, `Build_Themes_Rows`, `Build_Taxonomy_Rows`, and `Build_Cost_Rows` Code nodes if separate tab-specific transformations are easier to maintain.
6. Replace `Write_Cost_Tab` with a generic `Write_Tab_To_Google_Sheets` subflow or repeated Google Sheets nodes, one per tab. Each writer must receive flat row objects, not nested arrays.
7. Before writing each tab, clear the target range below the header row, then write the current full dataset. This prevents stale rankings and deleted clusters from persisting.
8. Update the no-sheet branch to send `status: "skipped_no_sheets_id"` in Slack, not "sync complete".
9. Add a final `Build_Sync_Summary` node after all sheet writes to count tabs written and rows written, then send one Slack notification per client.
10. Test with two active clients with different `sheets_view_id` values. Confirm client A's clusters never appear in client B's sheet.

---
*Written by model - [GPT-5.5 HIgh Reasoning]*
