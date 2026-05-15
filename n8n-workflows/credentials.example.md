# n8n credentials required

When importing the workflows, you must create / connect the following credentials in your n8n instance. Names below are the conventional names — match them exactly so workflow JSONs import cleanly without re-binding.

| Credential name | Type | Used by | Required env |
|---|---|---|---|
| `Supabase_SEOTools` | Supabase API | WF-01 / 02 / 03 / 04 / 05 / ONBOARD / HITL-DISPATCHER / QUALITY-AUDIT / CROSS-VALIDATION / COST-CEILING-GUARD | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` |
| `OpenRouter_SEOTools` | HTTP Header Auth | WF-02 / 03 / 04 / ONBOARD / CROSS-VALIDATION — both chat AND embedding endpoints | `OPENROUTER_API_KEY`, `OPENROUTER_BASE_URL`, `DEFAULT_EMBEDDING_MODEL`, `DEFAULT_EMBEDDING_DIMS`, `DEFAULT_LLM_MODEL`, `DEFAULT_CROSS_VALIDATION_MODEL` |
| `SerpAPI_SEOTools` | HTTP (header auth) | WF-04 | `SERPAPI_KEY` |
| `Slack_SEOTools` | Slack OAuth2 / Bot Token | WF-HITL-DISPATCHER, WF-QUALITY-AUDIT, WF-COST-CEILING-GUARD | `SLACK_BOT_TOKEN`, `SLACK_SIGNING_SECRET` |
| `Telegram_SEOTools` | Telegram Bot API | WF-HITL-DISPATCHER, WF-QUALITY-AUDIT, WF-COST-CEILING-GUARD | `TELEGRAM_BOT_TOKEN` |
| `PythonWorker_SEOTools` | HTTP (bearer token) | WF-03 | `PYTHON_WORKER_URL`, `PYTHON_WORKER_AUTH_TOKEN` |
| `WPGraphQL_SEOTools` | HTTP (header auth) | WF-00 | `WPGRAPHQL_ENDPOINT`, `WPGRAPHQL_AUTH_HEADER` |
| `GoogleSheets_SEOTools` | Google Sheets OAuth2 | WF-05 | `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REFRESH_TOKEN` |

## Credential setup steps

### Supabase

1. **Settings -> API** in your Supabase project.
2. Copy the `service_role` key (NOT the anon key) and the project URL.
3. In n8n: **Credentials -> New -> Supabase API**. Name it `Supabase_SEOTools`. Paste URL + service role key.
4. The service role key bypasses RLS — appropriate for n8n which orchestrates everything. Restrict the n8n instance's network exposure accordingly.

### OpenRouter

1. Follow Section 5 of [`docs/MANUAL-SETUP-GUIDE.md`](../docs/MANUAL-SETUP-GUIDE.md) to create the API key at https://openrouter.ai/keys.
2. In n8n: **Credentials -> New -> HTTP Header Auth**. Name `OpenRouter_SEOTools`.
   - **Header name:** `Authorization`
   - **Value:** `Bearer sk-or-v1-...` (paste the actual key after `Bearer `)
3. (Optional, recommended) Also configure two query / header pass-through fields for OpenRouter's app analytics:
   - `HTTP-Referer` = value of `OPENROUTER_HTTP_REFERER` env var (e.g. `https://webleymedia.com`)
   - `X-Title` = value of `OPENROUTER_APP_TITLE` env var (e.g. `SEO-Tools`)
   These are not required for auth; they just attribute usage in the OpenRouter dashboard.
4. All workflows hit `${OPENROUTER_BASE_URL}/chat/completions` (chat / classifier / theme / NER / ICP / cross-validation) or `${OPENROUTER_BASE_URL}/embeddings` (Tier 1 embedding + gold examples + page embeddings). The `model` field of each request is resolved at run time from the env vars (`DEFAULT_LLM_MODEL`, `DEFAULT_CROSS_VALIDATION_MODEL`, `DEFAULT_EMBEDDING_MODEL`) according to the prompt's `role` — see [`prompts/README.md`](../prompts/README.md).
5. To swap a model, edit the relevant `DEFAULT_*_MODEL` line in `.env`, restart n8n. No credential change needed; the credential only holds the API key.

### SerpAPI

1. Sign up at https://serpapi.com/.
2. Copy your API key.
3. In n8n: **Credentials -> New -> HTTP Query Auth**. Name `SerpAPI_SEOTools`. Query parameter name `api_key`, value = your key.

### Slack

1. Create a Slack app at https://api.slack.com/apps.
2. Scopes needed: `chat:write`, `commands`, `incoming-webhook`.
3. Install to your workspace; copy the Bot User OAuth Token and Signing Secret.
4. In n8n: **Credentials -> New -> Slack OAuth2 API**. Name `Slack_SEOTools`.
5. Set up an interactive endpoint pointing to `<n8n>/webhook/hitl-decision-slack`.

### Telegram

1. Create a bot via @BotFather. Copy the token.
2. In n8n: **Credentials -> New -> Telegram API**. Name `Telegram_SEOTools`.
3. Set webhook to `<n8n>/webhook/hitl-decision-telegram`.

### Python worker

1. Deploy per `python-worker/README.md`.
2. Generate a random `WORKER_AUTH_TOKEN`.
3. In n8n: **Credentials -> New -> HTTP Header Auth**. Name `PythonWorker_SEOTools`. Header `Authorization`, value `Bearer <token>`.

### WPGraphQL

1. From the Webley headless WordPress, enable the WPGraphQL plugin (already installed).
2. If WPGraphQL JWT or similar auth is enabled, generate a token; otherwise use unauthenticated queries.
3. In n8n: **Credentials -> New -> HTTP Header Auth**. Name `WPGraphQL_SEOTools`.

### Google Sheets

1. Create OAuth2 credentials in Google Cloud Console; enable the Sheets API.
2. In n8n: **Credentials -> New -> Google Sheets OAuth2 API**. Name `GoogleSheets_SEOTools`.
3. Complete the OAuth handshake.
4. Pre-create a Google Sheet named `SEO-Tools — <client slug>` per client; record the spreadsheet ID in `clients.config.sheets_view_id`.

## Multi-tenant credential isolation (future)

In Phase 1 all clients share these credentials (Webley's keys for all API providers). When Phase 2 / SaaS-ification arrives, per-client credentials live in a `credentials_vault` table; the n8n workflow looks up the client's credentials by `client_id` before each API call. See ROADMAP.md "Per-client API key vault (BYOK)".
