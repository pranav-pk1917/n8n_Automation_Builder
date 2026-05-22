# Audit: WF-01-Ingest

## 1. Current Logic Assessment
*Briefly define what the workflow currently does and its overall health.*
This workflow receives a CSV of keywords via webhook, parses it, dedupes against existing Supabase records and a graveyard, chunks the new records, and bulk inserts them. The overall health is poor due to webhook response errors when processing multiple chunks, and memory/scalability limits in the deduplication logic.

## 2. Identified Shortcomings & Doubts
*List any unclear logic, potential failure points, or scalability bottlenecks.*
- [ ] Issue 1: **Multiple Webhook Responses:** `Respond_Ingest` is placed at the end of the chunk processing chain. If the CSV is large enough to create multiple chunks, the workflow will attempt to respond to the webhook multiple times, causing a "Webhook already responded" error.
- [ ] Issue 2: **Multiple Run Completions:** `Complete_Ingest_Run` is also inside the chunk loop, meaning the pipeline run will be marked as completed multiple times.
- [ ] Issue 3: **Hardcoded 50k Limit:** `Fetch_Existing_Keywords` uses a hardcoded `Range: 0-49999` header. If a client scales beyond 50,000 keywords, the deduplication logic will fail and allow duplicates.
- [ ] Issue 4: **Memory Bloat:** Fetching up to 50k keywords into n8n memory just to perform a Set-based deduplication is highly inefficient.

## 3. Scope for Improvement
*Explain how the efficiency and scalability can be boosted without over-engineering.*
The webhook should be acknowledged immediately to prevent timeouts and multiple-response errors. Deduplication should be pushed to the database layer (Supabase RPC or `ON CONFLICT DO NOTHING`) to eliminate the 50k limit and reduce n8n memory usage.

## 4. Execution Plan (For Next Agent)
*Provide step-by-step, actionable instructions on exactly which nodes to change, add, or remove.*
1. **Respond Early:** Move the `Respond_Ingest` node to immediately follow `Validate_Ingest_Payload`. Return a simple `{"ok": true, "status": "processing"}` so the client isn't left hanging.
2. **Fix the Loop/Completion:** Add an `Aggregate` node after `Bulk_Insert_Keywords` to wait for all chunks to finish inserting. Connect the output of this Aggregate node to `Complete_Ingest_Run`.
3. **Optimize Deduplication:** Remove `Fetch_Existing_Keywords` and the manual `Dedupe_Keywords` code node. Instead, rely on Supabase's native unique constraints during the bulk insert, or replace the fetch with a Supabase RPC call that handles the deduplication on the database side.

---
*Written by model - [Gemini 3.1 Pro Reasoning]*