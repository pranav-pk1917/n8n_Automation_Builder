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

## Required Approval Process

Before ANY file deletion, removal, or move operation:
1. **Ask for explicit permission** from the user
2. **Explain what will be deleted/moved** and why
3. **Wait for user confirmation** before proceeding
4. **Provide a backup plan** if the operation needs to be undone

## Safe Alternatives

- **Renaming files**: Always safe, no permission needed
- **Creating new files**: Always safe, no permission needed
- **Modifying file content**: Always safe, no permission needed
- **Restoring files from git**: Always safe, no permission needed

## Exception: User-Initiated Operations

If the user EXPLICITLY instructs to delete, remove, or move files:
- Proceed with the operation
- Document the action in the response
- Provide a summary of what was changed

## Why This Rule Exists

On June 5, 2026, a `git reset --hard` operation accidentally deleted
multiple critical files from the SEO-Tools project, including:
- EXECUTION_PLAN.md (639 lines)
- PROJECT-AUDIT.md (487 lines)
- MANUAL-SETUP-GUIDE.md (70KB+)
- DATABASE-STATE-REPORT.md
- PHASE-C-REPORT.md
- SUPABASE-SETUP-GUIDE.md
- And several other important files

This rule prevents similar accidents by requiring explicit permission
before any destructive file operation.
