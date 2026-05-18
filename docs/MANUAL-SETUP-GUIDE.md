# Manual setup guide — SEO-Tools Phase 1

**Audience:** an intern at Webley Media who has never set up these tools before. Follow this guide top-to-bottom. Do not skip ahead. Each section ends with a **Verify** step — if verify fails, do not move on, fix it first.

**Total time:** 3-4 hours, doable in one session or split across two.

**When you finish:** fill in [HANDOFF-TEMPLATE.md](./HANDOFF-TEMPLATE.md) and notify the build agent in chat.

---

## Verification run log

This section is a living record of every verification script run against real credentials. Updated by the build agent each time a test is re-run. If a service shows PENDING, complete the prerequisite steps first.

| Service | Script | Last run | Result | Key / credential used |
|---|---|---|---|---|
| OpenRouter — Primary LLM (`google/gemini-2.0-flash-001`) | `verify_openrouter.ps1` | 2026-05-15 | PASS | `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` |
| OpenRouter — Embeddings (`openai/text-embedding-3-small` @ 768 dim) | `verify_openrouter.ps1` | 2026-05-15 | PASS | same key above |
| OpenRouter — Cross-validation LLM (`openai/gpt-4o-mini`) | `verify_openrouter.ps1` | 2026-05-15 | PASS | same key above |
| Slack — post to `#seo-tools-hitl` | `verify_services.ps1` | 2026-05-15 | PASS | token `xoxb-11122421376323-11134110887429-nhwtxduxAESuSwFCFzhC9m6e`, channel `C0B43A7QG5P` |
| SerpAPI — search query | `verify_services.ps1` | 2026-05-15 | PASS | `c68aa5b90d549f985c2f394a14628116f5465202fe13b1dbc34ea76de5564c2c` |
| Telegram — bot health (`getMe`) | `_tg_debug.ps1` | 2026-05-15 | **PASS** — bot alive, token valid | token `8616386423:AAHhENvweAI4Qc88vg92Dp09i0kauKopbac`, `@webley_seotools_hitl_bot`, `can_join_groups=True` |
| Telegram — send to group | `verify_services.ps1` | 2026-05-15 | **PASS** | token `8616386423:AAHhENvweAI4Qc88vg92Dp09i0kauKopbac`, chat ID `-4993060055` (`SEO-Tools HITL` group) |

### Full output — Telegram (2026-05-15, PASS)

**Step 1 — `_tg_debug.ps1` (chat ID discovery):**
```powershell
powershell -ExecutionPolicy Bypass -File "SEO-Tools/scripts/_tg_debug.ps1"
```
```
=== Step 1: getMe (bot health check) ===
PASS  Bot is alive and token is valid
  id               : 8616386423
  username         : @webley_seotools_hitl_bot
  name             : Webley SEO-Tools HITL
  can_join_groups  : True

=== Step 2: getUpdates (find group chat ID) ===
Found 3 update(s):
  chat_id=801056857    type=private  title=  from=@  text=/start
  chat_id=-4993060055  type=group    title=SEO-Tools HITL  from=@  text=

ACTION: Copy the chat_id above, paste it into step 8.10 of the setup guide,
then run verify_services.ps1 with that chat ID to complete the Telegram verify.
```

**Step 2 — `verify_services.ps1` (send message):**
```powershell
powershell -ExecutionPolicy Bypass -File "SEO-Tools/scripts/verify_services.ps1" `
  -TelegramBotToken "8616386423:AAHhENvweAI4Qc88vg92Dp09i0kauKopbac" `
  -TelegramChatId   "-4993060055" `
  -SlackBotToken    "skip" `
  -SerpApiKey       "skip"
```
```
=== Slack: SKIPPED ===

=== SerpAPI: SKIPPED ===

=== Telegram: send message to group ===
PASS  message sent, message_id=3

==============================
Results: 1 PASS / 0 FAIL
==============================
```

---

### Full output — OpenRouter (2026-05-15, 3/3 PASS)

Command run:
```powershell
powershell -ExecutionPolicy Bypass -File "SEO-Tools/scripts/verify_openrouter.ps1" -ApiKey "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"
```

Output:
```
=== Chat test: Primary LLM (google/gemini-2.0-flash-001) ===
PASS  response: Ok

=== Embedding test: openai/text-embedding-3-small (expecting 768 dims) ===
PASS  embedding length: 768

=== Chat test: Cross-validation LLM (openai/gpt-4o-mini) ===
PASS  response: Ok.

==============================
Results: 3 PASS / 0 FAIL
==============================
```

### Full output — Slack + SerpAPI (2026-05-15, 2/2 PASS)

Command run:
```powershell
powershell -ExecutionPolicy Bypass -File "SEO-Tools/scripts/verify_services.ps1" `
  -SlackBotToken  "xoxb-11122421376323-11134110887429-nhwtxduxAESuSwFCFzhC9m6e" `
  -SlackChannelId "C0B43A7QG5P" `
  -SerpApiKey     "c68aa5b90d549f985c2f394a14628116f5465202fe13b1dbc34ea76de5564c2c" `
  -TelegramBotToken "skip"
```

Output:
```
=== Slack: post message to channel ===
PASS  message posted to channel C0B43A7QG5P

=== SerpAPI: test search ===
PASS  search_metadata.status = Success

=== Telegram: SKIPPED ===

==============================
Results: 2 PASS / 0 FAIL
==============================
```

---

## Table of contents

1. [Prerequisites](#1-prerequisites)
2. [Create the Supabase project](#2-create-the-supabase-project) — 30 min
3. [Apply Supabase migrations](#3-apply-supabase-migrations) — 20 min
4. [Load Webley seed data](#4-load-webley-seed-data) — 5 min
5. [Get an OpenRouter API key](#5-get-an-openrouter-api-key) — 15 min
6. [Get a SerpAPI key (optional for Phase 1)](#6-get-a-serpapi-key-optional-for-phase-1) — 10 min
7. [Create the Slack bot](#7-create-the-slack-bot) — 25 min
8. [Create the Telegram bot (optional)](#8-create-the-telegram-bot-optional) — 15 min
9. [Deploy the Python worker on Railway](#9-deploy-the-python-worker-on-railway) — 25 min
10. [Run n8n locally in Docker](#10-run-n8n-locally-in-docker) — 25 min
11. [Expose n8n via a Cloudflare tunnel](#11-expose-n8n-via-a-cloudflare-tunnel) — 30 min
12. [Google Cloud OAuth + Sheets API (optional for Phase 1)](#12-google-cloud-oauth--sheets-api-optional-for-phase-1) — 30 min
13. [Verify WPGraphQL endpoint](#13-verify-wpgraphql-endpoint) — 10 min
14. [Final cross-service verification checklist](#14-final-cross-service-verification-checklist) — 15 min
15. [Hand off back to the agent](#15-hand-off-back-to-the-agent) — 5 min

Sections marked **optional for Phase 1** can be deferred. The first n8n workflow we build (WF-ONBOARD) does not need them. You can come back to them before WF-04 (SerpAPI / ICP scoring) and WF-05 (Sheet sync).

---

## 1. Prerequisites

### 1.1 Accounts you will need

Sign up for each one and confirm your email before continuing.

- [done] **GitHub** — https://github.com/signup. Free.
- [done- using:pranav.pk1917@gmail.com ] **Google account** — only needed for Google Cloud + Google Sheets in Section 12 (optional for Phase 1). Use a Webley Media account if available, otherwise your personal Google works.
- [ ] **OpenRouter** — https://openrouter.ai. Sign in with GitHub (uses the same GitHub account from the line above). OpenRouter is our unified LLM gateway for both chat models and text-embedding models. See Section 5.
- [done, github-pranav.pk1917@mail.com] **Supabase** — https://supabase.com. Sign in with GitHub (recommended).
- [done, github-pranav.pk1917@mail.com] **Railway** — https://railway.app. Sign in with GitHub. You will get $5 free credit; this is enough for several months at our usage.
- [done, Google-Pranav.pk1917@gmail.com] **Cloudflare** — https://dash.cloudflare.com/sign-up. Free.
- [done, Google-Pranav.pk1917@gmail.com] **SerpAPI** — https://serpapi.com/users/sign_up. Free 100 searches/month plan is enough for Phase 1 testing. *Optional now.*
- [done, Google-pranav.pk1917@gmail.com] **Slack workspace** — either use Webley Media's existing workspace, or create a new one at https://slack.com/get-started. You need admin or "Manage apps" permissions.
- [done] **Telegram** — install the Telegram app on your phone if you do not already use it. *Optional.*

### 1.2 Software to install on Windows

- [done] **Docker Desktop for Windows** — https://www.docker.com/products/docker-desktop. Run the installer, allow it to enable WSL 2 if prompted, restart your PC, then open Docker Desktop once and accept the terms. You will see a whale icon in your system tray when it is running.
- [done] **Git for Windows** — https://git-scm.com/download/win. Accept all default options.
- [done] **Cursor or VS Code** — you are likely already using one of these.
- [ ] **`cloudflared`** — Cloudflare Tunnel daemon. Install instructions are in [Section 11](#11-expose-n8n-via-a-cloudflare-tunnel). Do not install yet.

### 1.3 Confirm admin rights - done

You will need to:
- Install Docker Desktop (requires admin).
- Open ports on Windows Firewall (Docker handles this automatically but the prompt needs admin).
- Run PowerShell commands in elevated mode at least once.

If you do not have admin rights on this machine, stop and ask Pranav before continuing.

### 1.4 Open a fresh PowerShell terminal - done

Open **Windows Terminal** (or plain PowerShell). Run these to confirm everything is in place:

```powershell
docker --version
git --version
```

You should see version strings for both. If either errors out, install is incomplete.

### Verify section 1

- [done] All accounts created and email-confirmed.
- [done] Docker Desktop is running (whale icon in tray, no red error indicator).
- [done] `docker --version` and `git --version` print version strings.

---

## 2. Create the Supabase project

**What you're doing:** spinning up a new Postgres database (with the pgvector extension) dedicated to SEO-Tools. This must be a **separate project** from any other Supabase or Postgres database Webley uses (see [ADR 0004](./adr/0004-supabase-separate-from-prisma.md) for the reason).

### Steps

- [ ] 2.1 Go to https://supabase.com/dashboard. Sign in.
- [ ] 2.2 Click the green **"New project"** button (top-right of the Organization page).
- [ ] 2.3 If asked, pick or create an organization. For Webley use the organization named "Webley Media" (create it if it does not exist).
- [ ] 2.4 Fill in the form:
  - **Name:** `seo-tools-prod` (or `seo-tools-dev` if you want a dev project first — recommended for an intern's first run).
  - **Database Password:** click **Generate a password** and **save it immediately** into a password manager (Bitwarden, 1Password, etc.). You will not see this again.
  - **Region:** pick the one closest to your team. For India, choose **South Asia (Mumbai)**. For most of the world, **US East (North Virginia)** is the default.
  - **Pricing Plan:** Free is fine for Phase 1.
- [ ] 2.5 Click **Create new project**. Wait 2-3 minutes while it provisions. You will see a green checkmark when it is ready.
- [ ] 2.6 Once ready, you will be on the project's home page. Click **Project Settings** (gear icon in left sidebar) → **API**.
- [ ] 2.7 Copy these four values and paste them somewhere safe (you will put them in `SEO-Tools/.env` later):
  - **Project URL** (looks like `https://abcdefghij.supabase.co`)
  - **Project Reference ID** (the `abcdefghij` part)
  - **Project API keys** → **`anon` `public`** key
  - **Project API keys** → **`service_role` `secret`** key — **THIS IS A POWERFUL KEY. Never put it in client-side code or paste it into chat.**
  project name: seo-tools-prod
  database password: Ji,T&GvLW9rUH%-
  region: South Asia (Mumbai)

### Verify section 2

- [yes, https://supabase.com/dashboard/project/qpfjpjshpnndimoayiwb] You can access the project dashboard.
- [ ] You have copied the URL, project ref, anon key, and service_role key into a secure note.
these are the values for seo-tools-prod(project name)>CONFIGURATION>Roles (Showing all the values that are available for each option, along with its ID and what options have been selected )
```
 anon (ID: 16484)
- [ ] User can login
- [ ] User can create roles
- [ ] User can create databases
- [ ] User bypasses every row level security policy
- [ ] User is a Superuser
- [ ] User can initiate streaming replication and put the system in and out of backup mode

 authenticated (ID: 16485)
- [ ] User can login
- [ ] User can create roles
- [ ] User can create databases
- [ ] User bypasses every row level security policy
- [ ] User is a Superuser
- [ ] User can initiate streaming replication and put the system in and out of backup mode

 authenticator (ID: 16487)
- [x] User can login
- [ ] User can create roles
- [ ] User can create databases
- [ ] User bypasses every row level security policy
- [ ] User is a Superuser
- [ ] User can initiate streaming replication and put the system in and out of backup mode

 dashboard_user (ID: 16555)
- [ ] User can login
- [x] User can create roles
- [x] User can create databases
- [ ] User bypasses every row level security policy
- [ ] User is a Superuser
- [x] User can initiate streaming replication and put the system in and out of backup mode

 pgbouncer (ID: 16389)
- [x] User can login
- [ ] User can create roles
- [ ] User can create databases
- [ ] User bypasses every row level security policy
- [ ] User is a Superuser
- [ ] User can initiate streaming replication and put the system in and out of backup mode

 service_role (ID: 16486)
- [ ] User can login
- [ ] User can create roles
- [ ] User can create databases
- [x] User bypasses every row level security policy
- [ ] User is a Superuser
- [ ] User can initiate streaming replication and put the system in and out of backup mode

 supabase_admin (ID: 10)
- [x] User can login
- [x] User can create roles
- [x] User can create databases
- [x] User bypasses every row level security policy
- [x] User is a Superuser
- [x] User can initiate streaming replication and put the system in and out of backup mode

 supabase_auth_admin (ID: 16545)
- [x] User can login
- [x] User can create roles
- [ ] User can create databases
- [ ] User bypasses every row level security policy
- [ ] User is a Superuser
- [ ] User can initiate streaming replication and put the system in and out of backup mode

 supabase_etl_admin (ID: 16432)
- [x] User can login
- [ ] User can create roles
- [ ] User can create databases
- [x] User bypasses every row level security policy
- [ ] User is a Superuser
- [x] User can initiate streaming replication and put the system in and out of backup mode

 supabase_read_only_user (ID: 16434)
- [x] User can login
- [ ] User can create roles
- [ ] User can create databases
- [x] User bypasses every row level security policy
- [ ] User is a Superuser
- [ ] User can initiate streaming replication and put the system in and out of backup mode

 supabase_realtime_admin (ID: 17502)
- [ ] User can login
- [ ] User can create roles
- [ ] User can create databases
- [ ] User bypasses every row level security policy
- [ ] User is a Superuser
- [ ] User can initiate streaming replication and put the system in and out of backup mode

 supabase_replication_admin (ID: 16431)
- [x] User can login
- [ ] User can create roles
- [ ] User can create databases
- [ ] User bypasses every row level security policy
- [ ] User is a Superuser
- [x] User can initiate streaming replication and put the system in and out of backup mode

 supabase_storage_admin (ID: 16547)
- [x] User can login
- [x] User can create roles
- [ ] User can create databases
- [ ] User bypasses every row level security policy
- [ ] User is a Superuser
- [ ] User can initiate streaming replication and put the system in and out of backup mode

---

 Other Database Roles

 postgres (ID: 16388)
- [x] User can login
- [x] User can create roles
- [x] User can create databases
- [x] User bypasses every row level security policy
- [ ] User is a Superuser
- [x] User can initiate streaming replication and put the system in and out of backup mode

 supabase_privileged_role (ID: 16662)
- [ ] User can login
- [ ] User can create roles
- [ ] User can create databases
- [ ] User bypasses every row level security policy
- [ ] User is a Superuser
- [ ] User can initiate streaming replication and put the system in and out of backup mode
```

- [ yes] You saved the database password.

```
## API Keys

### Publishable Key
*This key is safe to use in a browser if you have enabled Row Level Security (RLS) for your tables and configured policies. Publishable keys can be safely shared publicly.*

* **Name:** default
* **Description:** No description
* **API Key:** `sb_publishable_zPcyQBITsdAvsr-fxJ9VCg_zq8Ap3BK`

---

### Secret Keys
*These API keys allow privileged access to your project's APIs. Use them in servers, functions, workers, or other backend components of your application.*

* **Name:** default
* **Description:** No description
* **API Key:** `sb_secret_7lBHxn7kptl3eNQ99_2wtg_wOWNvBXF` *(Note: This key is partially hidden for security)*
```

```
## JWT Keys
Control the keys used to sign JSON Web Tokens for your project.

### Current Key
* **Status:** CURRENT KEY
* **Key ID:** `A60D5F91-4332-44D8-AE9F-F145AB168FDA`
* **Type:** ECC (P-256)

---

### Previously Used Keys
*These JWT signing keys are still used to verify tokens that are yet to expire. Revoke once all tokens have expired.*

* **Status:** PREVIOUS KEY
* **Key ID:** `6F0AD46E-E425-4247-9A30-5CC3032406B0`
* **Type:** Legacy HS256 (Shared Secret)
```
### Common errors

- **"Project is paused"** — Supabase free-tier projects pause after 7 days of inactivity. Click **Restore project** at the top of the dashboard.
- **Can't find API keys** — make sure you clicked **Project Settings** (gear icon) and then **API** in the second-level sidebar, not the top nav.

---

## 3. Apply Supabase migrations

**What you're doing:** running the SQL files in `SEO-Tools/supabase/migrations/` and `SEO-Tools/supabase/functions/` in order. This creates the schema, RLS policies, indexes, and helper functions.

### Steps

- [ ] 3.1 In the Supabase dashboard, click the **SQL Editor** icon in the left sidebar (looks like a database with `</>`).
- [ ] 3.2 Open the file [`SEO-Tools/supabase/migrations/0001_initial_schema.sql`](../supabase/migrations/0001_initial_schema.sql) in your code editor. Select all (`Ctrl+A`), copy.
- [ ] 3.3 In Supabase SQL Editor, click **New query**. Paste the contents. Click the green **Run** button (bottom-right) or press `Ctrl+Enter`.
I got this security pop-up with these options: Along with the option I picked 
```
Potential issue detected with your query

**⚠️ The following potential issue has been detected:**
*Ensure that these are intentional before executing this query.*

### New tables will not have Row Level Security enabled
Without RLS, any client using your project's `anon` or `authenticated` keys can read and write to these tables. Enable RLS and add policies before exposing this table via the API. [Learn more]

*Please confirm that you would like to execute this query.*

**Options:**
- [ ] Cancel
- [ ] Run without RLS
- [x] Run and enable RLS
```
output: Success. No rows returned

- [ ] 3.4 You should see "Success. No rows returned." or a similar success message. If you see a red error, **stop and copy the full error message into a note** before troubleshooting (see Common errors below).

- [ ] 3.5 Repeat steps 3.2-3.4 for each of these files **in order**:
  - [`0002_pgvector.sql`](../supabase/migrations/0002_pgvector.sql) — enables the pgvector extension. **Important:** if you get an error saying the `vector` extension is not available, see Common errors.
  - [`0003_rls_policies.sql`](../supabase/migrations/0003_rls_policies.sql)
  - [`0004_indexes.sql`](../supabase/migrations/0004_indexes.sql)
```
for the file:0004_indexes.sql -I got this pop up. 
```
## Potential issue detected with your query

**⚠️ The following potential issue has been detected:**
*Ensure that these are intentional before executing this query*

### Query has destructive operations
Make sure you are not accidentally removing something important.

*Please confirm that you would like to execute this query.*

**Options:**
- [ ] Cancel
- [x] Run this query
```
Output I got :
```
Failed to run sql query: ERROR:  0A000: cannot use subquery in index expression
LINE 73:         (select keyword from raw_keywords where raw_keywords.id = keyword_classifications.raw_keyword_id)
```

- [ ] 3.6 Now run each file in [`SEO-Tools/supabase/functions/`](../supabase/functions/) (order does not matter for these):
  - [`apply_tier0_regex_filter.sql`](../supabase/functions/apply_tier0_regex_filter.sql)
  - [`apply_tier0_competitor_navigational_filter.sql`](../supabase/functions/apply_tier0_competitor_navigational_filter.sql)
  - [`compute_priority_score.sql`](../supabase/functions/compute_priority_score.sql)
  - [`check_cost_ceiling.sql`](../supabase/functions/check_cost_ceiling.sql)

### Verify section 3

Run this query in the SQL Editor:

```sql
select table_name
from information_schema.tables
where table_schema = 'public'
order by table_name;
```

- [x] You should see at least 24 tables including: `clients`, `client_members`, `niches`, `seed_keywords`, `competitors`, `competitor_brand_names`, `raw_keywords`, `keyword_classifications`, `clusters`, `keyword_cluster_map`, `pages`, `pipeline_runs`, `api_cost_log`, `human_reviews`, `quality_audits`, `cross_validation_events`, `taxonomy_suggestions`.

Run this query:

```sql
select extname, extversion from pg_extension where extname = 'vector';
```

- [x] You should see `vector` listed with a version (e.g., `0.7.0`). If you see zero rows, pgvector is not installed — see Common errors.

Run this query:

```sql
select proname from pg_proc where proname in (
  'apply_tier0_regex_filter',
  'apply_tier0_competitor_navigational_filter',
  'compute_priority_score',
  'check_cost_ceiling',
  'lock_run_cost_ceiling',
  'refresh_priority_scores'
);
```

- [ ] You should see all six function names. 
This is the output I got: Success. No rows returned

### Common errors

- **`extension "vector" is not available`** — In Supabase dashboard, go to **Database** → **Extensions**, search for `vector`, and click the toggle to enable it. Then re-run `0002_pgvector.sql`.
- **`relation "..." already exists`** — you ran a migration twice. The schema is already in place. Skip the duplicate run, but if you suspect partial corruption, contact Pranav before dropping anything.
- **`permission denied`** — you are using the wrong role. The SQL Editor uses the `postgres` super-user role by default — make sure you have not switched to `anon` in the role dropdown.
- **`Success. No rows returned` shown for BOTH a CREATE statement AND a verify SELECT** — this message is Supabase's success indicator for any DDL (CREATE TABLE / INDEX / FUNCTION), AND it's also what you see when a `SELECT` matches zero rows. They look identical, which makes it easy to think a migration ran when it didn't. **Fix:** when you run a verify `SELECT`, paste the first 3-5 actual result rows into your worklog, not just the status line. If a verify returns no rows after you "ran" a migration, check (a) the top-left **project selector** — make sure you are verifying in the same project you ran the migration in — and (b) re-run the migration file, watching for `Success. No rows returned` again as confirmation the DDL fired.
- **`syntax error at or near "..."` where the quoted text is not SQL** (e.g. `#!/`, `import`, `function`, a curly brace, etc.) — your clipboard had non-SQL content when you pasted into the SQL Editor, usually a leftover from a previous copy. **Fix:** in the source `.sql` file, click anywhere inside the file's text area, then `Ctrl+A` and `Ctrl+C`. Switch to the Supabase SQL Editor, click inside the editor pane, `Ctrl+A` and `Delete` to clear any residue, then `Ctrl+V`. Confirm the first line in the editor reads `-- ====` (a SQL comment) before clicking **Run**. Every file in `supabase/migrations/` and `supabase/functions/` starts with `-- ====`; anything else is wrong content.
- **`pg_proc` verify returns 0 rows even after the migrations ran cleanly** — symptom: the tables-and-pgvector verifies pass, but the function-name verify query returns nothing. Cause: step **3.6** (running the four files in [`supabase/functions/`](../supabase/functions/)) was skipped. The function files are **separate** from the four migration files in `supabase/migrations/` and must be run individually as their own paste-and-run loop. **Fix:** return to step 3.6, run each of the four function files, then re-run the `pg_proc` verify query — it should now return 6 rows (each of `check_cost_ceiling.sql` and `compute_priority_score.sql` defines two functions, which is why 4 files produce 6 function names).

---

## 4. Load Webley seed data

**What you're doing:** inserting two sample clients (Webley + a hypothetical clothing brand) so we can test multi-tenancy from day one.

### Steps

- [ ] 4.1 Open [`SEO-Tools/supabase/seed/dummy_clients.sql`](../supabase/seed/dummy_clients.sql) in your code editor. Select all, copy.
- [ ] 4.2 In Supabase SQL Editor → **New query** → paste → **Run**.

### Verify section 4

```sql
select name, slug, onboarding_status from clients;
```

- [ ] You should see two rows: **Webley Media** and **Acme Threads**, both with `onboarding_status = 'active'`.

```sql
select count(*) as niche_count from niches where client_id = '11111111-1111-1111-1111-111111111111';
```

- [ ] `niche_count` should be 6 (the six Webley niches: healthcare, pharmaceuticals, fintech, b2b_saas, ecommerce_dtc, professional_services).

```sql
select count(*) as page_count from pages where client_id = '11111111-1111-1111-1111-111111111111';
```

- [ ] `page_count` should be 12 (Webley's static pages).

### Common errors

- **`duplicate key value violates unique constraint`** — you ran the seed twice. Either it was already loaded (check the verify queries; if data is there, you're done) or delete the existing rows first: `delete from clients;` (cascades to dependents) then re-run.

---
.
## 5. Get an OpenRouter API key

**What you're doing:** signing up for OpenRouter, which is a single API gateway that proxies to many LLM and embedding-model providers (OpenAI, Google, Anthropic, Perplexity, Qwen, etc.). The pipeline talks to **one** API key here, and we pick the actual model (`google/gemini-2.0-flash-001`, `openai/text-embedding-3-small`, etc.) via env vars in `SEO-Tools/.env`. To switch models later, you edit one line in `.env` — no code, no n8n, no prompt changes. See [ADR 0005](./adr/0005-openrouter-unified-gateway.md) for the rationale.

### Steps

- [x] 5.1 Go to https://openrouter.ai. Click **Sign In** (top-right) → **Sign in with GitHub**. Authorize.
- [x] 5.2 Once signed in, click your avatar (top-right) → **Keys** → **Create Key**.
  - **Name:** `seo-tools-prod` Api Key : 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
  - **Credit limit:** leave blank (use account balance) OR set $50 for a hard cap. Recommended for an intern's first key: $50 cap so a runaway loop can't burn the whole balance.
  - Click **Create**. Copy the key (starts with `sk-or-v1-...`). **Save it immediately** to your password manager — OpenRouter shows the full key exactly once.
- [x] 5.3 Add credit: top-right avatar → **Credits** → **Add Credits**. Add **$10** for Phase 1 testing. This is enough for several months of dev work plus your first real client run. (Optional now, but the verify curl in this section will fail with HTTP 402 until you have some credit.)
- [ ] 5.4 Browse the **Models** catalog at https://openrouter.ai/models. The defaults already in `SEO-Tools/.env.example` are sensible May-2026 picks:
  - **Embeddings:** `openai/text-embedding-3-small` @ 768 dim ($0.02/M tokens; matches our `vector(768)` schema)
  - **Primary LLM:** `google/gemini-2.0-flash-001` (cheap, fast, structured-JSON-capable)
  - **Cross-validation second-pass LLM:** `openai/gpt-4o-mini` (deliberately different family from the primary, to make agreement signal meaningful)

models i picked-
embedding: qwen/qwen3-embedding-8b | 33K context ,$0.01 per 1M tokens
Primary LLM: deepseek/deepseek-v4-flash |1.05M context, $0.126 /M input tokens, $0.252 /M output tokens
Cross-validation second-pass LLM: openai/gpt-5.4-nano |400K context, $0.20 /M input tokens, $1.25 /M output tokens


  If you want different ones, copy the model **slug** (the path-style ID under the model name, e.g. `perplexity/pplx-embed-v1-4b`) from the Models page and paste it into the relevant `DEFAULT_*_MODEL` line in your `.env` later. Don't change models yet; finish setup with the defaults first, then swap once everything works end-to-end.
- [ ] 5.5 Note about the `HTTP-Referer` and `X-Title` headers: OpenRouter uses these for per-app analytics in your dashboard. They are already set as env vars in `.env.example` (`OPENROUTER_HTTP_REFERER`, `OPENROUTER_APP_TITLE`); no UI step needed.

### Verify section 5

**Note:** `curl.exe` with inline JSON does not work reliably in PowerShell due to quoting rules. Use the dedicated verify script instead — it uses `Invoke-RestMethod` and has been confirmed working (3/3 PASS on 2026-05-15).

Run in PowerShell (you will be prompted for the key — nothing is stored):

```powershell
powershell -ExecutionPolicy Bypass -File "SEO-Tools/scripts/verify_openrouter.ps1"
```

Or pass the key directly (session only, not saved anywhere):

```powershell
powershell -ExecutionPolicy Bypass -File "SEO-Tools/scripts/verify_openrouter.ps1" -ApiKey "sk-or-v1-..."
```

Expected output when everything is working:

```
=== Chat test: Primary LLM (google/gemini-2.0-flash-001) ===
PASS  response: Ok

=== Embedding test: openai/text-embedding-3-small (expecting 768 dims) ===
PASS  embedding length: 768

=== Chat test: Cross-validation LLM (openai/gpt-4o-mini) ===
PASS  response: Ok.

==============================
Results: 3 PASS / 0 FAIL
==============================
```

- [x] All three lines show `PASS` and the summary reads `3 PASS / 0 FAIL`.
  - Verified working on 2026-05-15: `google/gemini-2.0-flash-001` ✓, `openai/text-embedding-3-small` @ 768 dim ✓, `openai/gpt-4o-mini` ✓

### Common errors

- **`HTTP 401 No auth credentials found`** — `OPENROUTER_API_KEY` is wrong, empty, or the `Bearer ` prefix is missing in the Authorization header. Re-copy the key from your password manager (no extra whitespace) and confirm the curl has `Authorization: Bearer sk-or-v1-...`.
- **`HTTP 402 Insufficient credits`** — your OpenRouter balance is $0. Complete step 5.3 (add credit).
- **`HTTP 404 No allowed providers are available for the selected model`** — the model slug is mistyped. The correct format is `provider/model-name`, e.g. `openai/text-embedding-3-small` (with the dash, with the `-small`). Compare against the slug on https://openrouter.ai/models.
- **`HTTP 429 Rate limit exceeded`** — some free-tier models on OpenRouter (with `:free` suffix) are aggressively rate-limited. The default models we use (`openai/text-embedding-3-small`, `google/gemini-2.0-flash-001`, `openai/gpt-4o-mini`) are NOT in the free tier, so this is rare; if you see it, either you accidentally picked a `:free` model or you are sending many requests per second from a test loop.

---

## 6. Get a SerpAPI key (optional for Phase 1)

**What you're doing:** signing up for SerpAPI, which we use in WF-04 to pull live SERP results per cluster head term. You can skip this section until you are ready to run WF-04.

### Steps

- [x] 6.1 Go to https://serpapi.com/users/sign_up. Create an account.
- [x] 6.2 Verify your email.
- [x] 6.3 On the dashboard, copy your **Private API Key** (left sidebar → **API Key**).
Api key : c68aa5b90d549f985c2f394a14628116f5465202fe13b1dbc34ea76de5564c2c
- [x] 6.4 Save to your password manager.

### Verify section 6

**Note:** `curl.exe` with query-string `&` characters does not work reliably in PowerShell. Use the services verify script instead — tested and confirmed working on 2026-05-15.

```powershell
powershell -ExecutionPolicy Bypass -File "SEO-Tools/scripts/verify_services.ps1" -SerpApiKey "your-key" -SlackBotToken "skip" -SlackChannelId "skip"
```

Expected output:
```
=== SerpAPI: test search ==
PASS  search_metadata.status = Success
```

- [x] `search_metadata.status = Success` — confirmed working on 2026-05-15.

### Common errors

- **`invalid_api_key`** — the key was copied wrong. Re-copy from the dashboard.
- **`max_searches_reached`** — you exhausted the free 100/month. For Phase 1 testing this is unlikely; if it happens, the system's WF-04 budget cap will prevent it in production.

---

## 7. Create the Slack bot

**What you're doing:** creating a Slack app that posts review cards to a dedicated channel and listens for button clicks (approve/reject/etc.) from interns.

### Steps

- [x] 7.1 Go to https://api.slack.com/apps. Sign in if asked.
- [x] 7.2 Click **Create New App** (top right) → **From scratch**.
- [x] 7.3 Fill in:
  - **App Name:** `SEO-Tools HITL`
  - **Pick a workspace:** Webley Media's workspace.
- [x] 7.4 Click **Create App**.
- [x] 7.5 You are now on the app's **Basic Information** page. Scroll to **App Credentials** and copy the **Signing Secret** (click "Show", then copy). Save to your password manager.

Slack API: Basic Information
App Name: SEO-Tools HITL
App Credentials
App ID: A0B3V27078B
Date of App Creation: May 15, 2026
Client ID: 11122421376323.11131075007283
Client Secret: c48bdf21f3cbf230b3d44c01f03adeb7
Signing Secret: 546c812530f339a9fc723a1c07dc2d7c
Verification Token: douLA5WnYeFUD1gOU1xHOH9o

- [x] 7.6 In the left sidebar, click **OAuth & Permissions**.
- [x] 7.7 Scroll to **Scopes** → **Bot Token Scopes**. Click **Add an OAuth Scope** and add these (one at a time):
  - `chat:write`
  - `commands`
  - `channels:read`
  - `groups:read`
  - `chat:write.public` (so the bot can post to channels without being explicitly invited)
- [x] 7.8 Scroll up to **OAuth Tokens for Your Workspace** → click **Install to Workspace** → review permissions → **Allow**.
- [x] 7.9 You are redirected back. Copy the **Bot User OAuth Token** (starts with `xoxb-...`). Save to your password manager.
OAuth Tokens-Bot User OAuth Token: xoxb-11122421376323-11134110887429-nhwtxduxAESuSwFCFzhC9m6e

- [x] 7.10 Switch to your Slack desktop client (or slack.com). Create a new channel:
  - Channel name: `#seo-tools-hitl`
  - Type: **Private** (recommended for internal review).
  - Add yourself and Pranav.
- [x] 7.11 In the channel, type `/invite @SEO-Tools HITL` to add the bot. Confirm.
- [x] 7.12 Right-click the channel name → **Copy link**. The URL ends in `/CXXXXXXXXX` — that suffix is the channel ID. Copy and save it.
/C0B43A7QG5P

- [ ] 7.13 (Skip Interactivity & Slash Commands setup for now — we configure those later in Section 14 once you have the cloudflared public URL.)

### Verify section 7

**Note:** `curl.exe` with backtick-escaped JSON does not work reliably in PowerShell. Use the services verify script instead — tested and confirmed working on 2026-05-15.

```powershell
powershell -ExecutionPolicy Bypass -File "SEO-Tools/scripts/verify_services.ps1" `
  -SlackBotToken "xoxb-11122421376323-11134110887429-nhwtxduxAESuSwFCFzhC9m6e" `
  -SlackChannelId "C0B43A7QG5P" `
  -SerpApiKey "skip"
```

Expected output:
```
=== Slack: post message to channel ===
PASS  message posted to channel C0B43A7QG5P
```

- [x] `PASS  message posted to channel C0B43A7QG5P` — confirmed working on 2026-05-15.
- [x] In Slack, the message "setup verification test from intern setup guide" appears in `#seo-tools-hitl`.

### Common errors

- **`not_in_channel`** — the bot is not in the channel. Re-run `/invite @SEO-Tools HITL` in the channel.
- **`invalid_auth`** — bad bot token. Re-copy from the app's OAuth & Permissions page.
- **`channel_not_found`** — channel ID is wrong. Re-copy from the channel link.

---

## 8. Create the Telegram bot (optional)

**What you're doing:** creating a Telegram bot as a parallel HITL channel. Useful if your team uses Telegram more than Slack, or as a redundant alert channel. Skip if you only want Slack.

### Steps

- [x] 8.1 In Telegram, search for `@BotFather` (the official bot, has a blue checkmark). Start a chat.
- [x] 8.2 Send `/newbot`.
- [x] 8.3 Reply with a display name for the bot, e.g. `Webley SEO-Tools HITL`.
- [x] 8.4 Reply with a unique bot username ending in `bot`, e.g. `webley_seotools_hitl_bot`. If taken, try another.
- [x] 8.5 BotFather replies with a token (looks like `123456789:AAH...`). Save to your password manager.
  Bot username: `@webley_seotools_hitl_bot` — `t.me/webley_seotools_hitl_bot`
  Bot token: `8616386423:AAHhENvweAI4Qc88vg92Dp09i0kauKopbac`
- [x] 8.6 Create a new private Telegram group called "SEO-Tools HITL". Add yourself + Pranav.
- [x] 8.7 Add the bot to the group. **Note:** the "Invite members" search only shows contacts — bots don't appear there. Instead, go to your direct chat with `@webley_seotools_hitl_bot`, tap its name → **Add to Group** → select `SEO-Tools HITL`. Or open `https://t.me/webley_seotools_hitl_bot?startgroup=true` which prompts you to pick a group directly.
- [x] 8.8 Send any message in the group after adding the bot (e.g. `hello`). Required — Telegram only registers the chat after a message is sent.
- [x] 8.9 Run the PowerShell debug script to get the chat ID:
  ```powershell
  powershell -ExecutionPolicy Bypass -File "SEO-Tools/scripts/_tg_debug.ps1"
  ```
  Output: `chat_id=-4993060055  type=group  title=SEO-Tools HITL`
- [x] 8.10 Save the chat ID to your password manager. Fill it in below:
  Chat ID: `-4993060055` (group: `SEO-Tools HITL`)

### Verify section 8

Command run:
```powershell
powershell -ExecutionPolicy Bypass -File "SEO-Tools/scripts/verify_services.ps1" `
  -TelegramBotToken "8616386423:AAHhENvweAI4Qc88vg92Dp09i0kauKopbac" `
  -TelegramChatId   "-4993060055" `
  -SlackBotToken    "skip" `
  -SerpApiKey       "skip"
```

Output:
```
=== Slack: SKIPPED ===

=== SerpAPI: SKIPPED ===

=== Telegram: send message to group ===
PASS  message sent, message_id=3

==============================
Results: 1 PASS / 0 FAIL
==============================
```

- [x] `PASS  message sent, message_id=3` — confirmed working on 2026-05-15.
- [x] Message "setup verification test from intern setup guide" appeared in the `SEO-Tools HITL` Telegram group.

### Common errors

- **`Forbidden: bot was blocked`** — you blocked the bot. Unblock in Telegram settings.
- **`Bad Request: chat not found`** — chat ID is wrong. For groups it must be negative.
- **`getUpdates` returns empty (`result: []`)** — either the bot has not been added to the group yet, or no message was sent in the group after adding the bot. Complete steps 8.6–8.8, send a message, then re-run `_tg_debug.ps1`. This was the confirmed root cause on 2026-05-15.

---

## 9. Deploy the Python worker on Railway

**What you're doing:** Railway will build the Docker image from [`SEO-Tools/python-worker/Dockerfile`](../python-worker/Dockerfile) and host the FastAPI clustering service at a public HTTPS URL. n8n's WF-03 calls this URL.

### Steps

- [ ] 9.1 Push the SEO-Tools code to a private GitHub repo first. From PowerShell, in the workspace root:
  ```powershell
  cd "c:\Users\prana\OneDrive\Documents\Webley Media\WebleyTools\n8n-Scrapper+Builder\n8n_Automation_Builder"
  git status
  ```
  If the repo is not already pushed to GitHub, ask Pranav how he wants to handle that (most likely: keep using the existing repo; do not create a separate repo until Phase 1 is fully shipped per the SEO-Tools layout plan).
- [x] 9.2 Go to https://railway.app. Sign in with GitHub.
- [x] 9.3 Click **New Project** → **Deploy from GitHub repo**.
- [x] 9.4 Authorize Railway to access your GitHub if asked. **Important:** only authorize the specific repo containing SEO-Tools — do not grant access to all repos.
- [x] 9.5 Pick the repo containing the `SEO-Tools/` folder.
- [x] 9.6 Railway will scan the repo. By default it looks at the root for a `Dockerfile`. We need to point it at the sub-folder. After it provisions an empty service:
  - Open the service → **Settings** → **Build & Deploy**.
  - **Root Directory:** `SEO-Tools/python-worker`
  - **Builder:** `Dockerfile`
  - Save.
- [ ] 9.7 Click the **Variables** tab for the **service** (not "Shared Variables" at project level — those don't automatically reach the service). Add these directly (one at a time, **Add Variable** button):
  - `SUPABASE_URL` — from Section 2
    https://qpfjpjshpnndimoayiwb.supabase.co

  - `SUPABASE_SERVICE_ROLE_KEY` — from Section 2
----
"how i found key: 
How to Find the Supabase `service_role` API Key
*Note: Supabase recently updated their dashboard UI. The newer `sb_publishable...` and `sb_secret...` keys are now shown by default, while the older JWT-style keys have been moved to a separate tab.*

To locate your `service_role` key (the string starting with `eyJ...`), follow these steps:

1. Navigate to **Project Settings** in your Supabase dashboard.
2. Select **API** from the sidebar menu.
3. In the main panel, look just below the "Configure API keys..." header to find the navigation tabs.
4. Click on the tab labeled **Legacy anon, service_role API keys** (located next to the default "Publishable and secret API keys" tab).
5. Locate the row labeled **service_role**.
6. Click the **eye icon** to reveal your secret key.
7. Click the **copy icon** to copy the full `` string to your clipboard."

key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFwZmpwanNocG5uZGltb2F5aXdiIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3ODc0NDgyNSwiZXhwIjoyMDk0MzIwODI1fQ.1RTqb0WSh2hzHKqrhW8RTKGBsIxRnFIBzNIo9c1ay6A
-----

  - `WORKER_AUTH_TOKEN` — generate a random 32-character string. In PowerShell:
    ```powershell
    -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object {[char]$_})
    ```
    Copy the output. Save to your password manager.
    What I got : skayblDKeN3wULj1MimzZfCI69OvpunH
  - `LOG_LEVEL` — `info`
- [ ] 9.8 Click **Deploy** (or it will redeploy automatically after you save Root Directory). Watch the build logs in the **Deployments** tab. Build takes ~3-5 minutes (HDBSCAN compiles C extensions).
- [ ] 9.9 Once you see `Application startup complete` in the logs, go to **Settings** → **Networking** → **Generate Domain**. Copy the public URL (looks like `seo-tools-python-worker-production-abcd.up.railway.app`). Save it.

domain: seo-tools-production-c347.up.railway.app

### Verify section 9

**Worker URL:** `https://seo-tools-production-c347.up.railway.app`
**WORKER_AUTH_TOKEN:** `skayblDKeN3wULj1MimzZfCI69OvpunH`

Run:
```powershell
powershell -ExecutionPolicy Bypass -File "SEO-Tools/scripts/verify_worker.ps1" `
  -WorkerUrl   "https://seo-tools-production-c347.up.railway.app" `
  -WorkerToken "skayblDKeN3wULj1MimzZfCI69OvpunH"
```

Expected output:
```
=== Health check ===
PASS  {"ok":true,"version":"0.1.0"}

=== Cluster endpoint (empty payload auth test) ===
PASS  clusters=0, unclustered=0
```

**Diagnosis (2026-05-16):** `/health` passed but `/cluster` returned HTTP 500 with empty body. Root-cause investigation across three commits:

1. **Attempt 1 (bad):** Pinned `supabase==2.3.4` — caused build failure due to `httpx` version conflict. Reverted.
2. **Attempt 2 (commits `1b367e0` + `8addcd4`):** Reverted `supabase==2.11.0`, added global exception handler (so 500 body is never empty), added Supabase connectivity startup probe, added 8-second PostgREST timeout so requests fail fast.
3. **Real root cause confirmed (2026-05-16):** With the global handler in place, `/cluster` now returns a proper JSON error body: `"ValidationError: Field required — supabase_url / supabase_service_role_key"`. The Railway **Shared Variables** were added at project scope but were not applied to the service itself. The env vars `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are not reaching the worker process.

**Fix required:** In Railway → service → **Variables** tab, add `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` directly to the service (not as shared variables), then redeploy.

- [x] `/health` → `PASS {"ok":true,"version":"0.1.0"}` — confirmed 2026-05-16
- [ ] `/cluster` → `PASS clusters=0, unclustered=0` — pending: fix Railway Variables (see above) then redeploy

### Common errors

- **Build fails on `hdbscan`** — the Dockerfile installs build-essential before pip; if you removed that line, restore it. Railway sometimes times out long builds — retry from the **Deployments** tab.
- **Cold start delays** — Railway sleeps idle services. First request after 5+ minutes takes ~10 seconds to wake. This is fine for n8n (which has retries).
- **`500 Internal Server Error` on /cluster** — usually a Supabase connection issue. Check **Variables** that `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are correct (no trailing whitespace, no quotes).

---

## 10. Run n8n locally in Docker

> **Already using Elestio-hosted n8n?** Skip Sections 10 and 11 entirely — go straight to **Section 10B** below.

**What you're doing:** running an n8n instance on your laptop in a Docker container. Data persists in a Docker volume so restarts do not lose workflows.

### Steps

- [ ] 10.1 Open PowerShell. Make a folder for n8n's persistent data:
  ```powershell
  mkdir "$env:USERPROFILE\n8n-data" -Force | Out-Null
  ```
- [ ] 10.2 Create a `docker-compose.yml` file in your home directory:
  ```powershell
  notepad "$env:USERPROFILE\docker-compose.yml"
  ```
  Paste the following, save, close Notepad:
  ```yaml
  services:
    n8n:
      image: n8nio/n8n:latest
      restart: unless-stopped
      ports:
        - "5678:5678"
      environment:
        - N8N_HOST=localhost
        - N8N_PORT=5678
        - N8N_PROTOCOL=http
        - WEBHOOK_URL=http://localhost:5678/
        - GENERIC_TIMEZONE=Asia/Kolkata
        - N8N_RUNNERS_ENABLED=true
        - N8N_BLOCK_ENV_ACCESS_IN_NODE=false
        - N8N_SECURE_COOKIE=false
      volumes:
        - n8n_data:/home/node/.n8n

  volumes:
    n8n_data:
  ```
- [ ] 10.3 Start n8n:
  ```powershell
  cd $env:USERPROFILE
  docker compose up -d
  ```
  Wait for the image pull (first run only, ~2 minutes).
- [ ] 10.4 Check it is running:
  ```powershell
  docker compose ps
  ```
  You should see the `n8n` service `running`.
- [x] 10.5 Open http://localhost:5678 in your browser.
- [x] 10.6 Create the owner account: email, first/last name, password. Save credentials to your password manager.
- [x] 10.7 Skip the survey screens.
- [ ] 10.8 Once at the n8n home, click your avatar (top-right) → **Settings** → **API**. Click **Create an API key**. Label it `seo-tools-agent`. Copy the key. Save it.

Api key (local n8n): eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJmNDQ2YzQ3MS02YzMwLTQyY2QtYTliOS1hMjkxM2UxZGFmZTIiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwianRpIjoiNTljZDEyZDAtYzY1Zi00ZjhhLTliYzAtNjc1MmRjZmIwYTQ2IiwiaWF0IjoxNzc5MDk4MzE0fQ.rwZ7tYlSj9DC2tChD4xvuUibIMyGUYaL_lmBRrz0GJE

API Key (elest.io): eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhN2MwNDJlNS05ZTI4LTQ3ZmYtOTdmNC0xYmYyNzI3MWIyOTgiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwianRpIjoiNGI2ZmM1MDgtZDAxNi00NTA1LTk4NWUtZDhlYWJiYjk4MzNhIiwiaWF0IjoxNzc5MTAwODU3fQ.7KwNdMLf9-q6tnl_2IrN_Y2eSIsLlkJdbpDx639Av24

### Verify section 10

- [x] http://localhost:5678 loads the n8n UI.
- [x] You can create a "Hello World" workflow with a Manual Trigger → Set node and execute it once.

### Common errors

- **Port 5678 already in use** — another service is using the port. Stop it, or change the port mapping in `docker-compose.yml` (e.g., `"5679:5678"`) and use http://localhost:5679 instead.
- **Docker Desktop not running** — start it from the Start menu. Wait for the whale icon to stop pulsing.
- **`WEBHOOK_URL` warning in logs** — fine for now; we update it after the cloudflared tunnel in Section 11.

### Stopping and restarting n8n

```powershell
cd $env:USERPROFILE
docker compose down       # stop (data persists in the volume)
docker compose up -d      # start again
docker compose logs -f n8n  # tail logs
```

---

## 10B. Use Elestio-hosted n8n (online, accessible from anywhere)

**What you're doing:** using a managed cloud n8n instance on Elestio. It runs 24/7, has a valid HTTPS certificate, and is reachable from any browser or from Slack/Telegram webhooks without a Cloudflare tunnel. **This replaces Sections 10 and 11 for your setup.**

**Instance URL:** `https://n8n-webley-u35816.vm.elestio.app/`

### Steps

- [x] 10B.1 Open `https://n8n-webley-u35816.vm.elestio.app/` in your browser.
- [x] 10B.2 On the first-time setup screen, create the owner account:
  - **Email** — your business email (e.g., `pranav@webley.media`)
  - **First name / Last name** — your name
  - **Password** — 12+ characters; save to your password manager
  - Click **Get started**. Skip the survey screen.
  - If a login page appears instead of the setup screen, the owner account was pre-created by Elestio. Check your Elestio dashboard → **Service info** for the default credentials, log in, and change the password immediately.
- [ ] 10B.3 Click your avatar (top-right) → **Settings** → **API** → **Create an API key**.
  - Label: `seo-tools-agent`
  - Copy the key (starts with `n8n_api_...`). Save to password manager and paste into HANDOFF-TEMPLATE under `N8N_API_KEY`.

  API Key (elest.io): `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhN2MwNDJlNS05ZTI4LTQ3ZmYtOTdmNC0xYmYyNzI3MWIyOTgiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwianRpIjoiNGI2ZmM1MDgtZDAxNi00NTA1LTk4NWUtZDhlYWJiYjk4MzNhIiwiaWF0IjoxNzc5MTAwODU3fQ.7KwNdMLf9-q6tnl_2IrN_Y2eSIsLlkJdbpDx639Av24`

- [ ] 10B.4 Verify required environment variables are set. In Elestio:
  - Go to your Elestio dashboard → **SEO-Tools n8n** service → **Env Vars** tab (or **Software config** tab depending on your Elestio version).
  - Confirm or add:

  | Variable | Value |
  |---|---|
  | `GENERIC_TIMEZONE` | `Asia/Kolkata` |
  | `N8N_RUNNERS_ENABLED` | `true` |
  | `N8N_BLOCK_ENV_ACCESS_IN_NODE` | `false` |
  | `WEBHOOK_URL` | `https://n8n-webley-u35816.vm.elestio.app/` |

  Elestio typically sets `WEBHOOK_URL` automatically to your instance URL. Verify it matches exactly (including the trailing slash). Save and let the service restart if prompted.

- [ ] 10B.5 Quick smoke test: **+ New Workflow** → drag a **Manual Trigger** node → drag an **Edit Fields (Set)** node → connect them → click **Test workflow**. Should show "Workflow executed successfully". Delete the test workflow.

### Verify section 10B

- [x] `https://n8n-webley-u35816.vm.elestio.app/` loads the n8n UI from your phone on cellular (not on your home Wi-Fi) — confirms it is truly public.
- [x] Browser shows valid HTTPS (closed padlock) with a certificate issued to `*.vm.elestio.app`.

### Common errors

- **Login page instead of setup screen** — the owner account already exists (Elestio pre-created it). Check your Elestio dashboard → **Service info** for the default credentials. Log in and change the password from **Settings** → **Personal** → **Change Password**.
- **WEBHOOK_URL mismatch** — n8n webhooks will fail silently if `WEBHOOK_URL` does not exactly match the public URL. Copy-paste it from the browser address bar (no trailing path, just the origin + `/`).
- **Env var changes don't take effect** — Elestio requires a service restart after env var saves. Click **Restart** in the Elestio dashboard after saving.
- **Cannot find Env Vars tab** — depending on your Elestio plan, environment variables may be under **Software** → **Env** or **Tools** → **Env Editor**. Look for a page listing `KEY=VALUE` pairs.

### Skipping Section 11

Since Elestio provides a permanent public HTTPS URL, **you do not need Section 11 (Cloudflare tunnel)**. Skip it entirely. Wherever the guide later refers to `https://n8n-seotools.<your-domain>`, substitute `https://n8n-webley-u35816.vm.elestio.app` instead.

---

## 11. Expose n8n via a Cloudflare tunnel

> **Using Elestio (Section 10B)?** Skip this entire section — your instance is already public HTTPS. Continue to Section 12.

**What you're doing:** giving your local n8n instance a public HTTPS URL so Slack and Telegram can reach it when an intern clicks an "Approve" button in a HITL card. Without this, the local n8n is only reachable from your own laptop.

We will use **Cloudflare Tunnel** because it is free, requires no port forwarding, and is more stable than ngrok for production-like work.

### 11A. Quick tunnel (5 minutes, no Cloudflare account needed, for first-time testing)

- [x] 11.1 Download `cloudflared` for Windows from https://github.com/cloudflare/cloudflared/releases/latest — file named `cloudflared-windows-amd64.exe`.
- [x] 11.2 Rename the file to `cloudflared.exe` and put it in `C:\cloudflared\`. Add `C:\cloudflared\` to your PATH environment variable (Win+R → `sysdm.cpl` → Advanced → Environment Variables → edit Path).
- [x] 11.3 Open a new PowerShell window. Verify install:
  ```powershell
  cloudflared --version
  ```
- [ ] 11.4 Start a one-shot tunnel:
  ```powershell
  cloudflared tunnel --url http://localhost:5678
  ```
- [ ] 11.5 Wait ~10 seconds. You will see a line like:
  ```
  +--------------------------------------------------------------------------------------------+
  |  Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):  |
  |  https://abc-def-ghi-jkl.trycloudflare.com                                                 |
  +--------------------------------------------------------------------------------------------+
  ```

  url i got : https://problems-medium-sharp-tumor.trycloudflare.com
- [ ] 11.6 Open that URL in your browser. n8n should load.

**Important:** Quick tunnels die when you close the PowerShell window. They get a new random URL each restart. **Use only for verification.** For day-to-day work, set up a named tunnel (11B).

### 11B. Named tunnel (30 minutes, recommended)

- [ ] 11.7 Go to https://dash.cloudflare.com. Sign in.
- [ ] 11.8 If you do not already have a domain on Cloudflare:
  - Cheapest path: buy a `.xyz` from Cloudflare Registrar for ~$1/year, or use any domain you already own and switch its nameservers to Cloudflare's.
  - Or: skip 11B and use Quick Tunnels every time you work. Acceptable for an intern's dev work; Pranav can set up a named tunnel later.
- [ ] 11.9 Once your domain is on Cloudflare, go to **Zero Trust** (in the sidebar) → **Networks** → **Tunnels**.
- [ ] 11.10 Click **Create a tunnel** → **Cloudflared** → **Next**.
- [ ] 11.11 Tunnel name: `n8n-seotools`. **Save tunnel**.
- [ ] 11.12 On the "Install and run a connector" screen, pick **Windows**. Copy the command shown (looks like `cloudflared service install eyJh...`).
- [ ] 11.13 In an **elevated** PowerShell (Run as Administrator), paste and run the command. This installs cloudflared as a Windows service so it runs at boot.
- [ ] 11.14 Back in the Cloudflare UI, click **Next**.
- [ ] 11.15 On the **Public Hostnames** tab:
  - **Subdomain:** `n8n-seotools` (or whatever you like)
  - **Domain:** pick your domain
  - **Service Type:** `HTTP`
  - **URL:** `localhost:5678`
- [ ] 11.16 Click **Save tunnel**.
- [ ] 11.17 In your browser, open `https://n8n-seotools.<your-domain>`. n8n should load.
- [ ] 11.18 Update n8n's `WEBHOOK_URL` to use the public URL. Edit `~/docker-compose.yml`:
  ```yaml
  environment:
    - WEBHOOK_URL=https://n8n-seotools.<your-domain>/
  ```
  Then:
  ```powershell
  cd $env:USERPROFILE
  docker compose up -d
  ```
  (No data loss; the volume is preserved.)

### Verify section 11

- [ ] Your tunnel URL (quick or named) loads the n8n UI from any browser (including from your phone on cellular).
- [ ] In the URL bar, the certificate shows valid HTTPS (closed padlock).

### Common errors

- **`cloudflared` not in PATH** — open a NEW PowerShell window after editing PATH. The old one will not have the change.
- **Tunnel works but n8n shows "Webhook URL is not HTTPS"** — make sure you updated `WEBHOOK_URL` and ran `docker compose up -d` (not `down`).
- **Slack callbacks return 4xx** — Slack rejects self-signed certs and certain HTTP redirects. The Cloudflare cert is valid; if you still see issues, check n8n's `WEBHOOK_URL` does NOT have a trailing port number.

---

## 12. Google Cloud OAuth + Sheets API (optional for Phase 1)

**What you're doing:** setting up OAuth so n8n can write to Google Sheets in WF-05. Skip until you're ready for WF-05.

### Steps

- [x] 12.1 Go to https://console.cloud.google.com. Sign in.
- [x] 12.2 Create a new project: top-bar project selector → **New Project** → Name `webley-seo-tools` → **Create**.
- [x] 12.3 In the search bar at the top, type **Google Sheets API** → click the result → **Enable**.
- [x] 12.4 Search for **Google Drive API** → **Enable** (n8n needs both).
- [x] 12.5 Sidebar → **APIs & Services** → **OAuth consent screen**:
  - **User Type:** External (unless you have Google Workspace) → **Create**.
  - **App name:** `SEO-Tools Sheet Sync`
  - **User support email:** your email
  - **Developer contact:** your email
  - **Save and Continue**.
  - **Scopes** screen: click **Add or Remove Scopes** → search for `sheets` → tick `https://www.googleapis.com/auth/spreadsheets` → search for `drive` → tick `https://www.googleapis.com/auth/drive.file` → **Update** → **Save and Continue**.
  - **Test users:** add your own Google email + any team email that will access the Sheet → **Save and Continue**.
- [ ] 12.6 Sidebar → **APIs & Services** → **Credentials** → **Create Credentials** → **OAuth client ID**:
  - **Application type:** Web application
  - **Name:** `SEO-Tools n8n`
  - **Authorized redirect URIs:** add the URI that matches your n8n setup (you can add both):
    - **Local + Cloudflare (Section 11):** `https://n8n-seotools.<your-domain>/rest/oauth2-credential/callback`
    - **Elestio (Section 10B):** `https://n8n-webley-u35816.vm.elestio.app/rest/oauth2-credential/callback`
    - If you are still on a Quick Tunnel, you'll have to update this URI each time the URL changes — another reason to use a named tunnel or Elestio.
  - **Create**.
- [ ] 12.7 A modal shows **Client ID** and **Client Secret**. Copy both. Save to your password manager.
- [ ] 12.8 Create the master spreadsheet:
  - Go to https://sheets.google.com → **Blank**.
  - Title: `SEO-Tools - Webley Media`.
  - Add tabs (rename Sheet1 to `Visibility`, then add `Performance`, `Creative`, `Infrastructure`, `Uncategorized`, `Niches`, `Themes`, `Audit`, `Cross-Validation`, `Cost`, `Taxonomy-Suggestions`).
  - Copy the spreadsheet ID from the URL (`https://docs.google.com/spreadsheets/d/SPREADSHEET_ID/edit`). Save it.


OAuth creds
Client ID: 177243875957-qfklbkpdu53cddkbdmlrq42e4jjee9po.apps.googleusercontent.com
Client Secret: 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
### Verify section 12

We will verify in Section 14 by adding the OAuth credential to n8n and running a test write.

### Common errors

- **"This app isn't verified"** — for an "External" consent screen with a non-published app, Google warns the user the first time they OAuth. Click **Advanced** → **Go to SEO-Tools n8n (unsafe)** → **Allow**. Safe because it is your own app.
- **`redirect_uri_mismatch`** when authorizing — the URI in the OAuth client must EXACTLY match what n8n sends. Copy it from n8n's credential setup screen rather than typing it.

---

## 13. Verify WPGraphQL endpoint

**What you're doing:** making sure the headless WordPress that backs Webley's blog exposes a working GraphQL endpoint. WF-00 (page inventory sync) calls this.

### Steps

- [x] 13.1 Ask Pranav for the WordPress admin URL (typically `https://wp.webleymedia.com/wp-admin` or similar). Log in.
https://cms.webleymedia.com/wp-admin/
- [x] 13.2 Sidebar → **Plugins** → **Installed Plugins**. Confirm **WPGraphQL** is in the list and **Active**. If 
not, install it from **Plugins** → **Add New** → search "WPGraphQL" → Install → Activate.
- [x] 13.3 Sidebar → **GraphQL** → **Settings**. Note the **GraphQL Endpoint** URL (typically `https://wp.webleymedia.com/graphql`).
https://cms.webleymedia.com/graphql

- [x] 13.4 Auth decision: **JWT Auth plugin is already installed and configured** on `cms.webleymedia.com` (Secret Key configured, endpoints active, RFC 7519 compliant — confirmed via WordPress dashboard). For Phase 1 (read-only queries), first try without auth. If that fails, use the JWT path below. Write access (Phase 2) will use JWT.

### Verify section 13

**Step 1 — Try without auth first (works for published posts in most WPGraphQL installs):**

```powershell
$endpoint = "https://cms.webleymedia.com/graphql"
$body = '{"query":"{ posts(first: 1) { nodes { title slug } } }"}'
Invoke-RestMethod -Method Post -Uri $endpoint -ContentType "application/json" -Body $body | ConvertTo-Json -Depth 5
```

- **If you see `data.posts.nodes` with post data** → no auth needed for Phase 1. Check this box and move on.
- **If you see an error like `"Not logged in"` or HTTP 401** → the endpoint requires auth. Use Step 2 below.

**Step 2 — JWT auth path (only needed if Step 1 fails):**

First, get a JWT token using a WordPress user account:

```powershell
$tokenResp = Invoke-RestMethod -Method Post -Uri "https://cms.webleymedia.com/wp-json/jwt-auth/v1/token" `
  -ContentType "application/json" `
  -Body '{"username":"YOUR_WP_USERNAME","password":"YOUR_WP_PASSWORD"}'
$jwt = $tokenResp.token
Write-Host "Token: $jwt"
```

Then use the token in the GraphQL request:

```powershell
$endpoint = "https://cms.webleymedia.com/graphql"
$body = '{"query":"{ posts(first: 1) { nodes { title slug } } }"}'
Invoke-RestMethod -Method Post -Uri $endpoint -ContentType "application/json" `
  -Headers @{ Authorization = "Bearer $jwt" } -Body $body | ConvertTo-Json -Depth 5
```

- [x] You should see a JSON response with `data.posts.nodes` containing at least one post's `title` and `slug`.
- [x] Note which path worked (no auth or JWT) — record it here so the n8n credential setup in Section 14 uses the right approach.

No auth result: **PASS** — endpoint publicly readable, no credentials required for Phase 1.
Verified post returned: title `"Building HIPAA-Compliant n8n Workflows for Healthcare"`, slug `"hipaa-n8n-workflows"`
JWT required: **No** — JWT Auth plugin is installed for future Phase 2 write access but not needed now.

### Common errors

- **`GraphQL not enabled` or 404** — WPGraphQL plugin is not active. Re-check Section 13.2.
- **Step 1 returns `"Not logged in"` but Step 2 also fails** — the WP username/password is wrong. Use your actual WordPress admin credentials (the ones you log into `cms.webleymedia.com/wp-admin` with).
- **`jwt_auth_bad_config` error** — the JWT Secret Key in the plugin settings is not saved. Go to **WordPress** → **JWT Auth** → verify Secret Key is set.
- **CORS errors** — n8n calls server-side, so CORS does not affect it. If you see CORS in browser dev tools while testing manually, ignore it.

---

## 14. Final cross-service verification checklist

Now that everything is provisioned, verify each service can reach the others. **Do not skip this** — it catches misconfigurations before we try to build the actual workflows.

### 14A. Configure HITL channel callbacks in Slack

Now that you have the cloudflared public URL:

- [ ] 14.1 Go back to https://api.slack.com/apps → your **SEO-Tools HITL** app.
- [ ] 14.2 Sidebar → **Interactivity & Shortcuts** → toggle **Interactivity** ON.
- [ ] 14.3 **Request URL:** `https://n8n-seotools.<your-domain>/webhook/hitl-decision-slack` (use your tunnel URL).
- [ ] 14.4 **Save Changes**.

(For Telegram, n8n sets the webhook automatically via its Telegram Trigger node. No manual step here.)

### 14B. Connectivity matrix

For each item, run the listed test. Tick the checkbox once it passes.

- [ ] **n8n -> Supabase:** in n8n, **Credentials** → **New** → **Supabase API** (name `Supabase_SEOTools`) → paste URL + service_role key → **Save**. Test from a temporary workflow with one Supabase node querying `select count(*) from clients`. Should return `2`.

- [ ] **n8n -> OpenRouter:** in n8n, **Credentials** → **New** → **HTTP Header Auth** (name `OpenRouter_SEOTools`) → Header name `Authorization`, Value `Bearer YOUR_OPENROUTER_KEY` (paste the actual `sk-or-v1-...` key) → **Save**. In a temporary workflow, add an **HTTP Request** node:
  - **Method:** POST
  - **URL:** `https://openrouter.ai/api/v1/chat/completions`
  - **Authentication:** Generic Credential Type → HTTP Header Auth → `OpenRouter_SEOTools`
  - **Body (JSON):** `{"model":"google/gemini-2.0-flash-001","messages":[{"role":"user","content":"reply with the single word ok"}]}`
  - Execute. Should return JSON with `choices[0].message.content` containing `ok`. Repeat with the embeddings endpoint (`/embeddings`, body `{"model":"openai/text-embedding-3-small","input":"hello","dimensions":768}`) and confirm `data[0].embedding` has 768 floats.

- [ ] **n8n -> Python worker:** in n8n, **Credentials** → **New** → **HTTP Header Auth** (name `PythonWorker_SEOTools`) → Header name `Authorization`, Value `Bearer <WORKER_AUTH_TOKEN>` → **Save**. Test with an HTTP Request node calling `<WORKER_URL>/health`. Should return `{"ok":true,...}`.

- [ ] **n8n -> Slack:** in n8n, **Credentials** → **New** → **Slack API** (name `Slack_SEOTools`) → use OAuth2 flow (sign in with the Slack account that installed the bot) → **Save**. Test with a Slack node posting `"connectivity test"` to `#seo-tools-hitl`. Should appear in Slack.

- [ ] **Slack -> n8n:** in n8n, create a temporary workflow with a **Webhook** node at path `hitl-decision-slack-test`, set Method = POST, **Activate** the workflow. From PowerShell:
  ```powershell
  curl.exe -X POST "https://n8n-seotools.<your-domain>/webhook/hitl-decision-slack-test" -H "Content-Type: application/json" -d '{"test":"slack to n8n"}'
  ```
  In n8n's execution log, you should see the request received. Then delete the test workflow.

- [ ] **n8n -> Telegram** (if configured): **Credentials** → **New** → **Telegram API** (name `Telegram_SEOTools`) → paste token → **Save**. Test with a Telegram node sending to your chat ID. Message should appear.

- [ ] **Telegram -> n8n** (if configured): create a temporary workflow with a **Telegram Trigger** node → connect the credential → activate. Send `/start` in your Telegram group. n8n should log the incoming message. Delete the test workflow.

- [ ] **n8n -> WPGraphQL:** **Credentials** → **New** → **HTTP Header Auth** (name `WPGraphQL_SEOTools`) → if auth is configured, set the header; if open endpoint, you can skip the credential. Test with an HTTP Request POST to the GraphQL endpoint with a simple query. Should return WordPress post data.

- [ ] **n8n -> Google Sheets** (if 12 completed): **Credentials** → **New** → **Google Sheets OAuth2 API** (name `GoogleSheets_SEOTools`) → paste Client ID + Secret → click **Sign in with Google** → complete OAuth → **Save**. Test with a Google Sheets node reading the master spreadsheet — should return the tab names.

### Verify section 14

- [ ] Every box in 14B is ticked.
- [ ] No credential's connectivity test failed.

---

## 15. Hand off back to the agent

You're done. Now we transfer everything to the build agent so it can resume Phase 1 with WF-ONBOARD construction.

- [ ] 15.1 Open [HANDOFF-TEMPLATE.md](./HANDOFF-TEMPLATE.md).
- [ ] 15.2 Pick a handoff method (the doc explains the two options).
- [ ] 15.3 Fill in every row of the template.
- [ ] 15.4 Tick "Ready to resume build" if every Section 14 connectivity test passed.
- [ ] 15.5 Copy the resume prompt at the bottom of HANDOFF-TEMPLATE.md and paste it into the Cursor chat with the build agent.

The agent will read your handoff, validate the credentials, and start building the n8n workflows. If anything was misconfigured, the agent will tell you exactly which test to re-run.

---

## Quick reference: cheat sheet of URLs

| Service | URL |
|---|---|
| Supabase dashboard | https://supabase.com/dashboard |
| OpenRouter dashboard / API keys | https://openrouter.ai/keys |
| OpenRouter models catalog | https://openrouter.ai/models |
| SerpAPI | https://serpapi.com |
| Slack apps | https://api.slack.com/apps |
| Telegram BotFather | tg://resolve?domain=BotFather |
| Railway | https://railway.app |
| Cloudflare Zero Trust | https://one.dash.cloudflare.com |
| Google Cloud Console | https://console.cloud.google.com |
| n8n (local) | http://localhost:5678 |
| n8n (public) | https://n8n-seotools.&lt;your-domain&gt; |

---

## What to do if something goes wrong

1. Re-read the **Verify** subsection for the step that failed. Most issues are caught there.
2. Check the **Common errors** subsection for the step.
3. If still stuck, capture:
   - The exact command or UI action you ran
   - The exact error message
   - A screenshot if a UI error
   Then ping Pranav or paste in the Cursor chat with the build agent.

Do not invent workarounds for security-sensitive steps (especially OAuth and tokens). Bad workarounds here cost real money or expose data.
