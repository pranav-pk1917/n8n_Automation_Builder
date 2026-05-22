# Wave 1 Manual Setup — Intern Runbook

**Purpose:** Finish the remaining Wave 1 steps for the SEO-Tools n8n stack after the automated build (database migration + `SYS-Error-Handler` workflow creation). This guide is written so someone new to n8n, Supabase, and Slack can complete every step without asking “where do I get this value?”

**Time estimate:** 30–45 minutes (first time).

**What Wave 1 adds:**

- Global error workflow `SYS-Error-Handler` (catches uncaught failures, marks `pipeline_runs` as failed, posts to Slack).
- Two new n8n environment variables for Slack channel IDs.
- Error-workflow binding on all seven Phase-1 workflows.

**Companion docs:**

- Phase 2 update spec (what we are fixing and why): [Manual-Review/prd/phase-2-update-spec.md](../Manual-Review/prd/phase-2-update-spec.md)
- Full credential matrix (all workflows, not just Wave 1): [credentials.example.md](../credentials.example.md)
- Greenfield setup (new client / full stack): [MANUAL-SETUP-GUIDE.md](../../docs/MANUAL-SETUP-GUIDE.md)

---

## Section 0 — What you need before you start

Complete this checklist **before** opening n8n. If anything is missing, request access from your **SEO-Tools tech lead** (or whoever manages Webley’s automation stack).

| Access | Why you need it | Where to get it | If you don’t have it |
|--------|-----------------|-----------------|----------------------|
| **n8n login** | Edit workflows, credentials, variables | Tech lead sends an invite to `https://n8n-webley-u35816.vm.elestio.app` | Ask lead: “Please invite `<your-email>` to the Webley n8n instance.” |
| **Slack workspace** | Ops alerts and HITL messages land in channels | Your Webley Slack account (same as company email) | Ask IT or lead for Slack workspace invite. |
| **Slack channel membership** | Bot must be in the channel to post | Join `#seo-tools-ops` / `#seo-tools-hitl` **or** the channel your lead designates | In Slack: open channel → if you see “Join channel”, join. If channel doesn’t exist, use default ID `C0B43A7QG5P` (Section 3). |
| **Supabase project (read)** | Smoke test verifies `pipeline_runs` updates | `https://supabase.com/dashboard` → Webley SEO-Tools project | Ask lead to add you as **Developer** on the Supabase org/project. |
| **Slack app admin (optional)** | Only if `Slack_SEOTools` credential is missing in n8n | `https://api.slack.com/apps` | Ask lead to add you as **Collaborator** on the Webley Slack app, or to paste the bot token for you. |

**Do not need for Wave 1:** OpenRouter, SerpAPI, Google Sheets, Python worker, or WPGraphQL — those are already configured for other workflows.

---

## Section 1 — Log in to n8n

1. Open **https://n8n-webley-u35816.vm.elestio.app** in Chrome or Edge.
2. Sign in with the email and password your lead provided.
3. If you forgot your password, use **Forgot password** on the login page (or ask the lead to reset your account).

**You should see:** The **Workflows** list (left sidebar: Workflows, Credentials, Executions, etc.). The top bar shows your instance URL.

**If you see a blank page or 502:** The Elestio host may be restarting. Wait 2 minutes and refresh. If it persists, tell the lead.

---

## Section 2 — Verify and create credentials (10 min)

Wave 1 only needs **two** credentials. Always **check if they already exist** before creating duplicates.

**Open credentials:** Left sidebar → **Credentials** → use the search box.

### 2.1 `Supabase_SEOTools`

**Important:** [credentials.example.md](../credentials.example.md) lists this as “Supabase API”. On the **live** instance, workflows use **HTTP Header Auth** with the name `Supabase_SEOTools`. Match the live shape below.

**Check:**

1. Search for `Supabase_SEOTools`.
2. If it exists and type is **Header Auth** (or “HTTP Header Auth”), you are done with 2.1 → go to 2.2.
3. If missing, create it (steps below).

**Create (if missing):**

1. **Credentials** → **Add credential** → search **Header Auth** → select **Header Auth** (sometimes labeled “HTTP Header Auth”).
2. Fill in:

   | Field | Value |
   |-------|--------|
   | **Credential name** | `Supabase_SEOTools` (exact spelling, case-sensitive) |
   | **Name** (header name) | `apikey` |
   | **Value** (header value) | Your Supabase **service_role** key (see 2.1.1) |

3. **Save**.

**Note:** Individual HTTP nodes in workflows also send `Authorization: Bearer <service_role_key>` via expressions (`$env.SUPABASE_SERVICE_ROLE_KEY`). The credential’s `apikey` header is still required for PostgREST. Both must use the **same** service_role key as in n8n Variables (Section 4).

#### 2.1.1 Where to get the Supabase service_role key and project URL

1. Go to **https://supabase.com/dashboard**.
2. Select the **Webley SEO-Tools** project (name may be `n8n_Automation_Builder` or similar — ask the lead if you see multiple projects).
3. Left sidebar → **Project Settings** (gear) → **API**.
4. On that page:
   - **Project URL** — copy the URL at the top (looks like `https://xxxxxxxx.supabase.co`). You will use this as `SUPABASE_URL` in Section 4.
   - **Project API keys** — find the row labeled **`service_role`**. Click **Reveal** → copy the key (long JWT string).
5. **Do not** use the **`anon`** / **`public`** key for n8n server workflows. It respects Row Level Security and will cause confusing 401/403 errors.

**If you cannot open Supabase:** Ask the lead: “Please add me to the SEO-Tools Supabase project as Developer, or send me `SUPABASE_URL` and the service_role key for n8n Variables only (do not paste keys in public Slack).”

---

### 2.2 `Slack_SEOTools`

**Important:** `credentials.example.md` describes **Slack OAuth2**. Live SEO-Tools workflows call `https://slack.com/api/chat.postMessage` via **HTTP Request** nodes with **Header Auth**. Use **HTTP Header Auth** named `Slack_SEOTools`.

**Check:**

1. Search for `Slack_SEOTools`.
2. If one exists and type is **Header Auth** → done, skip to Section 3.
3. If one exists as **Slack OAuth2 API** → **rename** it to `Slack_SEOTools_OAuth2_legacy` (open credential → rename), then create a **new** Header Auth credential named `Slack_SEOTools` (steps below).
4. If none exists → create below.

**Create (if missing):**

1. **Add credential** → **Header Auth**.
2. Fill in:

   | Field | Value |
   |-------|--------|
   | **Credential name** | `Slack_SEOTools` |
   | **Name** (header name) | `Authorization` |
   | **Value** (header value) | `Bearer xoxb-...` (see 2.2.1 — include the word `Bearer`, one space, then the token) |

3. **Save**.

#### 2.2.1 Where to get the Slack Bot User OAuth Token

1. Go to **https://api.slack.com/apps**.
2. Open the **Webley** Slack app (exact name varies — ask the lead: “Which app is SEO-Tools / n8n using?”).
3. Left nav → **OAuth & Permissions**.
4. Under **OAuth Tokens for Your Workspace**, copy **Bot User OAuth Token** (starts with `xoxb-`).
5. Paste into the credential as: `Bearer ` + token (example: `Bearer xoxb-1234567890-1234567890123-AbCdEfGhIjKlMnOpQrStUvWx`).

**Required bot scopes** (lead should verify under **Scopes → Bot Token Scopes**):

- `chat:write`
- `chat:write.public` (posts to public channels the bot isn’t in yet — still invite the bot for private channels)

If scopes were added recently, the app may need **Reinstall to Workspace** (button on the same OAuth page).

**If you cannot access api.slack.com/apps:** Ask the lead for the bot token securely (1Password, DM, not a public channel) or to create/update the `Slack_SEOTools` Header Auth credential for you.

---

## Section 3 — Find Slack channel IDs (5 min)

n8n reads channel IDs from **Variables** (Section 4), not channel names like `#seo-tools-ops`.

**For each channel you will use:**

1. Open Slack (desktop or web).
2. Open the channel.
3. Click the **channel name** at the top of the message list.
4. Open the **About** tab.
5. Scroll to the bottom → copy **Channel ID** (starts with `C`, e.g. `C0B43A7QG5P`).

**Wave 1 defaults (if you don’t have separate ops/HITL channels yet):**

| Variable | Recommended channel | Default ID (legacy single channel) |
|----------|---------------------|-------------------------------------|
| `SLACK_OPS_CHANNEL` | Where `SYS-Error-Handler` posts failure alerts | `C0B43A7QG5P` |
| `SLACK_HITL_CHANNEL` | Where WF-02 / WF-03 / WF-05 post review cards | `C0B43A7QG5P` |

Using the same ID for both is **OK for Wave 1**. Splitting ops vs HITL into two channels is recommended later.

**Invite the bot to the channel:**

In the Slack channel, run: `/invite @<your-bot-display-name>`

Without this, `chat.postMessage` fails with `not_in_channel` even if the token and channel ID are correct.

---

## Section 4 — Set environment variables (3 min)

n8n **Variables** are instance-wide key/value pairs workflows read as `$env.VARIABLE_NAME`.

**Open:** Top-right **Settings** (gear) → **Variables** (or **Environments → Variables**, depending on n8n version).

### 4.1 Add these two variables (Wave 1)

Click **Add variable** for each:

| Key | Value | Where the value comes from |
|-----|--------|---------------------------|
| `SLACK_OPS_CHANNEL` | Channel ID from Section 3 | e.g. `C0B43A7QG5P` |
| `SLACK_HITL_CHANNEL` | Channel ID from Section 3 | e.g. `C0B43A7QG5P` |

No quotes around the value — paste the raw ID.

### 4.2 Confirm these already exist (do not change if present)

| Key | Typical source |
|-----|----------------|
| `SUPABASE_URL` | Supabase → Settings → API → Project URL (Section 2.1.1) |
| `SUPABASE_SERVICE_ROLE_KEY` | Same page → **service_role** key (must match credential value) |
| `PYTHON_WORKER_URL` | Railway deployment URL (no trailing slash) — ask lead |
| `GOOGLE_SHEETS_ID` | Google Sheet ID for WF-05 — ask lead |

If `SUPABASE_URL` or `SUPABASE_SERVICE_ROLE_KEY` is missing, add them using Section 2.1.1.

**Save** after any changes.

---

## Section 5 — Assign credentials inside SYS-Error-Handler (5 min)

The error handler workflow was created by automation but **did not** auto-bind credentials. Three nodes need you to pick credentials manually.

**Open workflow:**

https://n8n-webley-u35816.vm.elestio.app/workflow/a1pfnQHRkmPBWJDv

You should see **8 nodes** on the canvas (including a sticky note).

**For each HTTP Request node below:**

1. **Double-click** the node.
2. Confirm **Authentication** = **Generic Credential Type** → **Header Auth** (or “HTTP Header Auth”).
3. **Credential to connect with** → select from dropdown.
4. Close the node panel.
5. After all three: **Save** the workflow (**Ctrl+S** / **Cmd+S**, top right).

| Node name on canvas | Select this credential |
|---------------------|-------------------------|
| **Patch Pipeline Run** | `Supabase_SEOTools` |
| **Patch Onboarding Session** | `Supabase_SEOTools` |
| **Post Ops Alert** | `Slack_SEOTools` |

**Success:** Red warning borders on those nodes disappear. If a dropdown is empty, go back to Section 2 and create the missing credential, then refresh the page.

---

## Section 6 — Activate SYS-Error-Handler (1 min)

1. Stay on the `SYS-Error-Handler` workflow.
2. Top-right toggle: **Inactive** → **Active** (should turn green / “Active”).

**Why:** n8n only runs a designated error workflow when that error workflow is **active**.

**Do not** set an Error Workflow on `SYS-Error-Handler` itself (it would create a loop). Its own Settings → Error Workflow should stay empty.

---

## Section 7 — Bind error workflow on all 7 Phase-1 workflows (10 min)

When any of these workflows fail with an uncaught error, n8n will start `SYS-Error-Handler`.

**Repeat for each workflow in the table:**

1. Open the workflow URL (new tab is fine).
2. Open **Workflow settings**:
   - Click the **gear icon** top-right, **or**
   - Keyboard: **Ctrl+,** (Windows) / **Cmd+,** (Mac).
3. Find **Error Workflow** (sometimes under “Settings” or “Execution”).
4. Dropdown → select **`SYS-Error-Handler`**.
5. **Save** the workflow (**Ctrl+S** / **Cmd+S**).
6. Check off the row in your list and continue.

| # | Workflow | Direct link |
|---|----------|-------------|
| 1 | WF-ONBOARD | https://n8n-webley-u35816.vm.elestio.app/workflow/yMld4MwSr3ZHoxti |
| 2 | WF-00 Page Inventory | https://n8n-webley-u35816.vm.elestio.app/workflow/JM5HNsg6ADp0GW7Q |
| 3 | WF-01 CSV Ingest | https://n8n-webley-u35816.vm.elestio.app/workflow/3POshJ2qtKokamIZ |
| 4 | WF-02 Tiered Filter | https://n8n-webley-u35816.vm.elestio.app/workflow/WqeKRWzw5NrzzOt0 |
| 5 | WF-03 Cluster | https://n8n-webley-u35816.vm.elestio.app/workflow/4H0BClIdgm2LZgjr |
| 6 | WF-04 ICP Score | https://n8n-webley-u35816.vm.elestio.app/workflow/WVVmNKuwlcf5WcKz |
| 7 | WF-05 Sheet Sync | https://n8n-webley-u35816.vm.elestio.app/workflow/PRmymr61yi4Bsqed |

**Verify one workflow:** Re-open Settings → Error Workflow should still show `SYS-Error-Handler`.

**If the dropdown is empty:** `SYS-Error-Handler` is not Active — return to Section 6.

---

## Section 8 — Smoke test (5 min)

Prove the chain works: **workflow fails → error handler runs → Slack alert** (and optionally Supabase update).

### Option A — Synthetic failure in WF-01 (recommended)

Smallest blast radius; easy to revert.

1. Open **WF-01**: https://n8n-webley-u35816.vm.elestio.app/workflow/3POshJ2qtKokamIZ
2. Open the **Validate_Ingest_Payload** (or first **Code** node after the webhook).
3. At the **very first line** of the JavaScript, add temporarily:

   ```javascript
   throw new Error('SYS-Error-Handler smoke test');
   ```

4. **Save** the workflow.
5. **Test workflow** (or trigger the ingest webhook with any test payload).
6. **Expected:**
   - Execution list shows **failed** on that Code node.
   - Within ~30 seconds, Slack channel (`SLACK_OPS_CHANNEL`) gets a message like **“Workflow failed: WF-01 …”** with failing node name and error text.
7. **Revert:** Delete the `throw new Error(...)` line → **Save**.

**Optional Supabase check** (if the failed run had a `pipeline_run_id` in context):

1. Supabase dashboard → **SQL Editor** → New query.
2. Run:

   ```sql
   select id, status, finished_at, output_summary
   from pipeline_runs
   where output_summary->>'failed_workflow' is not null
   order by finished_at desc nulls last
   limit 5;
   ```

3. A recent row may show `status = 'failed'` and `output_summary` containing `failed_workflow`, `failing_node`, `error_class`, `error_message`, `execution_url`.

If the smoke test used a throw **before** any `pipeline_run_id` was created, Supabase may not update any row — Slack alert alone is enough to pass Wave 1.

### Option B — Manual step through SYS-Error-Handler

1. Open **SYS-Error-Handler**.
2. Use **Execute workflow** / test execution on the **Error Trigger** node (if your n8n version allows manual test on error workflows).
3. Confirm downstream nodes execute; Slack may post using mock data.

Supabase PATCH may update **zero rows** if the mock `pipeline_run_id` does not exist — that is expected for Option B.

---

## Section 9 — Troubleshooting / FAQ

| Problem | Likely cause | Fix |
|---------|--------------|-----|
| Red border on HTTP nodes after Section 5 | Credential not selected or workflow not saved | Select credential → **Save** workflow |
| Two `Slack_SEOTools` in dropdown | Old OAuth2 credential not renamed | Rename OAuth2 to `Slack_SEOTools_OAuth2_legacy`; use Header Auth one |
| Slack message never arrives | Wrong channel ID, or bot not in channel | Check `SLACK_OPS_CHANNEL` variable; `/invite @bot` in channel |
| Slack API error `not_in_channel` | Bot not invited | Invite bot to that channel |
| Slack API error `invalid_auth` | Wrong token or missing `Bearer ` prefix | Credential value must be `Bearer xoxb-...` |
| Supabase **401 Invalid API key** | Used `anon` key instead of `service_role` | Re-copy **service_role** from Supabase API settings |
| Supabase **404** on `onboarding_sessions` | Wave 1 migration not applied | SQL: `select * from onboarding_sessions limit 0;` — if error, contact dev who runs migrations |
| **Error Workflow** dropdown empty | SYS-Error-Handler inactive | Section 6 — activate it |
| Error handler never runs | Parent workflow not bound or not saved | Redo Section 7 for that workflow |
| `$env.SLACK_OPS_CHANNEL` is undefined in execution | Variable not set or typo | Section 4 — exact key name, no spaces |

**Still stuck?** Collect: workflow name, execution ID (from n8n Executions tab), screenshot of the failed node, and send to your tech lead.

---

## Section 10 — Handoff checklist (paste to your lead)

When everything passes, post this in Slack (add screenshots from Section 8):

```
Wave 1 manual setup — complete

[ ] Section 2: Supabase_SEOTools + Slack_SEOTools exist (HTTP Header Auth)
[ ] Section 4: SLACK_OPS_CHANNEL + SLACK_HITL_CHANNEL set in n8n Variables
[ ] Section 5: All 3 HTTP nodes in SYS-Error-Handler have credentials
[ ] Section 6: SYS-Error-Handler is Active
[ ] Section 7: All 7 workflows → Settings → Error Workflow = SYS-Error-Handler
[ ] Section 8: Smoke test — Slack alert received (screenshot attached)
[ ] Optional: Supabase pipeline_runs failed row (screenshot attached)

Completed by: <your name>
Date: <date>
```

---

## What’s next (Wave 2 — not part of this runbook)

After Wave 1 is signed off, development continues on **critical correctness** fixes documented in [phase-2-update-spec.md](../Manual-Review/prd/phase-2-update-spec.md):

- WF-02: persist Tier 1 classification rows (today most pass/reject decisions are dropped).
- WF-03: write `keyword_cluster_map` rows.
- WF-00 / WF-ONBOARD: fix `SplitInBatches` loop wiring.

You do **not** need to do those steps as an intern unless your lead assigns them.

---

## Quick reference — URLs and IDs

| Item | Value |
|------|--------|
| n8n instance | https://n8n-webley-u35816.vm.elestio.app |
| SYS-Error-Handler workflow ID | `a1pfnQHRkmPBWJDv` |
| SYS-Error-Handler URL | https://n8n-webley-u35816.vm.elestio.app/workflow/a1pfnQHRkmPBWJDv |
| Default Slack channel ID (legacy) | `C0B43A7QG5P` |
| Supabase dashboard | https://supabase.com/dashboard |
| Slack app config | https://api.slack.com/apps |
