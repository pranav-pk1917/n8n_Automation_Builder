# SEO-Tools Phase 1 — Handoff to Build Agent

Use this document to hand control back to the Cursor build agent so it can start constructing the n8n workflows (beginning with WF-ONBOARD).

---

## Handoff methods

**Method A — Paste directly into Cursor chat (recommended)**
Copy the resume prompt at the bottom of this file and paste it into the Cursor chat window. The agent will read it and resume.

**Method B — Reference this file in chat**
In the Cursor chat, type `@SEO-Tools/docs/HANDOFF-TEMPLATE.md` so the agent reads the file directly.

Either method works. Method A is faster if you are already in a chat session.

---

## Connectivity status (Section 14 results)

| Connection | Credential name in n8n | Status |
|---|---|---|
| n8n → Supabase | `Supabase_SEOTools` | PASS |
| n8n → OpenRouter | `OpenRouter_SEOTools` | PASS |
| n8n → Python worker (`/health`) | `PythonWorker_SEOTools` | PASS |
| n8n → Python worker (`/cluster`) | `PythonWorker_SEOTools` | PENDING — Railway env var fix needed (see Section 9) |
| n8n → Slack | `Slack_SEOTools` | PASS |
| Slack → n8n (inbound webhook) | *(no credential)* | PASS |
| n8n → Telegram | `Telegram_SEOTools` | PASS |
| Telegram → n8n (Trigger node) | `Telegram_SEOTools` | PASS |
| n8n → WPGraphQL | *(no credential, no auth)* | PASS |
| n8n → Google Sheets | `GoogleSheets_SEOTools` | SKIPPED — optional, not needed for Phase 1 |
| n8n → SerpAPI | `SerpAPI_SEOTools` | PASS |

---

## Service endpoints and keys

### n8n instance (Elestio)
- **URL:** `https://n8n-webley-u35816.vm.elestio.app`

### Supabase
- **Project URL:** `https://qpfjpjshpnndimoayiwb.supabase.co`
- **service_role key:** `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFwZmpwanNocG5uZGltb2F5aXdiIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3ODc0NDgyNSwiZXhwIjoyMDk0MzIwODI1fQ.1RTqb0WSh2hzHKqrhW8RTKGBsIxRnFIBzNIo9c1ay6A`

### OpenRouter
- **API base URL:** `https://openrouter.ai/api/v1`
- **Auth header name:** `Authorization`
- **Auth header value:** `Bearer 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`
- **LLM model:** `google/gemini-2.0-flash-001`
- **Embeddings model:** `openai/text-embedding-3-small` (768 dimensions)

### Python worker (Railway)
- **Base URL:** `https://seo-tools-production-c347.up.railway.app`
- **Health endpoint:** `https://seo-tools-production-c347.up.railway.app/health`
- **Cluster endpoint:** `https://seo-tools-production-c347.up.railway.app/cluster` *(broken — see note below)*
- **Auth header name:** `Authorization`
- **Auth header value:** `Bearer skayblDKeN3wULj1MimzZfCI69OvpunH`
- **Note:** `/cluster` returns HTTP 500 because `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are not reaching the Railway service process. Fix: Railway → service → Variables tab → add both variables directly to the service (not as Shared Variables) → redeploy.

### Slack
- **Bot User OAuth Token:** `xoxb-11122421376323-11134110887429-nhwtxduxAESuSwFCFzhC9m6e`
- **Channel:** `#seo-tools-hitl`
- **Channel ID:** `C0B43A7QG5P`
- **Interactivity Request URL (set in Slack app settings):** `https://n8n-webley-u35816.vm.elestio.app/webhook/hitl-decision-slack`

### Telegram
- **Bot token:** `8616386423:AAHhENvweAI4Qc88vg92Dp09i0kauKopbac`
- **Bot username:** `@webley_seotools_hitl_bot`
- **SEO-Tools HITL group chat ID:** `-4993060055`

### WPGraphQL (WordPress CMS)
- **GraphQL endpoint:** `https://cms.webleymedia.com/graphql`
- **Authentication:** None (publicly readable)

### SerpAPI
- **API key:** `c68aa5b90d549f985c2f394a14628116f5465202fe13b1dbc34ea76de5564c2c`

### Google Sheets
- **Status:** Optional — not configured. Skip for Phase 1.

---

## Outstanding issues to resolve before or during build

1. **Python worker `/cluster` endpoint** — Railway env vars not reaching the service. Must be fixed before WF-03 (the clustering workflow) can run. Fix is documented in Section 9 of MANUAL-SETUP-GUIDE.md.
2. **Google Sheets** — Skipped (optional). Not required for Phase 1 core workflows (WF-ONBOARD, WF-02, WF-03, WF-04).

---

## Ready to resume build

- [x] All mandatory Section 14 connectivity tests passed (or failures are documented above with known fixes)
- [x] All credential names in n8n match the names listed in the connectivity table above
- [x] Outstanding issues are documented and do not block WF-ONBOARD construction

---

## Resume prompt

Copy everything between the dashed lines below and paste it into the Cursor build agent chat:

---

```
I have completed the manual infrastructure setup for SEO-Tools Phase 1 
(Sections 1–14 of MANUAL-SETUP-GUIDE.md). All connectivity tests passed 
except the Python worker /cluster endpoint (known Railway env-var issue — 
fix documented in Section 9, does not block WF-ONBOARD).

The full handoff details — credential names, endpoints, keys, and 
outstanding issues — are in:
  @SEO-Tools/docs/HANDOFF-TEMPLATE.md

Please:
1. Read HANDOFF-TEMPLATE.md to confirm all credentials and endpoints.
2. Validate that the credential names in n8n match what the workflows will expect.
3. Begin building WF-ONBOARD as the first workflow in Phase 1.
4. If anything is misconfigured, tell me exactly which connectivity test to re-run.
```

---
