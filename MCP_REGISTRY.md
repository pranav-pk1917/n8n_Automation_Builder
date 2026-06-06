# MCP Server Registry

## Overview
This document tracks all MCP (Model Context Protocol) servers 
configured for the n8n_automation_builder project.

---

## MCP Server Status

| Server | Status | Type | Tools | Authentication |
|--------|--------|------|-------|----------------|
| `code-review-graph` | WORKING | Local | 30 | None |
| `context7 Docs` | WORKING | Remote | 4 | Logged in |
| `n8n-mcpServer` | WORKING | Remote | 27 | Logged in |
| `airtable` | WORKING | Remote | 16 | Logged in |
| `supabase` | WORKING | Remote | 20 | Logged in |
| `google-sheets` | ERRORED | Remote | — | Skipped for now |
| `railway-mcp-server` | ERRORED | Remote | — | Investigate |
| `@21st-dev/magic` | DISABLED | Remote | — | Not in use |

---

## Working MCPs

### code-review-graph
- **Type:** Local
- **Config:** `.code-review-graph/.mcp.json`
- **Command:** `python -m code_review_graph mcp`
- **Purpose:** Persistent incremental knowledge graph for 
  token-efficient, context-aware code reviews
- **Tools:** semantic_search_nodes, query_graph, detect_changes,
  get_impact_radius, get_affected_flows, refactor_tool, 
  get_architecture_overview, list_communities, refactor_tool

### context7 Docs
- **Type:** Remote (Cursor-managed)
- **Purpose:** Real-time n8n and general documentation lookup
- **Tools:** fetch_context7_documentation, 
  search_context7_documentation, search_context7_code,
  fetch_generic_url_content
- **Usage:** Use FIRST before Reference_Library for any 
  documentation question

### n8n-mcpServer
- **Type:** Remote (Cursor-managed)
- **Purpose:** Build and manage n8n workflows directly from Cursor
- **Tools (27):** search_nodes, get_node_types, get_suggested_nodes,
  validate_workflow, create_workflow_from_code, update_workflow,
  archive_workflow, get_sdk_reference, search_workflows,
  execute_workflow, get_execution, search_executions,
  get_workflow_details, publish_workflow, unpublish_workflow,
  prepare_test_pin_data, test_workflow, list_credentials,
  search_data_tables, create_data_table, rename_data_table,
  add_data_table_column, delete_data_table_column,
  rename_data_table_column, add_data_table_rows,
  search_projects, search_folders

### airtable
- **Type:** Remote (Cursor-managed)
- **Purpose:** Airtable database read/write operations
- **Tools:** 16 tools enabled

### supabase
- **Type:** Remote (Cursor-managed)
- **Purpose:** Supabase database and auth operations
- **Tools:** 20 tools enabled

---

## Errored MCPs

### google-sheets
- **Status:** Errored
- **Decision:** Skipped intentionally — not needed in current workflow
- **Fix when needed:** Remove and re-add through Cursor Settings > MCP

### railway-mcp-server
- **Status:** Errored
- **Action required:** Either fix authentication or remove if not in use
- **Fix:** Go to Cursor Settings > MCP > railway-mcp-server > 
  click Show Output to see the error, then either fix or remove

---

## Disabled MCPs

### @21st-dev/magic
- **Status:** Disabled intentionally
- **Re-enable:** Toggle on in Cursor Settings > MCP if needed

---

## Removed MCPs (Previously Existed)

### user-code-review-graph
- **Reason removed:** Duplicate of code-review-graph — was causing
  unpredictable tool routing
- **Removed:** 2026-05-28

### user-context7_Docs
- **Reason removed:** Replaced by context7 Docs (reinstalled clean)
- **Removed:** 2026-05-28

### user-n8n-mcp
- **Reason removed:** Replaced by n8n-mcpServer (reinstalled clean)
- **Removed:** 2026-05-28

### cursor-ide-browser
- **Reason removed:** No longer in active use
- **Removed:** 2026-05-28 (remove this line if it still exists)

### user-firecrawl-mcp
- **Note:** Check if this still exists in Cursor Settings.
  If yes, keep this entry as WORKING. If gone, this entry 
  documents its removal.

### plugin-figma-figma
- **Note:** Was AUTH_REQUIRED — check if still installed.
  If yes, authenticate via mcp_auth tool.

### plugin-vercel-vercel
- **Note:** Was AUTH_REQUIRED — check if still installed.
  If yes, authenticate via mcp_auth tool.

---

## MCP Configuration File Location

Project-level MCP config: `.code-review-graph/.mcp.json`

```json
{
  "mcpServers": {
    "server-name": {
      "command": "executable",
      "args": ["arg1", "arg2"]
    }
  }
}
```

---

## Railway MCP — Action Required

Your `railway-mcp-server` is showing an error. To investigate:

1. Go to Cursor Settings > MCP
2. Find `railway-mcp-server`
3. Click **Show Output** next to it
4. Read the error message
5. If you don't use Railway in your projects → click Remove
6. If you do use Railway → fix the authentication

---

## Last Updated

**Date:** 2026-05-28
**Status Check:** Cross-referenced with Cursor Settings and MCP tool descriptors
**Updated by:** UPDATE_PROTOCOL run on 2026-05-28