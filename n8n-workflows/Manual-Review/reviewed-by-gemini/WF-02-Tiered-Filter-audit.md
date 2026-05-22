# Audit: WF-02-Tiered-Filter

## 1. Current Logic Assessment
*Briefly define what the workflow currently does and its overall health.*
This workflow applies a multi-tier filter to unclassified keywords: regex negatives, competitor checks, embedding similarity (against gold examples), and an LLM classifier for borderline cases. Human-in-the-loop (HITL) Slack cards are dispatched for reviews. The health is poor due to a broken batching loop and multiple webhook response errors.

## 2. Identified Shortcomings & Doubts
*List any unclear logic, potential failure points, or scalability bottlenecks.*
- [ ] Issue 1: **Broken SplitInBatches Loop:** `Batch_For_Embedding` splits keywords into batches of 100, but the execution chain ends at `Respond_Filter` and never loops back. Only the first 100 keywords are processed.
- [ ] Issue 2: **Multiple Webhook Responses:** `Respond_Filter` is placed at the end of the item-level loop. It will attempt to respond to the webhook once per borderline keyword, causing errors.
- [ ] Issue 3: **Hardcoded 50k Limit:** `Fetch_Unclassified_Keywords` uses a hardcoded `Range: 0-49999` header.
- [ ] Issue 4: **Sequential LLM Calls:** `LLM_Tier2_Classify` processes borderline keywords sequentially, which is slow.

## 3. Scope for Improvement
*Explain how the efficiency and scalability can be boosted without over-engineering.*
The workflow must be restructured to process all keywords by fixing the batch loop. The webhook response must be moved to the beginning to prevent timeouts and multiple-response errors, allowing the heavy embedding and LLM classification to run asynchronously in the background.

## 4. Execution Plan (For Next Agent)
*Provide step-by-step, actionable instructions on exactly which nodes to change, add, or remove.*
1. **Respond Early:** Move `Respond_Filter` to immediately follow `Validate_Filter_Payload` to acknowledge the webhook instantly.
2. **Fix the Batch Loop:** Re-route the end of the processing chain (after `IF_Needs_HITL` and `Send_HITL_Card`) back to the input of `Batch_For_Embedding` (or use a Loop node).
3. **Handle 50k Limit:** Implement pagination for `Fetch_Unclassified_Keywords` or increase the range if the database supports it.
4. **Aggregate Before Completion:** Add a mechanism to detect when the `Batch_For_Embedding` loop is `done`, and only then execute any final pipeline run completion steps (if they exist).

---
*Written by model - [Gemini 3.1 Pro Reasoning]*