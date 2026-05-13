# MCP Server Registry

## Overview
This document tracks all MCP (Model Context Protocol) servers configured for the Titan Automation Builder project.

---

## MCP Server Status

| Server | Status | Type | Tools | Authentication |
|--------|--------|------|-------|----------------|
| `code-review-graph` | WORKING | Local | 30+ | None |
| `cursor-ide-browser` | WORKING | Local | 33+ | None |
| `user-firecrawl-mcp` | WORKING | Local | 16 | None |
| `user-code-review-graph` | WORKING | Local | 30+ | None |
| `plugin-figma-figma` | AUTH_REQUIRED | Remote | Yes | Needs `mcp_auth` |
| `plugin-vercel-vercel` | AUTH_REQUIRED | Remote | Yes | Needs `mcp_auth` |
| `user-n8n-mcp` | ERRORED | Remote | Missing | Needs reinstall |
| `user-context7_Docs` | ERRORED | Remote | Missing | Needs reinstall |
| `user-google-sheets` | ERRORED | Remote | Missing | Needs reinstall |

---

## Working MCPs

### code-review-graph
- **Config:** `.code-review-graph/.mcp.json`
- **Command:** `python -m code_review_graph mcp`
- **Purpose:** Persistent incremental knowledge graph for token-efficient, context-aware code reviews
- **Tools:** semantic_search_nodes, query_graph, detect_changes, get_impact_radius, get_affected_flows, refactor_tool, etc.

### cursor-ide-browser
- **Config:** `cursor-ide-browser/INSTRUCTIONS.md`
- **Purpose:** Web navigation and page interaction for frontend/webapp development
- **Critical Workflow:** `browser_navigate` -> `browser_lock` -> (interactions) -> `browser_unlock`

### user-firecrawl-mcp
- **Tools:** firecrawl_crawl, firecrawl_scrape, firecrawl_map, firecrawl_search, firecrawl_browser_* (browser automation)
- **Purpose:** Web scraping and crawling with Firecrawl API

### user-code-review-graph
- **Purpose:** Code review with knowledge graph (duplicate of code-review-graph at workspace level)

---

## Authentication Required

### plugin-figma-figma
- **Status:** Needs authentication via `mcp_auth` tool
- **Action:** Call `mcp_auth` with `{}`

### plugin-vercel-vercel
- **Status:** Needs authentication via `mcp_auth` tool
- **Action:** Call `mcp_auth` with `{}`

---

## Broken MCPs (Need Reinstall via Cursor Settings)

### user-n8n-mcp
- **Purpose:** Build and manage n8n workflows via MCP tools
- **Issue:** Missing tools folder - only has `SERVER_METADATA.json` and `STATUS.md`
- **Fix:** Remove and re-add through Cursor Settings > MCP

### user-context7_Docs
- **Purpose:** Fetch latest n8n documentation via Context 7
- **Issue:** Missing tools folder
- **Fix:** Remove and re-add through Cursor Settings > MCP

### user-google-sheets
- **Purpose:** Google Sheets integration
- **Issue:** Missing tools folder
- **Fix:** Remove and re-add through Cursor Settings > MCP

---

## Installation Instructions

### For Broken MCPs (Cursor-Managed)

1. Open Cursor Settings (Cmd/Ctrl + ,)
2. Navigate to: **MCP** or **Extensions** > **MCP Servers**
3. Find the broken server (n8n-mcp, context7 Docs, google-sheets)
4. Click **Remove** or **Uninstall**
5. Re-add by searching for the MCP in the MCP marketplace or providing the package name
6. Restart Cursor

### For Authentication Required MCPs

Use the `mcp_auth` tool (requires Cursor AI with MCP access):

```javascript
CallMcpTool({
  server: "plugin-figma-figma",
  toolName: "mcp_auth",
  arguments: {}
})
```

---

## MCP Configuration File Location

Project-level MCP config: `.code-review-graph/.mcp.json`

This file uses the standard MCP JSON format:
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

## Last Updated

**Date:** 2026-05-11
**Status Check:** Manual inspection of `mcps/` folder