# SEO-Tools Git Repository (Cursor rule)

**SCOPE: This rule applies ONLY to the `SEO-Tools/` project folder and does NOT affect other projects in the root workspace.**

## Git Remote Configuration

The `SEO-Tools/` project has its own dedicated GitHub repository. When working inside this directory, the git remote MUST be:

- **Repository URL:** `https://github.com/pranav-pk1917/SEO-Tools.git`
- **Remote name:** `origin`
- **Branch:** `master`

## Rules

1. **Always verify remote before pushing**: Before any `git push` command executed within the `SEO-Tools/` directory, verify that the remote URL points to `https://github.com/pranav-pk1917/SEO-Tools.git`.

2. **Never push SEO-Tools content to other repositories**: The `SEO-Tools/` folder content must NEVER be pushed to:
   - `n8n_Automation_Builder` repo
   - Any other repository
   - Any personal/backup repository

3. **If remote is misconfigured**: If the remote URL is not pointing to the correct SEO-Tools repository, automatically fix it by running:
   ```bash
   git remote set-url origin https://github.com/pranav-pk1917/SEO-Tools.git
   ```

4. **This rule is project-scoped**: This rule applies ONLY to operations within the `SEO-Tools/` directory. Other projects in the root workspace (e.g., `n8n_Automation_Builder`, `SEO-Titan-n8n-workflow`, etc.) are NOT affected by this rule and should maintain their own git remote configurations.

5. **Verification command**: To verify the current remote configuration, run:
   ```bash
   git -C SEO-Tools remote -v
   ```
   The output should show:
   ```
   origin	https://github.com/pranav-pk1917/SEO-Tools.git (fetch)
   origin	https://github.com/pranav-pk1917/SEO-Tools.git (push)
   ```

## Why This Rule Exists

On June 5, 2026, SEO-Tools content was accidentally pushed to the wrong repository (`n8n_Automation_Builder`) instead of the dedicated `SEO-Tools` repository. This rule prevents that mistake from recurring by enforcing the correct remote configuration whenever git operations are performed within the `SEO-Tools/` directory.

## Enforcement

- **Before any git push**: Check remote URL matches the SEO-Tools repository
- **Before any git commit**: Warn if remote is misconfigured
- **Auto-fix**: If misconfigured, automatically update remote before proceeding
