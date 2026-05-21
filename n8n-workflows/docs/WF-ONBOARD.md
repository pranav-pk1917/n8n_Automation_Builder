# WF-ONBOARD — Client Onboarding

**n8n workflow name:** `WF-ONBOARD`  
**Workflow ID:** `yMld4MwSr3ZHoxti`  
**Open in n8n:** https://n8n-webley-u35816.vm.elestio.app/workflow/yMld4MwSr3ZHoxti

---

## What this workflow does (plain English)

When you add a **new SEO client**, this workflow:

1. Crawls their website sitemap and a sample of pages.
2. Uses AI to suggest service pillars, ICP persona, brand voice, and niches.
3. Sends a **Slack form** so a human can review and correct the AI suggestions.
4. Runs a second AI pass to flag inconsistencies between the form and the crawl.
5. Saves the client, niches, and config into **Supabase**.
6. Notifies Slack when onboarding is complete.

After this runs successfully, the client exists in the database and you can run WF-01 (keywords) and WF-00 (page inventory).

---

## Current features (overview)

| Feature | What it does |
|---------|----------------|
| **Payload validation** | Rejects requests missing `client_url` or `client_name`. |
| **Pipeline run tracking** | Creates a `pipeline_runs` row with status `running`, then `completed`. |
| **Sitemap discovery** | Fetches `/sitemap.xml`, picks up to 20 URLs (prioritizes service/about-style paths). |
| **Page crawl (batched)** | Downloads HTML for pages in batches of 5. |
| **Page content extraction** | Pulls title and meta description from each page. |
| **LLM site analysis** | Gemini via OpenRouter proposes pillars, ICP, brand voice, industries. |
| **Slack questionnaire (HITL)** | Interactive Slack message with pre-filled fields for human review. |
| **Cross-validation (LLM)** | Second LLM pass compares questionnaire vs crawl; may set `has_flags`. |
| **Flag review path** | If flags exist, sends a Slack alert and waits for acknowledge webhook. |
| **Supabase writes** | Inserts `clients`, `niches`, updates `pipeline_runs`. |
| **Completion Slack** | Posts “Client onboarded” with next-step hints. |

---

## Important: three separate runs (not one long execution)

This workflow has **three webhook triggers**. They do **not** automatically chain in a single n8n execution:

| Phase | Webhook path | When it fires |
|-------|--------------|---------------|
| A — Start onboarding | `wf-onboard-start` | You POST to start crawl + Slack form |
| B — Questionnaire submit | `wf-onboard-questionnaire-response` | Slack (or you) POST when form is submitted |
| C — Flag acknowledge | `wf-onboard-flag-response` | Only if cross-validation found issues |

**Phase A** ends after sending the Slack questionnaire (it does not wait for the human).  
**Phase B** is a **new execution** when Slack hits the questionnaire webhook.  
**Phase C** only runs if `has_flags` was true in phase B.

For testing without Slack, you can POST mock payloads to paths B and C manually (see Testing section).

---

## Triggers and URLs

**Base URL:** `https://n8n-webley-u35816.vm.elestio.app`

| Node | Method | Production path | Test path |
|------|--------|-----------------|-----------|
| Webhook_Trigger | POST | `/webhook/wf-onboard-start` | `/webhook-test/wf-onboard-start` |
| Wait_For_Questionnaire | POST | `/webhook/wf-onboard-questionnaire-response` | `/webhook-test/wf-onboard-questionnaire-response` |
| Wait_Flag_Ack | POST | `/webhook/wf-onboard-flag-response` | `/webhook-test/wf-onboard-flag-response` |

---

## Input: Phase A (`wf-onboard-start`)

```json
{
  "client_url": "https://example.com",
  "client_name": "Acme Corp",
  "competitors": ["competitor1.com", "competitor2.com"],
  "seed_keywords": ["digital marketing agency"]
}
```

| Field | Required | Notes |
|-------|----------|-------|
| `client_url` | Yes | Normalized (trailing slash removed). |
| `client_name` | Yes | Display name. |
| `competitors` | No | Array of domain strings. |
| `seed_keywords` | No | Array of seed keyword strings. |

---

## Data flow (Phase A — start)

```
POST wf-onboard-start
        │
        ▼
┌───────────────────┐
│ Validate_Payload  │  Check required fields, normalize URL
└─────────┬─────────┘
          │  { client_url, client_name, competitors, seed_keywords, started_at }
          ▼
┌───────────────────┐
│ Create_Pipeline   │  POST → Supabase pipeline_runs (status: running)
│ _Run              │
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ Merge_Run_ID      │  Attach pipeline_run_id to context
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ Fetch_Sitemap     │  GET client_url/sitemap.xml
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ Parse_Sitemap_XML │  Up to 20 URLs → one item per page
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ Batch_Pages       │  Loop batches of 5 URLs
│   ├─ Crawl_Page   │  GET each page HTML
│   ├─ Extract_     │  title, meta_description per page
│   │  Page_Content │
│   └─ (loop)       │
└─────────┬─────────┘
          │  (when all batches done)
          ▼
┌───────────────────┐
│ Aggregate_Pages   │  Combine all pages into one item: { pages: [...] }
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ LLM_Site_Analysis │  OpenRouter → JSON analysis
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ Build_Slack_      │  Build Slack blocks + prefill text
│ Questionnaire     │
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ Send_Questionnaire│  POST → Slack chat.postMessage
│ _Card             │
└───────────────────┘
          │
          END Phase A (Slack waits for human)
```

---

## Data flow (Phase B — questionnaire)

```
POST wf-onboard-questionnaire-response  (Slack interactive payload)
        │
        ▼
┌──────────────────────────┐
│ Parse_Questionnaire_     │  Extract pillars, ICP, niches, competitors, review_tier
│ Response                 │
└─────────┬────────────────┘
          │  { pipeline_run_id, client_name, client_url, questionnaire: {...} }
          ▼
┌──────────────────────────┐
│ LLM_CrossValidate          │  OpenRouter → { has_flags, flags[], summary }
└─────────┬────────────────┘
          │
          ▼
┌──────────────────────────┐
│ Parse_CrossVal_Response    │  has_flags true/false
└─────────┬────────────────┘
          │
          ▼
┌──────────────────────────┐
│ IF_Has_Flags               │
├─ TRUE ─► Send_Flag_Review_Card → Wait_Flag_Ack → Parse_Flag_Ack ─┐
├─ FALSE ─────────────────────────────────────────────────────────┤
└─────────────────────────────────────────────────────────────────┤
                                                                  ▼
                                                    ┌──────────────────────────┐
                                                    │ Write_Client             │  POST → clients
                                                    └─────────┬────────────────┘
                                                              ▼
                                                    ┌──────────────────────────┐
                                                    │ Write_Niches             │  POST → niches
                                                    └─────────┬────────────────┘
                                                              ▼
                                                    ┌──────────────────────────┐
                                                    │ Complete_Pipeline_Run    │  PATCH status completed
                                                    └─────────┬────────────────┘
                                                              ▼
                                                    ┌──────────────────────────┐
                                                    │ Send_Completion_         │  Slack notification
                                                    │ Notification             │
                                                    └─────────┬────────────────┘
                                                              ▼
                                                    ┌──────────────────────────┐
                                                    │ Respond_OK               │  { "ok": true }
                                                    └──────────────────────────┘
```

---

## Node reference (every node)

| Node | Type | What it does |
|------|------|--------------|
| **Sticky Note** | Sticky | Canvas documentation (not executed). |
| **Webhook_Trigger** | Webhook | Starts Phase A on `wf-onboard-start`. |
| **Validate_Payload** | Code | Validates body; outputs normalized client fields. |
| **Create_Pipeline_Run** | HTTP Request | Inserts row in `pipeline_runs`. |
| **Merge_Run_ID** | Code | Merges `pipeline_run_id` into working context. |
| **Fetch_Sitemap** | HTTP Request | Downloads sitemap XML. |
| **Parse_Sitemap_XML** | Code | Parses `<loc>` URLs, scores paths, returns up to 20 page items. |
| **Batch_Pages** | Split in Batches | Processes 5 pages at a time. |
| **Crawl_Page** | HTTP Request | GET HTML for `page_url`. |
| **Extract_Page_Content** | Code | Extracts title + meta description from HTML. |
| **Aggregate_Pages** | Aggregate | Merges all crawled pages into `{ pages: [...] }`. |
| **LLM_Site_Analysis** | HTTP Request | OpenRouter chat completion (JSON mode). |
| **Build_Slack_Questionnaire** | Code | Parses LLM JSON; builds Slack prefill fields. |
| **Send_Questionnaire_Card** | HTTP Request | Posts interactive Slack message to channel `C0B43A7QG5P`. |
| **Wait_For_Questionnaire** | Webhook | Starts Phase B when Slack submits form. |
| **Parse_Questionnaire_Response** | Code | Parses Slack `payload` into `questionnaire` object. |
| **LLM_CrossValidate** | HTTP Request | OpenRouter cross-validation JSON. |
| **Parse_CrossVal_Response** | Code | Sets `has_flags` from LLM output. |
| **IF_Has_Flags** | If | Routes to flag path or straight to DB writes. |
| **Send_Flag_Review_Card** | HTTP Request | Slack message with acknowledge button. |
| **Wait_Flag_Ack** | Webhook | Waits for human to acknowledge flags. |
| **Parse_Flag_Ack** | Code | Passes through cross-val context after ack. |
| **Write_Client** | HTTP Request | POST `clients` with full `config` JSON. |
| **Write_Niches** | HTTP Request | POST one row per niche to `niches`. |
| **Complete_Pipeline_Run** | HTTP Request | PATCH `pipeline_runs` → completed. |
| **Send_Completion_Notification** | HTTP Request | Slack “Client onboarded” message. |
| **Respond_OK** | Respond to Webhook | Returns `{ ok: true }` to caller. |

---

## Supabase outputs

| Table | What gets written |
|-------|-------------------|
| `pipeline_runs` | `kind: onboard`, `status: running` → later `completed` |
| `clients` | Name, domain, `onboarding_status: active`, full `config` |
| `niches` | One row per niche from questionnaire |

---

## Credentials required

- `Supabase_SEOTools` — Create_Pipeline_Run, Write_Client, Write_Niches, Complete_Pipeline_Run
- `OpenRouter_SEOTools` — LLM_Site_Analysis, LLM_CrossValidate
- `Slack_SEOTools` — Send_Questionnaire_Card, Send_Flag_Review_Card, Send_Completion_Notification

---

## Testing tips

1. **Activate** the workflow (or use test webhook URLs).
2. Phase A — PowerShell example:

```powershell
$body = @{
  client_url = "https://example.com"
  client_name = "Test Client"
  competitors = @("rival.com")
  seed_keywords = @("seo agency")
} | ConvertTo-Json

Invoke-RestMethod -Method POST `
  -Uri "https://n8n-webley-u35816.vm.elestio.app/webhook-test/wf-onboard-start" `
  -Body $body -ContentType "application/json"
```

3. Check n8n **Executions** for Phase A — confirm Slack card was sent.
4. For Phase B without Slack UI, POST a minimal mock to `wf-onboard-questionnaire-response` with `pipeline_run_id` matching the button `value` from the Slack card.

---

## What runs next

- **WF-00** — Refresh page inventory daily.
- **WF-01** — Upload keyword CSV for this `client_id`.
