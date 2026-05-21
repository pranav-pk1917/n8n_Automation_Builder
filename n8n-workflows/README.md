# SEO-Tools — n8n Workflows (Phase 1)

This folder documents the **seven workflows** that power the SEO-Tools keyword pipeline. Each workflow has its own README with features, data flow, and a node-by-node guide.

**n8n instance:** https://n8n-webley-u35816.vm.elestio.app

---

## How the pipeline fits together

Think of the system as an assembly line. Data moves left to right; each step adds structure.

```
NEW CLIENT
    │
    ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ WF-ONBOARD  │────▶│   WF-00     │     │   WF-01     │
│ Set up      │     │ Page list   │     │ CSV keywords│
│ client in   │     │ (daily)     │     │ (on demand) │
│ Supabase    │     └─────────────┘     └──────┬──────┘
└─────────────┘                                │
                                               ▼
                                        ┌─────────────┐
                                        │   WF-02     │
                                        │ Filter bad  │
                                        │ keywords    │
                                        └──────┬──────┘
                                               │
                                               ▼
                                        ┌─────────────┐
                                        │   WF-03     │
                                        │ Group into  │
                                        │ clusters    │
                                        └──────┬──────┘
                                               │
                                               ▼
                                        ┌─────────────┐
                                        │   WF-04     │
                                        │ Score ICP + │
                                        │ priority    │
                                        └──────┬──────┘
                                               │
                                               ▼
                                        ┌─────────────┐
                                        │   WF-05     │
                                        │ Export to   │
                                        │ Google      │
                                        │ Sheets      │
                                        │ (nightly)   │
                                        └─────────────┘
```

**Typical order for a new client:**

1. Run **WF-ONBOARD** once (creates the client record and config).
2. Upload keywords with **WF-01** (CSV from Ahrefs/Semrush/etc.).
3. Run **WF-02** → **WF-03** → **WF-04** in sequence (filter → cluster → score).
4. **WF-00** and **WF-05** run on a schedule once the client is active.

---

## Workflow index

| Workflow | n8n name | Trigger | README |
|----------|----------|---------|--------|
| Onboarding | WF-ONBOARD | Webhook | [WF-ONBOARD.md](./docs/WF-ONBOARD.md) |
| Page inventory | WF-00 Page Inventory Sync | Daily 02:00 UTC | [WF-00.md](./docs/WF-00.md) |
| CSV ingest | WF-01 CSV Keyword Ingest | Webhook | [WF-01.md](./docs/WF-01.md) |
| Tiered filter | WF-02 Tiered Keyword Filter | Webhook | [WF-02.md](./docs/WF-02.md) |
| Clustering | WF-03 Clustering + 3-Axis Labeling | Webhook | [WF-03.md](./docs/WF-03.md) |
| ICP scoring | WF-04 ICP Scoring + Priority Score | Webhook | [WF-04.md](./docs/WF-04.md) |
| Sheets sync | WF-05 Nightly Google Sheets Sync | Daily 03:00 UTC | [WF-05.md](./docs/WF-05.md) |

**Direct links in n8n:**

| Workflow | Open in n8n |
|----------|-------------|
| WF-ONBOARD | https://n8n-webley-u35816.vm.elestio.app/workflow/yMld4MwSr3ZHoxti |
| WF-00 | https://n8n-webley-u35816.vm.elestio.app/workflow/JM5HNsg6ADp0GW7Q |
| WF-01 | https://n8n-webley-u35816.vm.elestio.app/workflow/3POshJ2qtKokamIZ |
| WF-02 | https://n8n-webley-u35816.vm.elestio.app/workflow/WqeKRWzw5NrzzOt0 |
| WF-03 | https://n8n-webley-u35816.vm.elestio.app/workflow/4H0BClIdgm2LZgjr |
| WF-04 | https://n8n-webley-u35816.vm.elestio.app/workflow/WVVmNKuwlcf5WcKz |
| WF-05 | https://n8n-webley-u35816.vm.elestio.app/workflow/PRmymr61yi4Bsqed |

---

## Credentials (bind before testing)

Every HTTP node needs the right credential. In n8n: open the workflow → click each red HTTP Request / Google Sheets node → assign the credential from the list below.

| Credential name in n8n | Type | Used by |
|------------------------|------|---------|
| `Supabase_SEOTools` | HTTP Header Auth | All workflows (Supabase REST) |
| `OpenRouter_SEOTools` | HTTP Header Auth | WF-ONBOARD, WF-00, WF-02, WF-03, WF-04 |
| `Slack_SEOTools` | HTTP Header Auth | WF-ONBOARD, WF-02, WF-03, WF-05 |
| `PythonWorker_SEOTools` | HTTP Header Auth | WF-03 (`/cluster` on Railway) |
| `SerpAPI_SEOTools` | HTTP Query Auth | WF-04 |
| `GoogleSheets_SEOTools` | Google Sheets OAuth2 | WF-05 |

**n8n environment variables** (Settings → Variables):

| Variable | Purpose |
|----------|---------|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role key for REST API |
| `PYTHON_WORKER_URL` | Railway worker base URL (no trailing slash) |
| `GOOGLE_SHEETS_ID` | Spreadsheet ID for WF-05 |

---

## Webhook URL pattern

For webhook workflows, n8n gives you two URLs:

- **Test:** `https://n8n-webley-u35816.vm.elestio.app/webhook-test/<path>`
- **Production (workflow must be Active):** `https://n8n-webley-u35816.vm.elestio.app/webhook/<path>`

Use **test** while building; switch to **production** when the workflow is activated.

---

## Repo files vs live n8n

| Location | What it is |
|----------|------------|
| `exports/*.json` | Full workflow JSON (may include extra nodes vs current n8n deploy) |
| `sdk/wf-onboard.ts` | Source used to deploy via n8n MCP SDK |
| `docs/WF-*.md` | Human-readable guides (this documentation) |

If something in n8n does not match an export file, **trust what you see in the n8n editor** — that is what runs.

---

## Supabase tables touched

| Table | Written by |
|-------|------------|
| `clients` | WF-ONBOARD |
| `niches` | WF-ONBOARD |
| `pipeline_runs` | WF-ONBOARD |
| `pages` | WF-00 |
| `raw_keywords` | WF-01 |
| `keyword_graveyard` | Read by WF-01 (dedupe) |
| `keyword_classifications` | WF-02 |
| `keyword_clusters` | WF-03, WF-04 |
| `api_cost_log` | WF-04 |

---

## Need help?

- Setup checklist: [MANUAL-SETUP-GUIDE.md](../docs/MANUAL-SETUP-GUIDE.md)
- Handoff after setup: [HANDOFF-TEMPLATE.md](../docs/HANDOFF-TEMPLATE.md)
