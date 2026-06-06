# MASTER_RULES.md — Cross-Environment Rule Sync Source

**Date Created:** 2026-05-28
**Last Updated:** 2026-05-28
**Owner:** Pranav / Webley Media
**Purpose:** Single source of truth for core engineering rules that must be consistent across all AI coding environments.

---

## Sync Status

| Environment | Config Location | Last Synced | Status |
|---|---|---|---|
| Cursor | `.cursor/` + `.CursorRules` | 2026-05-28 | Source of truth (synced by UPDATE_PROTOCOL) |
| Claude | `.claude/settings.json` | 2026-05-29 | Synced |
| Gemini | `.gemini/settings.json` | 2026-05-29 | Synced |
| Qoder | `.qoder/settings.json` | 2026-05-29 | Synced |

---

## NATIVE NODE MANDATE

> ⚠️ **CRITICAL — THIS OVERRIDES ALL REFERENCE LIBRARY PATTERNS** ⚠️

### Why This Rule Exists

The Reference_Library contains workflows built before native nodes existed for many platforms. Those old workflows use HTTP Request nodes for authentication and API calls. DO NOT copy that pattern. It creates fragile, hard-to-maintain workflows when better options exist.

### The Primary Rule

Before using `n8n-nodes-base.httpRequest` for ANY platform integration, ALWAYS check if a native node exists first:

```
search_nodes({query: "platform_name"})
```

If a native node exists → **USE IT. No exceptions.**

HTTP Request nodes are ONLY acceptable for:
- Platforms with no native n8n node at all
- Custom internal APIs your company built
- Specific endpoints the native node does not cover

### Native Node Priority List

NEVER use HTTP Request for these platforms — native nodes exist:

**Communication**
- Slack → `n8n-nodes-base.slack`
- Discord → `n8n-nodes-base.discord`
- Telegram → `n8n-nodes-base.telegram`
- WhatsApp → `n8n-nodes-base.whatsapp`
- Twilio (SMS) → `n8n-nodes-base.twilio`
- SendGrid → `n8n-nodes-base.sendGrid`
- Gmail → `n8n-nodes-base.gmail`
- Microsoft Outlook → `n8n-nodes-base.microsoftOutlook`

**Productivity & Docs**
- Notion → `n8n-nodes-base.notion`
- Google Sheets → `n8n-nodes-base.googleSheets`
- Google Drive → `n8n-nodes-base.googleDrive`
- Google Docs → `n8n-nodes-base.googleDocs`
- Airtable → `n8n-nodes-base.airtable`

**CRM & Sales**
- HubSpot → `n8n-nodes-base.hubspot`
- Salesforce → `n8n-nodes-base.salesforce`
- Pipedrive → `n8n-nodes-base.pipedrive`

**Project Management**
- Asana → `n8n-nodes-base.asana`
- Trello → `n8n-nodes-base.trello`
- Jira → `n8n-nodes-base.jira`
- Linear → `n8n-nodes-base.linear`
- Monday.com → `n8n-nodes-base.mondayCom`

**Databases**
- Postgres → `n8n-nodes-base.postgres`
- MySQL → `n8n-nodes-base.mySql`
- MongoDB → `n8n-nodes-base.mongoDb`
- Supabase → `n8n-nodes-base.supabase`
- Redis → `n8n-nodes-base.redis`

**Developer Tools**
- GitHub → `n8n-nodes-base.github`
- GitLab → `n8n-nodes-base.gitlab`

**E-Commerce & Payments**
- Shopify → `n8n-nodes-base.shopify`
- Stripe → `n8n-nodes-base.stripe`
- WooCommerce → `n8n-nodes-base.wooCommerce`

**Cloud & Storage**
- AWS S3 → `n8n-nodes-base.awsS3`
- AWS SES → `n8n-nodes-base.awsSes`
- Dropbox → `n8n-nodes-base.dropbox`

**AI Nodes (LangChain — use these, NOT legacy openAi node)**
- OpenAI Chat → `@n8n/n8n-nodes-langchain.lmChatOpenAi`
- Anthropic Claude → `@n8n/n8n-nodes-langchain.lmChatAnthropic`
- AI Agent → `@n8n/n8n-nodes-langchain.agent`
- HTTP Tool (for AI agents) → `@n8n/n8n-nodes-langchain.toolHttpRequest`
- Memory (window) → `@n8n/n8n-nodes-langchain.memoryBufferWindow`
- Structured Output Parser → `@n8n/n8n-nodes-langchain.outputParserStructured`
- OpenAI Embeddings → `@n8n/n8n-nodes-langchain.embeddingsOpenAi`
- Google Gemini → `@n8n/n8n-nodes-langchain.googleGemini`
- MiniMax → `@n8n/n8n-nodes-langchain.minimax`
- Moonshot Kimi → `@n8n/n8n-nodes-langchain.moonshot`

### Authentication Rule

When a native node exists, ALWAYS use its built-in credential system. NEVER manually construct Authorization headers or API keys in HTTP nodes for platforms that have native credential types in n8n. The native credential system is more secure, easier to rotate, and does not expose tokens in the workflow JSON.

---

## NEVER TRUST DEFAULTS

Default parameter values are the #1 source of runtime failures. ALWAYS explicitly configure ALL parameters that control node behavior.

**Example - FAILS at runtime:**
```json
{resource: "message", operation: "post", text: "Hello"}
```

**Example - WORKS - all parameters explicit:**
```json
{resource: "message", operation: "post", select: "channel", channelId: "C123", text: "Hello"}
```

**Validation Strategy:**
1. **Level 1 - Quick Check:** `validate_node({nodeType, config, mode: 'minimal'})` - Required fields only (<100ms)
2. **Level 2 - Comprehensive:** `validate_node({nodeType, config, mode: 'full', profile: 'runtime'})` - Full validation with fixes
3. **Level 3 - Complete:** `validate_workflow(workflow)` - Connections, expressions, AI tools
4. **Level 4 - Post-Deployment:** `n8n_validate_workflow({id})` - Validate deployed workflow

---

## Phase 3.1: PRE-DEPLOY VALIDATION (MANDATORY — DO NOT SKIP)

Before calling `n8n_create_workflow` or `n8n_push_workflow`, run this checklist. STOP and fix any item that is missing before proceeding.

### Checklist

Run through each item and confirm it is present in the workflow JSON:

**□ Error Handling**
- [ ] An `n8n-nodes-base.errorTrigger` node is present
- [ ] The error trigger connects to a notification (Slack, email, or similar)
- [ ] At least one Try/Catch pattern exists for external API calls

**□ Security**
- [ ] Zero hardcoded API keys, tokens, or passwords in any node
- [ ] All credentials use n8n's credential system (referenced as `{{ $credentials.xxx }}`)
- [ ] No sensitive data appears in Sticky Notes or node names

**□ Code Quality**
- [ ] All node names are descriptive (REJECT: "HTTP Request 1", "Set 3", "Code")
- [ ] ACCEPT examples: "Fetch_Customer_From_HubSpot", "Parse_Webhook_Payload"
- [ ] At least one Sticky Note explains what the workflow does

**□ Native Node Compliance**
- [ ] No HTTP Request nodes where a native node exists (check Native Node Mandate)
- [ ] All AI nodes use LangChain prefix, not legacy `n8n-nodes-base.openAi`

**□ Connections**
- [ ] All nodes are connected — no orphaned nodes
- [ ] No node has an output that goes nowhere

**If any item above is unchecked:** Fix it first, then re-run this checklist. Only call `n8n_create_workflow` when ALL items are checked.

---

### Handling Validation Errors

When validation fails, do NOT proceed with deployment. Instead:

1. **Read the error carefully** — validation errors are specific about what's wrong
2. **Fix the issue in the workflow JSON** — don't try to work around it
3. **Re-validate** — run validation again after every fix
4. **Common validation errors and fixes:**
   - `Missing required field` → Add the field to the node's parameters
   - `Invalid expression syntax` → Check `$json.xxx` vs `$input.xxx` usage
   - `Credential not found` → Ensure credential is referenced by ID, not hardcoded
   - `Node not connected` → Connect orphaned nodes or remove them

**Never deploy a workflow with validation errors.** Fix first, deploy second.

---

### Distinguishing Validation False Positives

Some validation warnings are not real errors. Before "fixing" a warning, check if it's a false positive:

**Common false positives (safe to ignore):**
- Warnings about optional fields being empty when the field truly is optional
- Style warnings (e.g., node naming conventions) when your naming is intentional
- Warnings about unused credentials when credentials are conditionally used

**Real errors that MUST be fixed:**
- Missing required fields
- Invalid expression syntax
- Disconnected nodes
- Hardcoded secrets

**When in doubt:** Consult `.cursor/skills/n8n-validation-expert/FALSE_POSITIVES.md` for the current catalog of known false positives. This file is actively maintained and updated as new false positives are discovered.

---

## Reference Library Version Warning

> ⚠️ **CRITICAL**

The workflows in Reference_Library were scraped at various points in time. Some may be from n8n versions before 1.0. Node parameter names and structures have changed significantly across versions.

**RULE: Never copy node parameters from Reference_Library verbatim.**

Instead:
1. Use Reference_Library for **PATTERN INSPIRATION only** (workflow structure, logic flow)
2. Always validate the actual parameters using: `get_node({nodeType, detail: 'standard'})`
3. If a parameter from the reference library doesn't appear in `get_node()` output, it no longer exists — do not use it

**Known outdated patterns to watch for:**
- `values.string` → now `assignments` in Set nodes
- `functionCode` → now `jsCode` in Code nodes
- `operation: "send"` in email nodes → check current operation names
- Any `n8n-nodes-base.openAi` node → replace with LangChain equivalent
- n8n 2.0: `Start` node removed → use Manual Trigger or Execute Workflow Trigger
- n8n 2.0: `MySQL`/`MariaDB` storage removed → PostgreSQL only
- n8n 2.0: `Spontit`, `crowd.dev`, `Kitemaker`, `Automizy` nodes removed (services retired)
- n8n 2.0: `ExecuteCommand` and `LocalFileTrigger` disabled by default (security)
- n8n 2.0: Python Code node `python` parameter → now `pythonNative` (native task runner replaces Pyodide)
- n8n 2.0: Environment variables blocked in code/expressions by default
- New standalone vendor nodes: `@n8n/n8n-nodes-langchain.anthropic`, `@n8n/n8n-nodes-langchain.googleGemini`, `@n8n/n8n-nodes-langchain.minimax`, `@n8n/n8n-nodes-langchain.moonshot`
- New Tool variants for AI agents: `slackTool`, `gmailTool`, `notionTool`, `hubspotTool`, `postgresTool`, `githubTool`

**Structure:** `Reference_Library/n8n_workflows_scraped/<Category>`

---

## Phase 5: POST-DEPLOY LEARNING (Run after successful workflow execution)

After a workflow has been successfully deployed and tested in n8n:

1. **Analyze what worked:** Document any novel solutions, parameter combinations, or error handling patterns that emerged during development.

2. **Extract reusable patterns:** If you solved a problem in a way that could benefit future workflows, note it down with:
   - The specific problem you solved
   - The solution you implemented
   - Why it worked (the underlying principle)
   - Any gotchas or edge cases discovered

3. **Update knowledge base:** Add any new insights to:
   - The appropriate `.cursor/skills/` file if it's a reusable pattern
   - The `MASTER_RULES.md` file if it's a cross-environment rule
   - The Reference_Library if it's a complete workflow pattern worth preserving

4. **Flag deprecated patterns:** If you discovered that a Reference_Library workflow used an outdated approach, document:
   - What the old pattern was
   - What the new pattern should be
   - The n8n version where the change occurred (if known)

5. **Improve validation rules:** If validation caught an error that saved you time, ensure that validation rule is documented. If validation missed something important, add a new validation check.

**This phase should take 5-10 minutes and happens AFTER the workflow is confirmed working.**

---

## Reasoning Behavior & Epistemic Standards

> ⚠️ **NOT YET PRESENT** — This section does not currently exist in `.CursorRules` and needs to be authored.

TODO: Define standards for:
- Epistemic humility (what to do when uncertain)
- Reasoning transparency (show work vs. skip)
- When to ask for clarification vs. proceed with assumptions
- Confidence thresholds for autonomous decisions

---

## SYNC INSTRUCTIONS

### When to Update This File

Update `MASTER_RULES.md` any time:
- A core rule in `.CursorRules` changes (new section, modified logic, deprecated rule)
- A new cross-environment rule is added that should apply to Claude, Gemini, and Qoder
- A rule is removed or significantly rewritten in any environment

### How to Sync to Other Environments

1. Open the target environment's config file:
   - **Claude:** `.claude/settings.json` (or a dedicated rules file if one exists)
   - **Gemini:** `.gemini/settings.json` (or a dedicated rules file if one exists)
   - **Qoder:** `.qoder/settings.json` (or a dedicated rules file if one exists)
   - **Cursor:** `.CursorRules` (this is the source of truth — edit it first, then sync here)

2. Copy the relevant section(s) from this file into the target config.

3. Update the **Last Synced** date in the Sync Status table at the top of this file for the environment you just updated.

4. If you added the sync timestamp line (`# Last synced from MASTER_RULES.md: YYYY-MM-DD`) to the target config file, update that date as well.

### Sync Timestamp Convention

Each environment config file should begin with this line (as a comment, so it does not break JSON parsing the line is tracked separately or kept in a companion `.md` file):

```
# Last synced from MASTER_RULES.md: YYYY-MM-DD
```

> **Note:** Since `.claude/settings.json`, `.gemini/settings.json`, and `.qoder/settings.json` are JSON files, the sync timestamp line is best placed in a companion markdown file within each directory (e.g., `.claude/SYNC.md`) or tracked solely in the table above. The sync timestamp comment has been added to each `settings.json` as a `//` JS-style comment at the top — valid in JSONC (JSON with Comments) which Cursor supports.
