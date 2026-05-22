# Audit: WF-ONBOARD

## 1. Current Logic Assessment
This is the most complex workflow in the pipeline — a multi-step onboarding wizard that crawls a new client's website, performs LLM site analysis, presents a Slack questionnaire for human review, runs cross-validation against the crawl data, and writes the client, niches, competitors, and gold examples to Supabase. It uses three webhook triggers chained in sequence to handle Slack interactivity (questionnaire submission and flag acknowledgement). Overall health is **fair but fragile** — the core HITL pattern works but has several promised features that are not implemented, and the error handling is thin for such a long-running, multi-webhook workflow.

## 2. Identified Shortcomings & Doubts
- [ ] Issue 1: **No competitor_brand_names Table Write:** The sticky note lists `competitor_brand_names` as an output, but no node in the workflow writes to this table. The `Build_DB_Writes` node constructs `competitors: q.competitors.map(c => ({ domain: c }))` but this array is never sent to Supabase. Competitor data from the questionnaire is silently lost.
- [ ] Issue 2: **No gold_examples Table Write:** Similarly, `gold_examples` is listed as an output, and `Build_DB_Writes` constructs seed gold examples from proposed pillars. But no HTTP Request node writes them to the Supabase `gold_examples` table. These seed examples are critical for WF-02's Tier 1 embedding similarity scoring.
- [ ] Issue 3: **No cross_validation_events Table Write:** The sticky note promises `cross_validation_events` output, but no node writes to this table. The cross-validation LLM response is used only to decide flag routing — the validation result itself is never persisted for audit or trend analysis.
- [ ] Issue 4: **The SDK (`wf-onboard.ts`) and Export JSON Differ Significantly:** The SDK version has fewer nodes, uses `$("Parse_Questionnaire_Response")` in expressions, and has a cleaner data flow. The export JSON has additional nodes (`Build_LLM_Request`, `Extract_Client_ID`, `Write_Niches`) that aren't in the SDK. This suggests the export JSON was hand-edited or generated from a different source. The deployed n8n version may be a third variant. **Trust what's in the n8n editor**, not either file.
- [ ] Issue 5: **No Error Handling for Sitemap Fetch Failure:** The `Fetch_Sitemap` node has a 15-second timeout but no error handler. If the client's website is down, behind a CDN/WAF that blocks the request, or has no sitemap, the entire onboarding flow crashes at step 1 with no useful feedback to the user.
- [ ] Issue 6: **Aggregate_Page_Data Output Field Name Uncertainty:** The aggregate node uses `aggregate: "aggregateAllItemData"` without specifying a `destinationFieldName`. The default could be `data` or `aggregatedData` depending on n8n version. `Build_LLM_Request` references `$input.first().json.data` — if the actual field name differs, the LLM receives an empty pages array.
- [ ] Issue 7: **No Handling for Partial Questionnaire Data:** If the Slack questionnaire is submitted with empty required fields (no pillars, no ICP persona), `Build_DB_Writes` creates a client with empty config. There's no validation that the questionnaire has meaningful data before writing to Supabase.
- [ ] Issue 8: **Cross-Validation Happens After Questionnaire But Before DB Write:** If flags are raised, the human acknowledges them via a Slack button, which triggers `Wait_For_Flag_Ack`. But the questionnaire data is not modified during this acknowledgement — the flags are informational only. The original (potentially inconsistent) data is still written to the database. There's no mechanism to actually fix flagged issues.
- [ ] Issue 9: **Client Slug Collision Risk:** `Build_DB_Writes` generates a slug: `(q.client_name || '').toLowerCase().replace(/[^a-z0-9]+/g, '-')`. Two clients with the same name (or similar names after sanitization) produce the same slug, causing a unique constraint violation on the `clients` table.
- [ ] Issue 10: **Navigation Competitor Strategy and Monthly Budget Not Written:** The questionnaire captures `navigational_competitor_strategy` and `monthly_api_budget_usd`, but these are NOT included in the `config` object in `Build_DB_Writes`. The config only has hardcoded defaults: `navigational_competitor_strategy: "allow_comparison_only"` and `monthly_api_budget_usd: 50`. Any custom values from the questionnaire form are ignored.

## 3. Scope for Improvement
The three missing table writes (competitor_brand_names, gold_examples, cross_validation_events) should be implemented — they're foundational data for downstream workflows. Adding the missing config fields (nav strategy, budget) makes the questionnaire form actually functional. Validation after questionnaire parsing catches empty submissions before they corrupt the database. A sitemap fetch failure should produce a graceful Slack notification instead of a crash.

## 4. Execution Plan (For Next Agent)
1. **Write competitor_brand_names to Supabase:** Add a new HTTP Request node after `Write_Niches` that POSTs to `/rest/v1/competitor_brand_names`. Use `$json.db_writes.competitors` (the array built in `Build_DB_Writes`). Add `client_id: $json.client_id` to each record. Set `Prefer: return=minimal` header.
2. **Write gold_examples to Supabase:** Add another HTTP Request node after the competitor write. POST to `/rest/v1/gold_examples`. Use `$json.db_writes.gold_examples`. Add `client_id: $json.client_id` and `source: 'onboarding_llm_seed'` to each record.
3. **Write cross_validation_events to Supabase:** After `Parse_CrossVal_Response`, add a node that writes the validation result to `/rest/v1/cross_validation_events`. Include: `client_id`, `pipeline_run_id`, `validation_result` (the full JSON), `had_flags` (boolean), `summary`. Do this regardless of whether flags were raised (write empty flags too, for audit completeness).
4. **Add Questionnaire Validation:** In `Parse_Questionnaire_Response`, after parsing, add validation checks:
   ```
   if (!questionnaire.service_pillars || questionnaire.service_pillars.length === 0) {
     // Send a Slack message back: "Questionnaire submitted with no service pillars. Please re-submit."
     // Then throw an error to halt execution
   }
   if (!questionnaire.icp_persona || questionnaire.icp_persona.length < 20) {
     // Same pattern — require meaningful ICP persona
   }
   ```
5. **Fix Missing Config Fields in Build_DB_Writes:** Add `navigational_competitor_strategy` and `monthly_api_budget_usd` from `q` (questionnaire) into the `config` object:
   ```
   navigational_competitor_strategy: q.navigational_competitor_strategy || 'allow_comparison_only',
   monthly_api_budget_usd: q.monthly_api_budget_usd || 50,
   ```
6. **Add Slug Uniqueness:** In `Build_DB_Writes`, append a short random suffix to the slug to prevent collisions:
   ```
   slug: baseSlug + '-' + Math.random().toString(36).slice(2, 6)
   ```
   Or better, check for existing slugs via a Supabase GET before writing and increment a counter if needed.
7. **Graceful Sitemap Fetch Failure:** Before `Fetch_Sitemap`, add an If/Else check: try the sitemap fetch. If it fails (HTTP error or timeout), instead of crashing, send a Slack card saying "Could not crawl sitemap for {url}. Onboarding will continue with manual inputs only. Please verify the site is accessible." Set `$json.pages = []` and skip the crawl/extraction steps, proceeding directly to the LLM analysis with empty pages (which will produce low-confidence results).
8. **Align JSON Export with Deployed n8n Version:** Before implementing any of these changes, open each workflow in the n8n editor and compare the live nodes with the export JSON. If the live version differs significantly, audit that version instead and document the differences in the export file header.

---
*Written by model - [DeepSeek V4 Pro]*
