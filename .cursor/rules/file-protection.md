# File Protection Rule (Cursor rule)

**SCOPE: This rule applies to ALL projects and files in the workspace.**

## Strict Rules

1. **NEVER delete files** without explicit user permission
2. **NEVER remove files** without explicit user permission
3. **NEVER move files** to different locations without explicit user permission
4. **NEVER use destructive operations** like:
   - `git reset --hard` (unless explicitly approved)
   - `git clean -fd` (unless explicitly approved)
   - `rm -rf` (unless explicitly approved)
   - `Remove-Item -Recurse -Force` (unless explicitly approved)
   - `git rm -r --cached` (unless explicitly approved)
   - `git push --force` / `git push -f` (unless explicitly approved)
   - `git checkout -- <file>` to discard changes (unless explicitly approved)

## Required Approval Process

Before ANY file deletion, removal, or move operation:
1. **Ask for explicit permission** from the user
2. **Explain what will be deleted/moved** and why
3. **Wait for user confirmation** before proceeding
4. **Provide a backup plan** if the operation needs to be undone
5. **Create a backup first** if possible (e.g., `cp file file.bak` or `git add . && git commit`)

## Safe Alternatives

- **Renaming files**: Always safe, no permission needed
- **Creating new files**: Always safe, no permission needed
- **Modifying file content**: Always safe, no permission needed
- **Restoring files from git**: Always safe, no permission needed
- **Creating backups**: Always safe and RECOMMENDED before any risky operation

## Exception: User-Initiated Operations

If the user EXPLICITLY instructs to delete, remove, or move files:
- Proceed with the operation
- Document the action in the response
- Provide a summary of what was changed

## Recovery Procedures

If files are accidentally deleted or lost:
1. **Check git reflog**: `git reflog` to find lost commits
2. **Use `git fsck`**: `git fsck --lost-found` to find dangling objects
3. **Restore from git**: `git checkout <commit> -- <path>` to restore files
4. **Ask user for permission** before any recovery operation

## Multi-Repository Protection

When working with multiple git repositories (subprojects):
1. **ALWAYS verify the current directory** before running git commands
2. **ALWAYS verify the remote URL** before pushing
3. **NEVER assume which repo you're in** — check with `git remote -v` and `pwd`
4. **When in doubt, ASK** which repo should receive the changes

## Why This Rule Exists

### Incident 1: June 5, 2026 - SEO-Tools File Deletion
A `git reset --hard` operation accidentally deleted multiple critical files from the SEO-Tools project, including:
- EXECUTION_PLAN.md (639 lines)
- PROJECT-AUDIT.md (487 lines)
- MANUAL-SETUP-GUIDE.md (70KB+)
- DATABASE-STATE-REPORT.md
- PHASE-C-REPORT.md
- SUPABASE-SETUP-GUIDE.md
- And several other important files

### Incident 2: June 6, 2026 - n8n_Automation_Builder Mass Deletion
When SEO-Tools was added as a subdirectory, 314 files were deleted from the n8n_Automation_Builder root directory. This required a complete restoration from commit 7efd032.

### Incident 3: June 6, 2026 - Wrong Repository Push
SEO-Tools content was accidentally pushed to the wrong GitHub repository (`n8n_Automation_Builder` instead of `SEO-Tools`). This required:
- Resetting the wrong repo
- Re-pushing to the correct repo
- Re-syncing the local repos

### Incident 4: June 6, 2026 - Lost Local Changes
After a `git reset --hard origin/master` on the root repo, the SEO-Tools subdirectory was wiped (including its `.git` folder), requiring a re-clone from GitHub.

**These rules prevent similar accidents by requiring explicit permission before any destructive file operation.**

## Enforcement

These rules are **MANDATORY** and apply to:
- All file operations in the workspace
- All git operations
- All filesystem operations
- All Cursor AI agent actions
- All automated scripts and commands

**If you are uncertain whether an operation is destructive, ASK FIRST. It is always better to ask than to cause data loss.**
