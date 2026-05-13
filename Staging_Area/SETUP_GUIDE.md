# Competitor Intelligence System - Setup Guide

## Overview
This system implements an **Asynchronous Scraping Pipeline** for competitor website analysis using Firecrawl and AI summarization.

### Architecture
```
┌─────────────────────────────────────────────────────────────────┐
│                    DISPATCHER WORKFLOW                          │
│  Manual Trigger → Create Job (PENDING) → Firecrawl API          │
│                                              │                  │
│                                              ▼                  │
│                                    Webhook callback URL ────────┼──┐
└─────────────────────────────────────────────────────────────────┘  │
                                                                      │
                                                                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                    RECEIVER WORKFLOW                            │
│  Webhook ← Firecrawl callback                                   │
│      │                                                          │
│      ▼                                                          │
│  Update Status (COMPLETED) → AI Summarizer → Save Summary       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Step 1: Create Supabase Table

1. Open your Supabase project dashboard
2. Go to **SQL Editor**
3. Paste the contents of `scrape_jobs_table.sql` and run it

---

## Step 2: Import Receiver Workflow

1. Open n8n
2. Go to **Workflows** → **Import from File**
3. Select `compy_datascrape_receiver.json`
4. **Configure Credentials:**
   - Click on `Update_Job_Status_Completed` node → Add Postgres credentials (your Supabase connection)
   - Click on `OpenAI_GPT4` node → Add your OpenAI API credentials
   - Click on `Save_Intelligence_Summary` node → Add same Postgres credentials
5. **Activate the workflow**
6. **Copy the Production Webhook URL:**
   - Click on `Firecrawl_Callback` node
   - Copy the **Production URL** (looks like: `https://your-n8n.com/webhook/compy-receiver`)

---

## Step 3: Import Dispatcher Workflow

1. Go to **Workflows** → **Import from File**
2. Select `compy_datascrape_dispatcher.json`
3. **Configure Credentials:**
   - Click on `Create_Job_Ticket_Pending` node → Add Postgres credentials
   - Click on `Dispatch_Firecrawl_Scrape` node → Add Firecrawl API credentials
   - Click on `Update_Job_Dispatched` node → Add same Postgres credentials
4. **Update the Webhook URL:**
   - Click on `Dispatch_Firecrawl_Scrape` node
   - In the JSON body, replace `YOUR_RECEIVER_WEBHOOK_URL_HERE` with the Production URL from Step 2

---

## Step 4: Test the System

1. In the Dispatcher workflow, update the `Set_Target_URL` node with a real competitor URL
2. Click **Execute Workflow**
3. Check Supabase → `scrape_jobs` table to see the job progress:
   - PENDING → DISPATCHED → COMPLETED → ANALYZED

---

## Credential Setup Reference

### Supabase/Postgres
- **Host**: `db.xxxxx.supabase.co`
- **Database**: `postgres`
- **User**: `postgres`
- **Password**: Your database password
- **Port**: `5432`
- **SSL**: Enable (required for Supabase)

### Firecrawl API
- **API Key**: Get from https://firecrawl.dev/dashboard

### OpenAI
- **API Key**: Get from https://platform.openai.com/api-keys

---

## Troubleshooting

### Job stuck at DISPATCHED
- Check Firecrawl dashboard for job status
- Verify the webhook URL is publicly accessible
- Check n8n error logs

### AI Summarizer failing
- Verify OpenAI API key is valid
- Check if raw_markdown column has data
- Review the markdown content for unusual characters

### Webhook not receiving callbacks
- Ensure Receiver workflow is **active**
- Use the **Production URL**, not Test URL
- Check if Firecrawl can reach your n8n instance (needs public URL or tunnel)

---

## Files Included

| File | Purpose |
|------|---------|
| `compy_datascrape_receiver.json` | Receiver workflow - handles Firecrawl callbacks |
| `compy_datascrape_dispatcher.json` | Dispatcher workflow - initiates scrape jobs |
| `scrape_jobs_table.sql` | Supabase table schema |
| `SETUP_GUIDE.md` | This guide |
