# Architecture Review: Manual Workflow Audits

**Role:** Lead Architecture Reviewer  
**Scope:** All seven manual audits in [Manual-Review](.) cross-checked against workflow exports in [../exports](../exports) and design docs in [../docs](../docs).  
**Date:** 2026-05-21

---

## 1. The Verdict

**NO** — The audit has blind spots, misunderstandings, or requires revision before building.

The seven workflow audits are unusually strong on local n8n plumbing: SplitInBatches v3 output wiring, missing loopbacks, webhook-as-wait misuse, PostgREST `$json.client_id` failures, and per-node context loss after Supabase writes. Those findings were verified against [wf-00-page-inventory.json](../exports/wf-00-page-inventory.json) and align with the exported graphs.

However, the audit set has **systemic blind spots** that no single workflow file owns, plus a few **over-engineered prescriptions** and **unresolved build-time decisions** (WF-05 tab contract, WF-04 formula ambiguity in the audit text). Proceeding to the build phase without amending the audit files and documenting cross-workflow concerns will reproduce the same class of bugs at the pipeline level.

---

## 2. Methodology

1. Read all seven audit files: WF-00 through WF-05 and WF-ONBOARD.
2. Cross-checked WF-00 audit claims against [wf-00-page-inventory.json](../exports/wf-00-page-inventory.json):
   - `Batch_Pages` connects output index 0 to `Fetch_Page_HTML` (done path, not loop path).
   - No loop-back from `Upsert_Page` to `Batch_Pages`.
   - `Upsert_Page` connects directly to `Complete_Run` (per-page completion).
   - `Parse_Sitemap` comment claims dedupe but code does not dedupe.
   - `Merge_Client_Run` uses `$('Split_Clients').item.json` after `Create_Run` HTTP POST.
3. Compared WF-04 audit execution plan against [WF-04.md](../docs/WF-04.md) for the canonical priority formula.
4. Evaluated each audit against: completeness (bottlenecks, error handling, edge cases), contextual accuracy (fit with existing architecture), and over-engineering.

---

## 3. Critical Blind Spots

### Cross-workflow (none of the seven audits address these)

| ID | Blind spot | Impact |
|----|------------|--------|
| **CW-1** | **No global failure path for `pipeline_runs`.** Every workflow creates a run with `status='running'`. None prescribe an n8n Error Workflow that PATCHes the run to `status='failed'` with the error message on uncaught exceptions. | Runs stuck in `running` indefinitely after any mid-flow failure (WF-00, WF-01, WF-02, WF-03, WF-04, WF-ONBOARD). |
| **CW-2** | **No idempotency / retry contract.** No guidance for manual re-runs or cron overlap. | WF-00 re-embeds every page nightly; WF-04 may re-charge SerpAPI/LLM if the gate is `priority_score` null instead of `scored_at IS NULL`. |
| **CW-3** | **PostgREST array-vs-object pitfall treated locally, not as a standard.** WF-03 Issue 1 and WF-04 Issue 1 are the same root cause: `{{ $json.client_id }}` after a Supabase GET that returns `[{ ... }]`. | Repeated one-off fixes; inconsistent context handling across workflows. |
| **CW-4** | **Inter-workflow orchestration is undefined.** The real pipeline is WF-01 → WF-02 → WF-03 → WF-04 (webhook chain) with shared `pipeline_run_id`; WF-00 and WF-05 are cron-only. No audit defines who triggers whom or how `pipeline_run_id` propagates. | Build agent will wire triggers inconsistently or omit downstream kicks. |
| **CW-5** | **n8n execution timeout not considered.** WF-00 (per-page HTTP + embedding for entire client) and WF-02 (full keyword set + embeddings + borderline LLM) can exceed default execution limits on large clients. | Silent truncation or failed runs with no partial-state recovery. |

### Per-workflow

#### WF-00 — Page Inventory

| Issue | What the audit missed or got wrong |
|-------|-----------------------------------|
| **PairedItem brittleness** | `Merge_Client_Run` uses `$('Split_Clients').item.json` after `Create_Run` (HTTP POST returning a Supabase array). With multiple active clients in one execution, `pipeline_run_id` can cross-pollinate between clients. Not in audit. |
| **Sitemap index handling** | Audit Plan step 7 says "if sitemap indexes are expected." WordPress (confirmed by `Fetch_WP_Posts` GraphQL) ships sitemap indexes by default. This must be **required**, not conditional. |
| **Idempotency** | No skip for pages already embedded recently (`last_seen_at` within ~20h unless content hash changed). Nightly cron will re-embed and re-bill every page. |

Audit Issues 1–7 are **correct** and verified in export JSON.

#### WF-01 — Ingest

| Issue | What the audit missed or got wrong |
|-------|-----------------------------------|
| **RFC4180 parser over-engineering** | Plan step 9 prescribes hand-rolling RFC4180 in a Code node. Safer: `Spreadsheet File` node or require pre-parsed JSON on the webhook. |
| **Schema verification** | Plan step 5 prescribes unique index `(client_id, keyword)` without requiring verification against current Supabase schema first. |

Audit Issues 1–6 and chunk-loop fixes are **correct**.

#### WF-02 — Tiered Filter

| Issue | What the audit missed or got wrong |
|-------|-----------------------------------|
| **Gold-example centroids** | Plan step 5 outputs `pos_centroid` / `neg_centroid` but never states they require a **prior embedding call** on gold examples before Tier 1 scoring. |
| **Embedding API limits** | No mention of OpenAI limits (8191 tokens/input, batch partial failures). A single oversized keyword can fail a 100-keyword batch. |
| **LLM rate limits** | Plan addresses SerpAPI retries in WF-04 but WF-02 has no equivalent for borderline `LLM_Classify` calls at scale. |

Audit Issues 1–9 are **correct** for tier ordering, batchIndex, chunk offsets, and Tier 1 write gap.

#### WF-03 — Cluster

| Issue | What the audit missed or got wrong |
|-------|-----------------------------------|
| **Cannibalization over-engineered** | Plan step 10 proposes in-n8n cosine similarity against `pages.embedding`. WF-00 already stores embeddings in Supabase with pgvector. Correct approach: Supabase RPC `find_cannibalization_candidates(cluster_centroid, client_id, threshold)`. |
| **Magic threshold** | `0.82` in Plan step 10 has no source. Should be `clients.config.cannibalization_threshold` with documented default. |
| **Single-member clusters** | No handling when worker returns clusters with one member (labeling and head-term quality). |

Audit Issues 1–6, 8–9 are **correct**. Issue 7 (cannibalization missing) is correct but the prescribed fix is the wrong layer.

#### WF-04 — ICP Score

| Issue | What the audit missed or got wrong |
|-------|-----------------------------------|
| **Priority formula not cited in audit** | Audit Issue 4 and Plan step 7 say "does not match documented formula" but do not embed the formula. Canonical version from [WF-04.md](../docs/WF-04.md): `priority_score = (icp_score × 0.35) + (commercial_intent_score × 0.25) + (volume_norm × 0.20) + (0.20)` where `volume_norm = min(keyword_count / 100, 1.0)` and KD is a **fixed 0.20 placeholder** in current docs—not `total_volume` / `avg_kd` unless docs are intentionally being changed. Build agent needs explicit owner decision: keep deployed placeholder formula or upgrade to real `total_volume` / `avg_kd`. |
| **LLM rate limits** | Plan step 9 adds Wait/retry for SerpAPI only; `LLM_ICP_Score` at 100 clusters has identical 429 risk. |
| **Gate field** | Docs say `icp_score IS NULL`; audit should align fetch filter on `scored_at IS NULL` (or both) for idempotency. |

Audit Issues 1–3, 5–8 are **correct** for context loss and multi-response.

#### WF-05 — Sheet Sync

| Issue | What the audit missed or got wrong |
|-------|-----------------------------------|
| **Contract left open** | Issue 7 correctly flags docs vs export disagreement but punts the decision to the builder. Reviewer must lock the contract now. |

Audit Issues 1–6 are **correct** for `.first()` cross-client bleed and flat-row shape.

#### WF-ONBOARD

| Issue | What the audit missed or got wrong |
|-------|-----------------------------------|
| **New table without schema check** | Plan step 2 prescribes `onboarding_sessions` without requiring inspection of existing schema (e.g. `pipeline_runs.context_jsonb`) first. |

Audit Issues 1–10 are **correct** for webhook-as-wait, Slack modal misuse, and missing writes.

---

## 4. Suggested Course Correction

Amend each audit file **before** the build phase. Do not edit workflow JSON until these are done.

### Shared: new section for every audit (or one appendix file)

Add to [README.md](../README.md) a **Cross-Workflow Concerns** section documenting CW-1 through CW-5:

- **CW-1:** Error Workflow template that PATCHes `pipeline_runs` to `failed`.
- **CW-2:** Idempotency rules per workflow (see per-file amendments below).
- **CW-3:** Standard `Unwrap_PostgREST` Code node after every Supabase GET.
- **CW-4:** Orchestration diagram: WF-01 POST success → Execute Workflow / HTTP POST WF-02 with same `pipeline_run_id` → WF-03 → WF-04; WF-00 and WF-05 cron-only.
- **CW-5:** WF-00 and WF-02 use `Execute Workflow` per client to avoid execution timeout.

---

### [WF-00-Page-Inventory-audit.md](WF-00-Page-Inventory-audit.md)

**Add to §2 Identified Shortcomings:**

- [ ] **Issue 8:** `Merge_Client_Run` pairs back to `Split_Clients` via `$('Split_Clients').item.json` after `Create_Run`. Multi-client executions can assign the wrong `pipeline_run_id`. Replace with explicit merge of `Create_Run` response + current client item (no cross-execution `.item` reference).
- [ ] **Issue 9:** No idempotency. Nightly cron re-embeds all pages. Skip pages where `last_seen_at` is within the last 20 hours unless `text_for_embedding` hash changed.

**Amend §4 Execution Plan:**

- **Step 7:** Change "If sitemap indexes are expected" → **Required:** detect `<sitemap><loc>`, fetch child sitemaps, merge URLs before `Parse_Sitemap`.
- **Add step 10:** Before `Embed_Page`, filter batch items against existing `pages` rows (recent `last_seen_at` + unchanged hash).

---

### [WF-01-Ingest-audit.md](WF-01-Ingest-audit.md)

**Amend §4 Execution Plan:**

- **Step 5:** Prefix with: "Verify `(client_id, keyword)` unique index exists in Supabase schema before creating migration."
- **Replace step 9:** Do not hand-roll RFC4180 in Code. Use n8n `Spreadsheet File` node for CSV parsing, OR change webhook contract to accept `records: [{ keyword, volume, kd, ... }]` JSON and deprecate raw CSV for production imports.

---

### [WF-02-Tiered-Filter-audit.md](WF-02-Tiered-Filter-audit.md)

**Add to §2:**

- [ ] **Issue 10:** `pos_centroid` / `neg_centroid` require embedding gold examples first. Add `Embed_Gold_Examples` before `Prepare_Tier1`; Tier 1 must not start until centroids exist.
- [ ] **Issue 11:** OpenAI embedding API limits (8191 tokens per input, batch partial failures). Add per-keyword length guard and handle failed inputs in batch without failing the whole chunk.

**Amend §4:**

- **Before current step 5:** Insert step: "Add `Embed_Gold_Examples` after `Fetch_Gold_Examples`; compute centroids; pass into `Merge_Tier1_Inputs`."
- **Add to step 14:** Add Wait/retry on `LLM_Classify` (same pattern as SerpAPI in WF-04).

---

### [WF-03-Cluster-audit.md](WF-03-Cluster-audit.md)

**Amend §4 Execution Plan:**

- **Replace step 10** with: "Add Supabase RPC `find_cannibalization_candidates(p_client_id, p_centroid, p_threshold)` using pgvector on `pages.embedding`. Set `cannibalization_risk_page_id` from RPC result. Threshold from `clients.config.cannibalization_threshold` (default `0.82`). Do not compute cosine similarity in n8n Code."
- **Add step 13:** "If cluster `member_ids.length === 1`, set `review_flags` to include `single_member_cluster` and skip LLM labeler or use keyword text as head term."

---

### [WF-04-ICP-Score-audit.md](WF-04-ICP-Score-audit.md)

**Amend §2 Issue 4** — append canonical formula from [WF-04.md](../docs/WF-04.md):

```
priority_score = (icp_score × 0.35) + (commercial_intent_score × 0.25) + (volume_norm × 0.20) + 0.20
volume_norm = min(keyword_count / 100, 1.0)   // deployed placeholder; KD fixed at 0.20
```

Add owner decision note: upgrade to `total_volume` / `avg_kd` only if docs and product agree.

**Amend §4:**

- **Step 4:** Fetch filter must use `scored_at=is.null` (align with docs `icp_score` null—use whichever column is authoritative; document one gate).
- **Step 7:** Replace vague "documented priority formula" with the formula block above.
- **Add step 9b:** "Add Wait/retry on `LLM_ICP_Score` identical to SerpAPI pattern in step 9."

---

### [WF-05-Sheet-Sync-audit.md](WF-05-Sheet-Sync-audit.md)

**Resolve Issue 7 in §2** — replace open question with decision:

> **Decision (locked):** Output contract is **`Clusters`** tab + **`Cost`** tab only. No per-pillar tabs until reporting requirements justify them.

**Amend §4 step 1:** Remove "Decide the output contract" and "Recommended." Replace with: "Implement `Clusters` and `Cost` tabs per locked contract above."

---

### [WF-ONBOARD-audit.md](WF-ONBOARD-audit.md)

**Amend §4 step 2:** Prefix with:

> "Inspect current Supabase schema. If `pipeline_runs.context_jsonb` (or equivalent) exists, persist Phase A/B/C state there. Create `onboarding_sessions` only if no suitable column/table exists."

---

## 5. Items Confirmed Correct (Do Not Re-debate)

These findings in the original audits are accurate and should be implemented as written:

| Workflow | Confirmed finding |
|----------|-------------------|
| WF-00 | SplitInBatches v3: output 0 = done, output 1 = loop (Issues 1–2). `Complete_Run` per page (Issue 3). No page-level `continueOnFail` (Issue 4). `Parse_Sitemap` no dedupe (Issue 5). Hardcoded WP GraphQL URL (Issue 6). |
| WF-01 | Graveyard IDs unused in dedupe (Issue 1). 50k range cap (Issue 3). Per-chunk webhook respond (Issue 4). |
| WF-02 | Tier 0 does not gate Tier 1 (Issue 1). `batchIndex` missing (Issue 4). Tier 1 classifications never written (Issue 7). HITL branch blocks respond (Issue 8). |
| WF-03 | `$json.client_id` after client fetch (Issue 1). `keyword_cluster_map` never written (Issue 4). Context lost after `Write_Cluster` (Issues 5–6). Per-cluster webhook respond (Issue 8). |
| WF-04 | Context loss after `Fetch_Client_Config` (Issue 1). Multi webhook respond (Issue 3). `Update_Cluster_Score` patches only `priority_score` (Issue 5). |
| WF-05 | `.first()` cross-client data bleed (Issue 1). Only Cost tab written (Issue 2). Nested arrays to Sheets (Issue 3). |
| WF-ONBOARD | Webhook triggers used as wait nodes (Issue 2). Phase B references Phase A nodes (Issue 3). Slack input blocks in channel message (Issue 5). Missing competitor/gold writes (Issue 7). |

---

## 6. Gate Criteria for Build Phase

All three must be satisfied before any workflow JSON is edited in n8n:

- [ ] **Audit amendments complete** — All seven files updated per Section 4 above.
- [ ] **Cross-workflow doc published** — [README.md](../README.md) (or equivalent) contains CW-1 through CW-5 with orchestration diagram and Error Workflow requirement.
- [ ] **Owner decisions recorded**
  - WF-04: Keep deployed priority formula (keyword_count proxy + fixed KD 0.20) OR upgrade to `total_volume` / `avg_kd`.
  - WF-05: Locked to `Clusters` + `Cost` tabs (recommended in this review).

---

## 7. Over-Engineering Assessment

| Audit prescription | Verdict |
|--------------------|---------|
| WF-01 RFC4180 Code parser | **Over-engineered** — use `Spreadsheet File` or JSON webhook. |
| WF-03 in-n8n cosine cannibalization | **Over-engineered** — use pgvector RPC. |
| WF-00 batch embeddings "only if volume high" | **Appropriate** — correctly deferred. |
| WF-ONBOARD three-workflow split + session table | **Appropriate** — minimum safe design for Slack HITL; but check existing schema first. |
| WF-05 per-pillar tabs | **Correctly deferred** — lock simpler contract instead. |

---

*Written by model - [Claude Opus 4.7 Medium Reasoning]*
