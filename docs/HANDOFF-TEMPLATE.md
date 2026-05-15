# Handoff template — SEO-Tools Phase 1

**Who fills this in:** the intern who just finished [MANUAL-SETUP-GUIDE.md](./MANUAL-SETUP-GUIDE.md).

**Who reads it:** the build agent (Cursor / Claude) that will resume building the n8n workflows.

**Why this exists:** secrets must never be pasted into chat. URLs and non-secret config can. This template separates the two and gives the agent a checklist of what was verified working, so it can pick up exactly where you left off without re-verifying everything.

---

## Part A — Where every credential goes

Two categories of secret. **Do not mix them up.**

### A.1 — Goes into `SEO-Tools/.env` (gitignored, never committed)

| .env key | What it is | Source |
|---|---|---|
| `SUPABASE_URL` | Project URL | Setup guide §2.7 |
| `SUPABASE_ANON_KEY` | Anon key | Setup guide §2.7 |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role key — **powerful** | Setup guide §2.7 |
| `SUPABASE_PROJECT_REF` | Project reference ID | Setup guide §2.7 |
| `OPENROUTER_API_KEY` | OpenRouter API key (`sk-or-v1-...`) | Setup guide §5.2 |
| `OPENROUTER_BASE_URL` | Defaults to `https://openrouter.ai/api/v1` — only override for self-hosted gateway testing | Setup guide §5 |
| `DEFAULT_EMBEDDING_MODEL` | OpenRouter slug for the embedding model (default `openai/text-embedding-3-small`) | Setup guide §5.4 |
| `DEFAULT_EMBEDDING_DIMS` | Dimensions requested from the embedding endpoint (default `768`, matches `vector(768)` schema) | Setup guide §5.4 |
| `DEFAULT_LLM_MODEL` | OpenRouter slug for the primary chat LLM (default `google/gemini-2.0-flash-001`) | Setup guide §5.4 |
| `DEFAULT_CROSS_VALIDATION_MODEL` | OpenRouter slug for the cross-validation second-pass LLM, deliberately a different family (default `openai/gpt-4o-mini`) | Setup guide §5.4 |
| `SERPAPI_KEY` | SerpAPI key | Setup guide §6.3 |
| `SLACK_BOT_TOKEN` | `xoxb-...` token | Setup guide §7.9 |
| `SLACK_SIGNING_SECRET` | Signing secret | Setup guide §7.5 |
| `SLACK_DEFAULT_CHANNEL_ID` | `#seo-tools-hitl` channel ID | Setup guide §7.12 |
| `TELEGRAM_BOT_TOKEN` | BotFather token | Setup guide §8.5 |
| `TELEGRAM_DEFAULT_CHAT_ID` | Group chat ID (negative number) | Setup guide §8.10 |
| `PYTHON_WORKER_URL` | Railway public URL | Setup guide §9.9 |
| `PYTHON_WORKER_AUTH_TOKEN` | The 32-char token you generated | Setup guide §9.7 |
| `WPGRAPHQL_ENDPOINT` | WordPress GraphQL URL | Setup guide §13.3 |
| `N8N_BASE_URL` | Public cloudflared URL (or `http://localhost:5678` for local-only work) | Setup guide §11 |
| `N8N_API_KEY` | n8n internal API key | Setup guide §10.8 |
| `GOOGLE_CLIENT_ID` | OAuth client ID (Sheets) — optional | Setup guide §12.7 |
| `GOOGLE_CLIENT_SECRET` | OAuth client secret (Sheets) — optional | Setup guide §12.7 |
| `SHEETS_INTERN_VIEW_SPREADSHEET_ID` | Spreadsheet ID — optional | Setup guide §12.8 |

`GOOGLE_REFRESH_TOKEN` is left blank in `.env`. n8n manages it inside its credential store after you complete the OAuth flow.

### A.2 — Goes into n8n credentials only (never in `.env`)

These should be entered through the n8n UI under **Credentials** → **New**. n8n stores them encrypted in its own database. The build agent will reference them by **credential name**, not by value.

| n8n credential name | Type | Purpose |
|---|---|---|
| `Supabase_SEOTools` | Supabase API | DB reads/writes |
| `OpenRouter_SEOTools` | HTTP Header Auth (`Authorization: Bearer ${OPENROUTER_API_KEY}`) | All LLM + embedding calls go through this one credential |
| `SerpAPI_SEOTools` | HTTP Header Auth | SERP lookups (optional Phase 1) |
| `Slack_SEOTools` | Slack OAuth2 | HITL cards |
| `Telegram_SEOTools` | Telegram API | HITL cards (optional) |
| `PythonWorker_SEOTools` | HTTP Header Auth | Worker calls |
| `WPGraphQL_SEOTools` | HTTP Header Auth (only if endpoint has auth) | Page inventory |
| `GoogleSheets_SEOTools` | Google Sheets OAuth2 | Sheet sync (optional Phase 1) |

The build agent does NOT need to see the secret values for the n8n credentials — only confirmation that the credential exists and was tested working.

### A.3 — Non-secret URLs the agent needs in chat

These are safe to paste in the chat message that resumes the build:

- n8n public base URL (the cloudflared one, e.g., `https://n8n-seotools.example.com`)
- Supabase project URL (`https://abcdefghij.supabase.co`)
- Python worker public URL (`https://...up.railway.app`)
- WPGraphQL endpoint URL
- Sheets spreadsheet ID (if Section 12 completed)

These let the agent reference resources for diagnostics without ever seeing tokens.

---

## Part B — Pick a handoff method

### Method 1 (recommended) — Gitignored `.env` file

**Steps for the intern:**

1. In the workspace, copy [`SEO-Tools/.env.example`](../.env.example) to `SEO-Tools/.env`:
   ```powershell
   cd "c:\Users\prana\OneDrive\Documents\Webley Media\WebleyTools\n8n-Scrapper+Builder\n8n_Automation_Builder\SEO-Tools"
   copy .env.example .env
   ```
2. Open `SEO-Tools/.env` and paste every value from Part A.1 next to its key.
3. Save. Confirm `.env` is gitignored:
   ```powershell
   git check-ignore -v SEO-Tools/.env
   ```
   You should see `SEO-Tools/.gitignore:... SEO-Tools/.env`. If not, **STOP** and tell Pranav — the file is at risk of being committed.
4. In Part D below, tick "I used Method 1" and paste the resume prompt into the chat.

**What the agent will do:** read the `.env` file with the Read tool only when it needs a specific value. The agent will never echo secret values back in chat.

**Why it's safe:** the file is on your local disk, ignored by git, and the agent reads it from disk on demand — secrets never travel through chat history.

### Method 2 (most secure, more friction) — Time-limited share link

For organizations with strict secret-handling policies.

**Steps for the intern:**

1. Open Bitwarden (or 1Password). Create a **Secure Note** titled `SEO-Tools Phase 1 handoff`. Paste every Part A.1 value as `KEY=value` lines.
2. Use **Bitwarden Send** (or 1Password's **Item Share**) to generate a link that:
   - Expires in 24 hours OR after 1 view (whichever comes first).
   - Is access-restricted (a passcode you tell Pranav over a different channel).
3. Paste the link in the chat. Paste the passcode in a separate message (or text it to Pranav).
4. The agent will tell you when it has read the values once. After that, you should manually revoke the link (Bitwarden → Sends → Revoke).
5. The agent then writes the values into `SEO-Tools/.env` on your machine itself (using its file-editing tools) so the share link is no longer needed.

**Why it's safer:** the secrets never sit on disk in your project folder until the agent puts them there, and the link auto-expires.

**Why it's more friction:** more moving parts; if the link expires before the agent reads it, you have to regenerate it.

---

## Part C — Fill-in checklist

Tick every box as you complete it. Do not move on if a verify step failed.

### C.1 — Account creation
- [ ] GitHub account created
- [ ] Google account ready (note which one: ________________________)
- [ ] Supabase account created
- [ ] Railway account created
- [ ] Cloudflare account created
- [ ] SerpAPI account created (or noted as skipped for Phase 1)
- [ ] Slack workspace access confirmed (workspace name: ________________________)
- [ ] Telegram account ready (or noted as skipped)

### C.2 — Software installed
- [ ] Docker Desktop installed and running
- [ ] Git installed
- [ ] `cloudflared` installed and on PATH

### C.3 — Supabase
- [ ] Project provisioned (project name: ________________________)
- [ ] Region selected (region: ________________________)
- [ ] Database password saved in password manager
- [ ] URL, project ref, anon key, service role key captured
- [ ] Migrations `0001_initial_schema.sql` through `0004_indexes.sql` applied without errors
- [ ] All four `functions/*.sql` files applied
- [ ] `pgvector` extension verified installed
- [ ] Seed `dummy_clients.sql` applied, `select count(*) from clients` returns 2

### C.4 — OpenRouter
- [ ] API key (`sk-or-v1-...`) created and saved to password manager
- [ ] At least $10 credit added to the account
- [ ] Chat verify curl returned a `choices[0].message.content` containing `ok`
- [ ] Embedding verify curl returned a `data[0].embedding` array of exactly 768 floats
- [ ] Active model slugs chosen and written into `.env`: `DEFAULT_EMBEDDING_MODEL`, `DEFAULT_LLM_MODEL`, `DEFAULT_CROSS_VALIDATION_MODEL` (defaults from `.env.example` are fine for first run)

### C.5 — SerpAPI
- [ ] API key created — or — [ ] Skipped for Phase 1
- [ ] Verify curl returned `search_metadata` (if not skipped)

### C.6 — Slack
- [ ] App "SEO-Tools HITL" created
- [ ] Bot token + signing secret saved
- [ ] Bot scopes added: `chat:write`, `commands`, `channels:read`, `groups:read`, `chat:write.public`
- [ ] Bot installed to workspace
- [ ] `#seo-tools-hitl` channel created and bot invited
- [ ] Channel ID captured
- [ ] Verify post via curl appeared in Slack

### C.7 — Telegram
- [ ] Bot created via BotFather — or — [ ] Skipped
- [ ] Token saved (if not skipped)
- [ ] Group created and bot added (if not skipped)
- [ ] Chat ID captured (if not skipped)
- [ ] Verify sendMessage curl returned `"ok":true` (if not skipped)

### C.8 — Railway / Python worker
- [ ] Repo connected to Railway
- [ ] Root directory set to `SEO-Tools/python-worker`
- [ ] Env vars set: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `WORKER_AUTH_TOKEN`, `LOG_LEVEL`
- [ ] Worker built and deployed successfully
- [ ] Public domain generated and captured
- [ ] `/health` returns `{"ok":true,...}`
- [ ] `/cluster` returns a JSON response (even an empty-clusters one) when called with a valid bearer token

### C.9 — n8n local
- [ ] `docker-compose.yml` created
- [ ] `docker compose up -d` succeeded
- [ ] http://localhost:5678 loads UI
- [ ] Owner account created
- [ ] n8n API key generated and saved

### C.10 — Cloudflare tunnel
- [ ] Quick Tunnel test passed (interim) — or — [ ] Named tunnel set up
- [ ] Tunnel URL captured: ________________________________________
- [ ] n8n's `WEBHOOK_URL` updated to public URL in `docker-compose.yml`
- [ ] n8n container restarted with new env var

### C.11 — Google Sheets / OAuth
- [ ] GCP project created — or — [ ] Skipped for Phase 1
- [ ] Sheets API + Drive API enabled (if not skipped)
- [ ] OAuth consent screen set up (if not skipped)
- [ ] OAuth client created with cloudflared redirect URI (if not skipped)
- [ ] Master spreadsheet created with all expected tabs (if not skipped)
- [ ] Spreadsheet ID captured (if not skipped)

### C.12 — WPGraphQL
- [ ] WPGraphQL plugin confirmed active on WordPress
- [ ] Endpoint URL captured
- [ ] Auth model decided (none / JWT)
- [ ] Verify curl returned valid GraphQL response

### C.13 — Cross-service verification (Section 14 of setup guide)
- [ ] n8n -> Supabase verified
- [ ] n8n -> OpenRouter verified (both chat and embeddings endpoints)
- [ ] n8n -> Python worker verified
- [ ] n8n -> Slack verified
- [ ] Slack -> n8n verified (interactivity URL configured + test POST received)
- [ ] n8n -> Telegram verified (if not skipped)
- [ ] Telegram -> n8n verified (if not skipped)
- [ ] n8n -> WPGraphQL verified
- [ ] n8n -> Google Sheets verified (if not skipped)

### C.14 — Secret placement
- [ ] `.env` file created at `SEO-Tools/.env` and populated (if using Method 1)
- [ ] `.env` confirmed gitignored (`git check-ignore` test passed)
- [ ] n8n credentials created with the names listed in Part A.2 — and the connectivity test passed for each
- [ ] Bitwarden Send link generated (if using Method 2)

### C.15 — Open issues / notes for the agent

If anything is non-standard (e.g., you skipped a section, you chose a different region for Supabase, the WPGraphQL endpoint requires JWT auth, the Slack workspace isn't on Webley Media, etc.), write it here:

```
(Intern: write any deviations or notes here.)



```

---

## Part D — Resume the build

**Ready to resume? Y / N:** ____

If Y, paste this into the Cursor chat with the build agent:

---

```
Handoff complete for SEO-Tools Phase 1 setup.

Method used: [Method 1 — .env file / Method 2 — share link]

Public URLs (safe to paste):
- n8n base URL: https://________________________
- Supabase URL: https://________________________
- Python worker URL: https://________________________
- WPGraphQL endpoint: https://________________________
- Sheets spreadsheet ID (or N/A): ________________________

All verify steps in MANUAL-SETUP-GUIDE.md sections 1-14 passed.
The full filled-in HANDOFF-TEMPLATE.md is committed in SEO-Tools/docs/.
Secrets are in SEO-Tools/.env (gitignored).

Notes / deviations:
[paste C.15 contents here, or "none"]

Please resume Phase 1 build starting with WF-ONBOARD. Read SEO-Tools/.env for any secret you need; do not echo secret values back in chat.
```

---

If N, write here what is blocking you, then ping Pranav:

```
Blockers:




```
