# UPDATE_PROTOCOL.md
# n8n Automation Builder — Node & Skills Update Protocol
# Owner: Pranav / Webley Media
# Last Run: 2026-05-28
# Trigger Command: "Execute UPDATE_PROTOCOL and generate a completion report"

---

## WHEN TO RUN THIS PROTOCOL

Run this file when any of the following happen:
- A new n8n version is released
- A workflow fails with "property does not exist" error
- A workflow fails with "unknown operation" error
- A node behaves differently than expected
- Monthly maintenance (first Monday of each month)

---

## PHASE 1 — DISCOVER NEW AND CHANGED NODES

1. Call `get_node_types()` to get the full list of nodes currently 
   installed in the live n8n instance
2. Call `search_nodes({query: "trigger"})` to scan all trigger nodes
3. Call `search_nodes({query: "langchain"})` to check AI node updates
4. Compare results against the Native Node Priority List in .CursorRules
5. List every node that exists in n8n but is missing from the 
   NATIVE NODE MANDATE section in .CursorRules
6. List every node in .CursorRules that no longer appears in 
   get_node_types() output — these may be deprecated

---

## PHASE 2 — CHECK FOR BREAKING CHANGES VIA CONTEXT7

1. Call `fetch_context7_documentation` with query: "n8n changelog"
2. Call `search_context7_documentation` with query: "breaking changes"
3. Call `search_context7_documentation` with query: "deprecated nodes"
4. Call `search_context7_documentation` with query: "new nodes"
5. Note any of the following:
   - Parameter renames on existing nodes
   - Removed operations
   - New operations added to existing nodes
   - Nodes moved from HTTP-only to native node support

---

## PHASE 3 — VALIDATE SKILLS FILES AGAINST LIVE SCHEMAS

For each file in `.cursor/skills/n8n-node-configuration/`:
1. Identify which node the file documents
2. Call `get_node({nodeType, detail: 'standard'})` for that node
3. Compare every parameter mentioned in the skills file against 
   the live schema output
4. Flag parameters in the skills file that no longer exist in 
   the live schema — mark them ⚠️ OUTDATED
5. Flag parameters in the live schema not covered in the skills 
   file — mark them as MISSING DOCUMENTATION

Also check:
- `.cursor/skills/n8n-expression-syntax/COMMON_MISTAKES.md`
  — verify examples still use current syntax
- `.cursor/skills/n8n-code-javascript/DATA_ACCESS.md`
  — verify $input methods are still current
- `.cursor/skills/n8n-workflow-patterns/ai_agent_workflow.md`
  — verify LangChain node names match current node registry

---

## PHASE 4 — UPDATE .CursorRules

Make these updates to .CursorRules:

1. NATIVE NODE MANDATE section:
   - Add any new native nodes discovered in Phase 1
   - Place them under the correct category (Communication, 
     Databases, AI Nodes, etc.)
   - Format: `- Platform → \`n8n-nodes-base.nodeName\``

2. Node registry list (the numbered list of 36+ nodes):
   - Add new nodes with the next available number
   - Mark deprecated nodes with ⚠️ DEPRECATED comment

3. Model reference line at top of file:
   - Ensure it reads exactly:
     `# Model: claude-sonnet-4-6 (Primary) | deepseek-v4-flash (Secondary)`

4. Reference Library Version Warning:
   - Add any newly discovered outdated patterns to the 
     "Known outdated patterns to watch for" list

---

## PHASE 5 — UPDATE SKILLS FILES

1. For any parameter flagged ⚠️ OUTDATED in Phase 3:
   - Open the relevant skills file
   - Update the parameter name to the current correct value
   - Add a comment: `# Updated: [today's date]`

2. For any MISSING DOCUMENTATION flagged in Phase 3:
   - Add the new parameter to the relevant skills file
   - Include: parameter name, type, purpose, example value

3. If new nodes were discovered in Phase 1 with no existing 
   skills file:
   - Create a new file in `.cursor/skills/n8n-node-configuration/`
   - Named: `[node-name]-config.md`
   - Include: node type string, available operations, 
     required parameters, credential type

---

## PHASE 6 — UPDATE MCP_REGISTRY.md

1. Open Cursor Settings > MCP
2. Check current status of every MCP in the list
3. Update MCP_REGISTRY.md to reflect current state:
   - Any new MCPs added → add entry with WORKING status
   - Any MCPs now erroring → update status to ERRORED
   - Any MCPs removed → move to Removed MCPs section
4. Update the Last Updated date at the bottom of MCP_REGISTRY.md

---

## PHASE 7 — SYNC MASTER_RULES.md

1. Open MASTER_RULES.md
2. Check if any of these sections changed in Phase 4:
   - NATIVE NODE MANDATE
   - PRE-DEPLOY VALIDATION checklist
   - Reference Library Version Warning
3. If yes — copy the updated sections into MASTER_RULES.md
4. Update the sync date in the Sync Status table for Cursor
5. Add a note: "Synced by UPDATE_PROTOCOL run on [today's date]"

---

## PHASE 8 — COMMIT AND PUSH ALL CHANGES

Run these commands:
git add .CursorRules
git add .cursor/skills/
git add MCP_REGISTRY.md
git add MASTER_RULES.md
git add UPDATE_PROTOCOL.md
git commit -m "Maintenance: node and skills update [today's date]"
git push origin master

Also update the Last Run date at the top of this file 
to today's date before committing.

---

## PHASE 9 — COMPLETION REPORT

Output a summary with exactly these fields:

- **Date of run:**
- **n8n version checked:**
- **New nodes discovered:**
- **Nodes deprecated or removed:**
- **Skills files updated:**
- **Parameters renamed or fixed:**
- **New parameters documented:**
- **MCP status changes:**
- **MASTER_RULES.md synced:** Yes / No
- **Git committed and pushed:** Yes / No
- **Issues requiring manual attention:**

---

## USAGE

To run this protocol, open Cursor in Agent mode and type:
Execute UPDATE_PROTOCOL and generate a completion report