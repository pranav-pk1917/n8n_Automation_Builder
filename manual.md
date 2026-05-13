This is your enhanced, hierarchical **Standard Operating Procedure (SOP)**. I have used Markdown formatting to visually separate sections and emphasize critical actions.

Save this file as `TITAN_MANUAL.md` in the root of your `n8n_Automation_Builder` folder.

---

# 📘 Titan Automation Builder: Operating Manual

**Version:** 2.0 (Titan V2)
**Owner:** Webley Media / Pranav
**System:** Cursor AI + n8n + Local Knowledge Base

---

## 1. System Overview (What is this?)

The **Titan Builder** is not just an AI chat. It is a "Cybernetic Factory" that builds n8n automation workflows. It combines four critical components:

* 🧠 **The Brain:** `.cursor/skills/` (Textbooks on n8n syntax and nodes).
* 📚 **The Memory:** `Reference_Library/` (7,000+ real-world examples).
* ⚖️ **The Rules:** `.cursorrules` (The engineering standards enforcement).
* 🤖 **The Builder:** Cursor "Composer" (The AI Agent).

---

## 2. The Map: Where is everything?

*Do not move or delete files unless you are the System Admin.*

| Folder / File | Description | When to use it? |
| --- | --- | --- |
| **`.cursor/skills/`** | The "Textbooks." Contains guides on JS, Python, and Expression Syntax. | **Never touch manually.** The AI reads this automatically to ensure code accuracy. |
| **`Reference_Library/`** | The "Vault." Contains 7k+ JSON files organized by category. | Use `@Reference_Library` to search for similar workflows to copy. |
| **`Staging_Area/`** | (Optional) Folder to save new JSONs before deploying. | When you want to save a file locally instead of pushing to n8n directly. |
| **`.cursorrules`** | The "Constitution." | Defines how the AI behaves. **Read-only** for the team. |

---

## 3. The "GSD" Build Process (Standard Workflow)

**🔴 Standard Rule:** Never ask the AI to "just write code." Always follow the **Plan -> Search -> Build** loop.

### Phase 1: Context & Search (The Setup)

Open Cursor **Composer** (`Ctrl+I` or `Cmd+I`) and set it to **Agent Mode**.

**📋 Prompt Template:**

> "I need to build a **[Name of Workflow]**.
> 1. **Goal:** [Describe what it does, e.g., Scrape Google Maps and save to Airtable].
> 2. **Search:** Scan `@Reference_Library/Organized_Workflows_Multi` for patterns related to **[Keywords]**.
> 3. **Consult:** Check `.cursor/skills` for any specific node limitations."
> 
> 

### Phase 2: Architecture (The Plan)

The AI will return a plan. Review it:

* *Check:* Does it include an **Error Trigger**?
* *Check:* Are the steps logical?
* *Action:* If it looks good, say: **"Proceed to build."**

### Phase 3: Construction (The Code)

The AI will generate the JSON code.

**📋 Prompt Template:**

> "Generate the JSON.
> **Engineering Standards:**
> 1. Use descriptive node names (e.g., `Webhook_Inbound`).
> 2. Include a Sticky Note wrapping the main logic.
> 3. Add an Error Trigger connected to a Slack notification node.
> 4. Deploy directly to n8n using the MCP tool."
> 
> 

---

## 4. Cheat Sheet: What to Reference & When

| If you are building... | Reference this folder (`@Foldername`) | Specific Instruction |
| --- | --- | --- |
| **Web Scrapers** | `@Reference_Library/.../Scrapers` | "Look for 'Puppeteer' or 'HTML Extract' patterns." |
| **Sales / CRM** | `@Reference_Library/.../CRM` | "Look for 'Pipedrive' or 'HubSpot' deduplication logic." |
| **Custom JavaScript** | `.cursor/skills/n8n-code-javascript` | "Use the `DATA_ACCESS.md` guide to ensure `$input.first()` is used correctly." |
| **Slack/Discord Bots** | `@Reference_Library/.../Social` | "Check how we handle 'Interactive Buttons' in previous bots." |
| **Complex Math/Logic** | `.cursor/skills/n8n-expression-syntax` | "Ensure you use the correct syntax for accessing JSON body data." |

---

## 5. Beginner's Bootcamp: Your First Day

*For new team members who have never used Cursor or n8n.*

### Step 1: Open the Factory

1. Open **Cursor**.
2. Go to `File > Open Folder` and select `n8n_Automation_Builder`.
3. **Wait 2 minutes.** Look at the bottom/top right. If you see "Indexing...", wait for it to finish. This is the AI reading the library.

### Step 2: The Interface

You will mostly use **Composer**.

* **Shortcut:** Press `Ctrl + I` (Windows) or `Cmd + I` (Mac).
* This opens a floating chat window. This is your "Command Center."
* **Agent Mode:** Ensure the toggle says "Agent" (not "Normal"). This allows the AI to search files and run tools.

### Step 3: Your First Build (The "Hello World")

Let's build a simple tool: **"A Text Summarizer."**

**Copy/Paste this into Composer:**

> "I want to build a simple workflow for a complete beginner.
> **Goal:** Receive text via a Webhook, use an AI Agent to summarize it, and return the summary.
> **Context:** Search `@Reference_Library` for 'OpenAI' or 'Summarize'.
> **Build:** Create the JSON with descriptive names and a Sticky Note explaining how it works."

### Step 4: The Deployment

1. The AI will generate code.
2. It might ask: *"Do you want me to save this or push it to n8n?"*
3. Type: **"Push it to n8n."**
4. Open your browser to `http://localhost:5678`. Refresh the page.
5. You will see your new workflow named "Text_Summarizer_v1".

### Step 5: Fixing Errors (The "Self-Healing" Trick)

If you try to execute the workflow in n8n and it turns red (fails):

1. Copy the error message from n8n (e.g., *"Problem in node 'Summarize': API Key missing"*).
2. Go back to Cursor Composer.
3. Paste the error and say: **"Fix this."**
4. The AI will analyze the error, rewrite the JSON, and update it.

---

## 6. Pro Tips for the Team

**💡 The "Example" Trick**
If you want the AI to copy a *specific* style of automation you saw online:

* Download that automation JSON to the `Inbox` folder.
* Tell Cursor: *"Build a variation of the workflow found in `@Inbox/example_workflow.json` but change the destination to Google Sheets."*

**🔍 Handling "Hallucinations"**
If the AI invents a parameter that doesn't exist (e.g., trying to use "GPT-5" in a node that doesn't support it):

* **Command:** *"Stop. Check `.cursor/skills/n8n-node-configuration`. Does the OpenAI node support this parameter? Correct yourself."*

**💾 Saving Your Wins**
When you build a *perfect* workflow:

1. Export it from n8n.
2. Save it to `Reference_Library/Organized_Workflows_Multi/Automation/`.
3. Now the AI remembers it for next time!

---

## 7. Troubleshooting

| Issue | Solution |
| --- | --- |
| **"I can't find that file."** | Check your spelling. Use the `@` symbol to trigger the file picker dropdown to ensure the AI sees it. |
| **"The code is broken."** | Ask the AI: *"Did you check the `.cursor/skills` files for syntax?"* usually it forgot to check the textbook. |
| **AI is writing slow/lazy code.** | Type: **"Execute GSD Protocol."** This forces it to re-read the `.cursorrules` and be rigorous. |