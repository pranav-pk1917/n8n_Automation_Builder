# Audit: WF-ONBOARD Client Onboarding

## 1. Current Logic Assessment
Three webhooks form three independent executions: Phase A (`wf-onboard-start`) validates payload, creates a `pipeline_runs` row, fetches sitemap, batches and crawls up to 20 pages (5 per batch), aggregates, runs `LLM_Site_Analysis`, and posts a Slack questionnaire card. Phase B (`wf-onboard-questionnaire-response`) parses the Slack submission, runs `LLM_CrossValidate`, branches on `has_flags`: if true, posts a flag-review card and waits on Phase C; if false, writes `clients` + `niches`, completes the run, posts a Slack completion notification. Phase C (`wf-onboard-flag-response`) merges back into the DB-write chain.

Overall health: **Requires improvement**. The three-phase split is correct because Slack interactivity is inherently asynchronous, but the workflow misuses n8n's webhook nodes as if they were Wait nodes, references Phase A node outputs from Phase B (impossible across executions), omits writes for competitors and seed keywords, and has no session state in Supabase so Phase B cannot reliably reconstruct Phase A's context.

## 2. Identified Shortcomings & Doubts
- [ ] **Issue 1 — Webhook triggers used as wait nodes.** `Wait_For_Questionnaire` and `Wait_Flag_Ack` are `n8n-nodes-base.webhook` triggers — each begins a NEW execution. They are not part of the Phase A execution context. Any expression in Phase B reading `$('Validate_Payload').item.json` (a Phase A node) will be undefined.
- [ ] **Issue 2 — No persisted session.** Phase A creates a `pipeline_runs` row but does not persist the crawl results, the LLM site analysis output, or the input fields. Phase B receives only the Slack interactive payload — `pipeline_run_id` is the only handle — and must re-fetch everything. There is no `onboarding_sessions` table or `pipeline_runs.context_jsonb` write.
- [ ] **Issue 3 — Phase B re-runs `LLM_CrossValidate` without the crawl context.** Cross-validation compares the questionnaire vs the crawl — but the crawl output is in Phase A's execution log, not in any DB table. The LLM is effectively cross-validating against `null`.
- [ ] **Issue 4 — Slack input fields posted as channel message blocks.** Per `Build_Slack_Questionnaire`, the prefilled text is sent into a chat message. Input fields belong in a Slack **modal** (`views.open`) triggered by a button click. As built, users cannot edit anything inline; they can only react.
- [ ] **Issue 5 — Competitors and seed keywords never persisted.** Phase A receives `competitors[]` and `seed_keywords[]` but `Write_Client` and `Write_Niches` do not write a `competitors` table, a `seed_keywords` table, nor a `clients.config.competitors` / `clients.config.seed_keywords` field. The data is lost after the Slack card is sent.
- [ ] **Issue 6 — Gold examples not collected.** WF-02 requires `pos_centroid`/`neg_centroid` from gold examples; onboarding is the natural place to collect 5–10 positive and 5–10 negative example keywords. The questionnaire does not ask for them.
- [ ] **Issue 7 — `Parse_Sitemap_XML` 20-URL cap with naive path scoring.** A WP site with a sitemap index returns the index, not page URLs; the parse silently returns zero. The path-priority scoring (service/about-style) is a Code regex that breaks on multilingual sites.
- [ ] **Issue 8 — `Batch_Pages` may have the same SplitInBatches v3 wiring bug as WF-00** (output 0 = done, output 1 = loop). Verify in the export; if so, batch processing only runs the first 5 pages.
- [ ] **Issue 9 — `Fetch_Sitemap` and `Crawl_Page` have no `continueOnFail`.** Any 5xx/timeout aborts the whole onboarding execution; the `pipeline_runs` row is stuck `running`.
- [ ] **Issue 10 — No retry/timeout on `LLM_Site_Analysis` and `LLM_CrossValidate`.** OpenRouter occasionally 429s; the onboarding fails and the human has no clean re-entry path.
- [ ] **Issue 11 — `Respond_OK` placement.** Phase A should respond 200 immediately after `Create_Pipeline_Run` so the caller knows the start succeeded; instead it appears to be in Phase B only.
- [ ] **Issue 12 — No "resume from Phase B without Phase A context" fallback.** If Phase A succeeded but Phase B is triggered hours later, the only way to reconstitute state is a DB lookup — but there is no row to look up (per Issue 2).

## 3. Scope for Improvement
Keep the three-phase architecture. Add a `onboarding_sessions` table (or use `pipeline_runs.context_jsonb`) to persist Phase A output so Phase B/C can re-hydrate. Move the questionnaire into a Slack modal. Persist competitors, seed keywords, and ask for gold examples. Fix the SplitInBatches wiring, add `continueOnFail` on crawl steps, and respond 200 in Phase A immediately after the run row is created.

## 4. Execution Plan (For Next Agent)
1. **Schema check.** Before creating a new table, verify whether `pipeline_runs.context_jsonb` (or `metadata jsonb`) exists. If yes, use it; if no, create:
   ```sql
   CREATE TABLE onboarding_sessions (
     pipeline_run_id uuid PRIMARY KEY REFERENCES pipeline_runs(id),
     client_url text NOT NULL,
     client_name text NOT NULL,
     competitors text[] DEFAULT '{}',
     seed_keywords text[] DEFAULT '{}',
     crawled_pages jsonb DEFAULT '[]',
     llm_site_analysis jsonb,
     questionnaire_response jsonb,
     cross_validation jsonb,
     status text DEFAULT 'phase_a',
     created_at timestamptz DEFAULT now(),
     updated_at timestamptz DEFAULT now()
   );
   ```
2. **Phase A: respond first.** Move `Respond_OK` to fire immediately after `Create_Pipeline_Run`, returning `{ pipeline_run_id }` to the caller. The rest of Phase A runs after the response (n8n supports this via "Respond to Webhook: When the last node finishes" vs. "Immediately").
3. **Phase A: persist context.** After `Aggregate_Pages` and `LLM_Site_Analysis`, insert a `Write_Onboarding_Session` HTTP POST writing `crawled_pages`, `llm_site_analysis`, `competitors`, `seed_keywords`, `client_url`, `client_name` keyed by `pipeline_run_id`. Set `status='phase_a_complete'`.
4. **Phase A: fix sitemap-index handling and batch wiring.** Apply the same fixes documented in WF-00 audit Issues 5/7 (sitemap index detection, dedupe) and Issue 1 (SplitInBatches output 1 = loop). Add `continueOnFail: true` on `Crawl_Page`.
5. **Phase A: convert Slack message to modal trigger.** `Send_Questionnaire_Card` should post a single channel message with a button "Open Onboarding Form". The button payload value = `pipeline_run_id`. Create a separate webhook `wf-onboard-modal-trigger` that handles the button click, fetches the session from Supabase, calls Slack `views.open` with a `modal` view containing input blocks pre-filled from `llm_site_analysis`. The modal's `submit` action goes to `wf-onboard-questionnaire-response` (Phase B).
6. **Phase B: re-hydrate from Supabase.** First node after `Parse_Questionnaire_Response` must be `Fetch_Onboarding_Session` (GET `onboarding_sessions?pipeline_run_id=eq.<id>`). Pass `crawled_pages` and `llm_site_analysis` into `LLM_CrossValidate` so it can actually cross-validate.
7. **Phase B: persist questionnaire + cross-val.** PATCH `onboarding_sessions.questionnaire_response` and `cross_validation`, set `status='phase_b_complete'` (or `'awaiting_flag_ack'` if `has_flags`).
8. **Phase C: re-hydrate from Supabase.** `Wait_Flag_Ack` → `Fetch_Onboarding_Session` → continue to DB writes.
9. **Persist competitors, seed keywords, gold examples.** In `Write_Client`, set `config.competitors`, `config.seed_keywords`, `config.gold_examples` (positive + negative arrays). Add fields to the questionnaire modal asking the human to confirm/edit each list.
10. **Add gold-examples step.** Questionnaire modal should ask: "Provide 5 keywords your ideal customer would type" (positive) and "Provide 5 keywords that look related but are NOT your ICP" (negative). Persist to `clients.config.gold_examples = { positive: [...], negative: [...] }`. WF-02 reads from here.
11. **Idempotency.** If a `clients` row with the same `canonical_domain` already exists, Phase B should PATCH it rather than insert a duplicate; otherwise `clients` collects orphan rows from re-runs.
12. **Error workflow** per CW-1: any uncaught error PATCHes `pipeline_runs.status = failed` AND `onboarding_sessions.status = 'failed'` with the error message, plus a Slack alert to the channel.
13. **Retries.** Enable node retry on `LLM_Site_Analysis` and `LLM_CrossValidate` (3 attempts, 5s backoff). Add `response_format: { type: 'json_object' }` to both.
14. Smoke test: Phase A with a WP site (sitemap index) → confirm 20 pages crawled, session row written, Slack button posted, 200 response in <2s. Click modal, submit → Phase B reads session, cross-val LLM sees actual pages. Phase C ack → client row written with competitors, seed keywords, and gold examples in `config`.

---
*Written by model - [Opus 4.7 medium thinking]*
