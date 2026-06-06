# Subprojects

This repository (`n8n_Automation_Builder`) contains multiple subprojects. Each subproject exists as both a subdirectory in this root repository AND as an independent GitHub repository for isolation and focused development.

## Subproject List

### 1. SEO-Tools
- **Subdirectory:** `./SEO-Tools/`
- **GitHub Repository:** https://github.com/pranav-pk1917/SEO-Tools
- **Status:** Active and synced
- **Purpose:** SEO/GEO keyword research and content automation platform
- **Phase:** Phase 1 (Keyword Cleaning + Clustering Pipeline)

### 2. SEO-Titan-n8n-workflow
- **Subdirectory:** `./SEO-Titan-n8n-workflow/`
- **GitHub Repository:** (Not yet created - needs setup)
- **Status:** Subdirectory exists but not yet pushed to own repo
- **Purpose:** Titan n8n workflow templates and examples

## Why Dual Structure?

Each subproject exists as both a subdirectory AND an independent repo for these reasons:

1. **Isolation:** Each project can be developed, versioned, and deployed independently
2. **Focused Development:** Subproject repos have clean histories without root-level noise
3. **Easier Collaboration:** Team members can work on subprojects without cloning the entire root
4. **Deployment Flexibility:** Subprojects can be deployed independently
5. **Cleaner Permissions:** Subproject repos can have different access controls

## Git Workflow for Subprojects

### Working in SEO-Tools/
```bash
# Navigate to subproject
cd SEO-Tools

# Work on files normally
# ...

# Commit and push to SEO-Tools repo
git add .
git commit -m "Your changes"
git push origin master
```

### Working in SEO-Titan-n8n-workflow/
```bash
# Navigate to subproject
cd SEO-Titan-n8n-workflow

# Work on files normally
# ...

# Commit and push to SEO-Titan-n8n-workflow repo
git add .
git commit -m "Your changes"
git push origin master
```

### Working in Root (n8n_Automation_Builder)
```bash
# Work on root-level files
# ...

# Commit and push to root repo
git add .
git commit -m "Your changes"
git push origin master
```

## Synchronization Strategy

**Important:** Changes made in a subproject should be committed and pushed to BOTH:
1. The subproject's own GitHub repository (primary)
2. The root repository (as a sync, if subdirectory is tracked)

**Current Setup:**
- SEO-Tools: Subdirectory is tracked in root repo AND has its own repo
- SEO-Titan-n8n-workflow: Subdirectory exists but not tracked in root repo

## When to Commit Where

| Change Location | Commit To |
|----------------|-----------|
| Files in `SEO-Tools/` | SEO-Tools repo (primary), then root repo (sync) |
| Files in `SEO-Titan-n8n-workflow/` | SEO-Titan-n8n-workflow repo (when created) |
| Root-level files (`.CursorRules`, `MASTER_RULES.md`, etc.) | Root repo only |
| `.cursor/skills/` files | Root repo only |
| `code-review-graph/` files | Root repo only |
| `Staging_Area/` files | Root repo only |

## Setting Up a New Subproject

To add a new subproject with its own GitHub repo:

1. Create the subdirectory in the root
2. Create a new GitHub repository for the subproject
3. Initialize git in the subdirectory: `cd subproject && git init`
4. Add the remote: `git remote add origin https://github.com/pranav-pk1917/subproject-name.git`
5. Create `.gitignore` for the subproject
6. Make initial commit and push
7. Update this SUBPROJECTS.md file
8. Decide whether to track the subdirectory in root repo or exclude via `.gitignore`

## Notes

- Each subproject maintains its own git history
- The root repository acts as a meta-repository containing all subprojects
- This structure allows for both integrated development (in root) and independent development (in subprojects)
