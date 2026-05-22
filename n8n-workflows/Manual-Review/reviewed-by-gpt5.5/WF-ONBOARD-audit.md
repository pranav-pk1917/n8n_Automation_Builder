# Audit: WF-ONBOARD

## 1. Current Logic Assessment
This workflow is intended to onboard a client in phases: start from a webhook, crawl the website, use an LLM to propose client strategy, send a Slack questionnaire, parse the human response, cross-validate the response, optionally wait for flag acknowledgement, write client configuration into Supabase, log costs, complete the pipeline run, and notify Slack.

Overall health: requires major correction before relying on it. The business process is good, but the exported workflow connects multiple webhook triggers as if they are wait nodes, and later phases reference data from earlier executions that will not be available unless persisted.

Current logic map:
1. `Webhook_Trigger` starts Phase A.
2. `Validate_Payload`, `Create_Pipeline_Run`, and `Merge_Run_ID` prepare onboarding context.
3. `Fetch_Sitemap`, `Parse_Sitemap_XML`, `SplitInBatches_Pages`, `Crawl_Page`, and `Extract_Page_Content` collect page data.
4. `Aggregate_Page_Data` and `Build_LLM_Request` prepare site analysis.
5. `LLM_Site_Analysis` returns strategy suggestions.
6. `Build_Slack_Questionnaire` builds a Slack message with input blocks.
7. `Send_Questionnaire_Card` posts to Slack.
8. The graph connects to `Wait_For_Questionnaire`, a separate webhook trigger.
9. `Parse_Questionnaire_Response` parses Slack payload values.
10. `Build_CrossVal_Request` references `Build_Slack_Questionnaire` from Phase A.
11. The workflow optionally goes through `Wait_For_Flag_Ack`, another webhook trigger.
12. `Build_DB_Writes`, `Write_Client`, `Write_Niches`, `Log_API_Costs`, `Update_Pipeline_Run`, `Send_Completion_Notification`, and `Respond_OK` complete onboarding.

## 2. Identified Shortcomings & Doubts
- [ ] Issue 1: `SplitInBatches_Pages` is wired from output 0 to `Crawl_Page` and has no loop-back. For SplitInBatches v3, process batches from output 1 and finish from output 0.
- [ ] Issue 2: `Wait_For_Questionnaire` and `Wait_For_Flag_Ack` are webhook trigger nodes connected mid-flow. Webhook triggers start separate executions; they do not pause and resume the Phase A execution.
- [ ] Issue 3: `Build_CrossVal_Request` references `$('Build_Slack_Questionnaire').first().json.crawl_analysis`. That data will not exist in the separate questionnaire webhook execution.
- [ ] Issue 4: The flag acknowledgement path feeds the ack webhook payload into `Build_DB_Writes`, but the ack payload does not contain the questionnaire or crawl analysis context.
- [ ] Issue 5: `Build_Slack_Questionnaire` sends Slack `input` blocks inside a `chat.postMessage` message. Slack input blocks are for modals and App Home, not ordinary channel messages.
- [ ] Issue 6: `Parse_Questionnaire_Response` expects `payload.view.state.values`, but the workflow posts a message button, not a modal submission. The questionnaire fields will not be submitted in the expected shape.
- [ ] Issue 7: `Build_DB_Writes` prepares `competitors` and `gold_examples`, but the graph never writes `competitor_brand_names` or `gold_examples`.
- [ ] Issue 8: `Write_Niches` assumes `q.niches` exists. If Slack parsing fails or returns no niches, the Code node can throw before completing the pipeline run.
- [ ] Issue 9: `Create_Pipeline_Run` starts a run, but there is no durable onboarding session table or row to reconnect Phase A, Phase B, and Phase C.
- [ ] Issue 10: The initial sitemap crawl has no fallback when `/sitemap.xml` is missing, blocked, or a sitemap index.

## 3. Scope for Improvement
Do not try to keep this as one continuous workflow with connected webhook triggers. Split it into clear phases or persist state between webhooks. The minimum safe design is three workflows or three trigger branches backed by an `onboarding_sessions` table keyed by `pipeline_run_id`.

## 4. Execution Plan (For Next Agent)
1. Split WF-ONBOARD into three explicit workflows or three independent trigger sections: `WF-ONBOARD-A-Start`, `WF-ONBOARD-B-Questionnaire`, and `WF-ONBOARD-C-Flag-Ack`. If staying in one n8n workflow, do not connect webhook trigger nodes as if they are normal wait nodes.
2. Create or use a Supabase table named `onboarding_sessions` with at least: `pipeline_run_id`, `client_name`, `client_url`, `crawl_analysis`, `llm_cost`, `questionnaire`, `validation_pass1`, `status`, `created_at`, and `updated_at`.
3. In Phase A, after `Build_Slack_Questionnaire`, write the context into `onboarding_sessions` before posting Slack.
4. Replace the Slack questionnaire message with a valid Slack modal flow: post a message with an "Open Questionnaire" button, then use Slack `views.open` from the interaction handler to present inputs in a modal.
5. Update Phase B (`wf-onboard-questionnaire-response`) to parse `payload.view.state.values` from the modal submission and extract `pipeline_run_id` from `private_metadata`.
6. At the start of Phase B, fetch the matching `onboarding_sessions` row by `pipeline_run_id`; do not reference Phase A nodes directly.
7. In Phase B, run cross-validation using persisted `crawl_analysis` plus the submitted questionnaire, then update `onboarding_sessions.validation_pass1` and `onboarding_sessions.questionnaire`.
8. If flags exist, send a Slack acknowledgement message with `pipeline_run_id` in the button value and set session `status = "waiting_flag_ack"`.
9. In Phase C, fetch `onboarding_sessions` by `pipeline_run_id` before `Build_DB_Writes`; do not rely on ack payload fields except the session key.
10. If no flags exist in Phase B, route directly to the DB write subflow using the fetched session context.
11. Update `Build_DB_Writes` to guard arrays: `const niches = Array.isArray(q.niches) ? q.niches : [];` and same for competitors and service pillars.
12. Add missing write nodes after `Write_Niches`: `Write_Competitor_Brand_Names` and `Write_Gold_Examples`. Use the prepared `db_writes.competitors` and `db_writes.gold_examples`, each enriched with `client_id`.
13. Fix the page crawl loop: connect `SplitInBatches_Pages` output 1 to `Crawl_Page`, loop `Extract_Page_Content` back to `SplitInBatches_Pages`, and send output 0 to `Aggregate_Page_Data`.
14. Add sitemap fallback: if `/sitemap.xml` returns no page URLs, create a small fallback URL list with root, `/services`, `/about`, `/case-studies`, and any paths from `seed_keywords` or payload hints.
15. Test all three phases independently with one `pipeline_run_id`. Verify the session row persists Phase A data, Phase B can cross-validate without Phase A node references, and Phase C can write the client after a flag acknowledgement.

---
*Written by model - [GPT-5.5 HIgh Reasoning]*
