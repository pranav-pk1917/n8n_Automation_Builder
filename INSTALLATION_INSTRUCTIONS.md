# Installation Instructions for n8n Automation Builder

This guide explains how to set up the complete n8n Automation Builder environment on a new computer.

---

## Prerequisites

### Required Software

| Tool | Version | Purpose |
|------|---------|---------|
| **Git** | 2.0+ | Version control and cloning repositories |
| **Cursor IDE** | Latest | AI-powered code editor with MCP support |
| **Python** | 3.9+ | For code-review-graph MCP server |
| **Node.js** | 18+ | For n8n and Node-based tools (optional) |
| **gh CLI** | Latest | GitHub CLI for repository management |

### Optional Tools

| Tool | Purpose |
|------|---------|
| **uv** | Fast Python package manager (for code-review-graph) |
| **n8n** | Self-hosted automation platform (if not using cloud) |

---

## Installation Steps

### Step 1: Install Cursor IDE

1. Download Cursor from [cursor.sh](https://cursor.sh)
2. Install and sign in with your account
3. Enable MCP support in Settings

### Step 2: Install Git and GitHub CLI

```bash
# Install GitHub CLI (Windows)
winget install GitHub.cli

# Verify installation
gh auth status
```

### Step 3: Install Python (for code-review-graph)

```bash
# Windows: Download from python.org or use winget
winget install Python.Python.3.11

# Verify
python --version
```

### Step 4: Clone the Main Repository

```bash
# Navigate to your preferred location
cd C:/Projects

# Clone main project
git clone https://github.com/pranav-pk1917/n8n_Automation_Builder.git

# Enter project directory
cd n8n_Automation_Builder
```

### Step 5: Clone the Reference Library

```bash
# This contains 7000+ n8n workflow examples
git clone https://github.com/pranav-pk1917/n8n_Automation_Builder_ReferenceLibrary.git Reference_Library
```

### Step 6: Install code-review-graph (Optional but Recommended)

```bash
# Navigate to code-review-graph directory
cd code-review-graph

# Install Python dependencies
pip install -e .

# Verify installation
python -m code_review_graph --help
```

### Step 7: Configure MCP Servers in Cursor

Open Cursor Settings > MCP and configure:

| Server | Command | Purpose |
|--------|---------|---------|
| code-review-graph | `python -m code_review_graph mcp` | Code analysis |
| n8n-mcp | (via Cursor marketplace) | n8n workflow management |
| context7 Docs | (via Cursor marketplace) | Latest n8n documentation |

### Step 8: Verify Installation

```bash
# Test code-review-graph
python -m code_review_graph mcp --help

# Open project in Cursor
cursor .
```

---

## Project Structure Reference

This is the exact folder structure that should be replicated:

```
n8n_Automation_Builder/                    # Project root
├── .cursor/                              # Cursor configuration
│   ├── mcp.json                         # MCP server config
│   └── skills/                          # n8n skills (36 files)
│       ├── n8n-code-javascript/         # JS Code node guide
│       ├── n8n-code-python/             # Python Code node guide
│       ├── n8n-expression-syntax/       # Expression syntax guide
│       ├── n8n-mcp-tools-expert/       # MCP tools usage guide
│       ├── n8n-node-configuration/     # Node config patterns
│       ├── n8n-validation-expert/       # Validation guide
│       └── n8n-workflow-patterns/      # Workflow architectures
├── .claude/                             # Claude agent config
├── .gemini/                             # Gemini agent config
├── .qoder/                              # Qoder config
├── code-review-graph/                   # Code review tools
│   ├── .mcp.json                       # MCP config for this tool
│   ├── code_review_graph/               # Python source code
│   ├── skills/                          # Review skills
│   └── docs/                            # Documentation
├── Staging_Area/                        # Ready-to-deploy workflows
│   ├── compy_datascrape_receiver.json   # Firecrawl webhook receiver
│   ├── compy_datascrape_dispatcher.json # Job dispatcher
│   ├── scrape_jobs_table.sql            # Database schema
│   └── SETUP_GUIDE.md                   # Deployment guide
├── Reference_Library/                    # 7000+ n8n workflow examples
│   └── n8n_workflows_scraped/           # Organized by category
│       └── #AllCombined/                # All workflows combined
├── MCP_REGISTRY.md                      # MCP server documentation
├── .CursorRules                         # AI behavior rules (Titan Protocol)
├── AGENTS.md                            # Agent configuration
├── manual.md                            # Full operating manual
├── .gitignore                           # Git ignore patterns
└── .mcp.json                            # Project-level MCP config
```

---

## Configuration Files Explained

### .CursorRules (Titan Protocol)

Defines how the AI agent should behave when building workflows:
- Phase-based workflow (Interrogation -> Strategy -> Blueprint -> Execution)
- GSD (Get Stuff Done) rules
- Engineering standards enforcement
- No hallucinations - must reference skills files

### .mcp.json

Project-level MCP server configuration:

```json
{
  "mcpServers": {
    "code-review-graph": {
      "command": "python",
      "args": ["-m", "code_review_graph", "mcp"]
    }
  }
}
```

### MCP_REGISTRY.md

Documents all MCP servers, their status, and how to configure them.

---

## Troubleshooting

### Git "Filename too long" error

Windows has a 260 character path limit. Solutions:

1. **Use Git Bash** instead of PowerShell
2. **Clone to shorter path**: `C:/n8n_builder`
3. **Enable long paths**: `git config --global core.longpaths true`

### MCP servers not working

1. Check Cursor Settings > MCP
2. Verify Python is in PATH
3. Restart Cursor IDE

### Reference_Library not found

Ensure you cloned it with:
```bash
git clone https://github.com/pranav-pk1917/n8n_Automation_Builder_ReferenceLibrary.git Reference_Library
```

---

## For Interns

### First Time Setup (30 minutes)

1. Install prerequisites (Git, Cursor, Python)
2. Clone main project
3. Clone reference library
4. Open in Cursor
5. Configure MCP servers via Settings
6. Run `code-review-graph build` to index code

### Daily Workflow

1. Open project in Cursor: `cursor .`
2. Use Agent mode (Ctrl+I) for workflow building
3. Reference `.cursor/skills/` for syntax help
4. Search `Reference_Library/` for similar workflows

---

## Support

- **Issues**: Create GitHub issue in the main repository
- **Documentation**: See `manual.md` for full operating guide
- **MCP Status**: See `MCP_REGISTRY.md` for server configuration