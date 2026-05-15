# Prompts

All LLM prompts used by the pipeline live here as version-controlled markdown.

## Why prompts as files

- **Diff-able prompt changes** in PR review.
- **`llm_prompt_hash`** in `keyword_classifications` is computed from the rendered prompt text — so prompt edits are detectable in production.
- **Easy A/B testing**: a prompt can have multiple variants (`tier2-classifier.v2.md`) and the pipeline can route a % of traffic through each.
- **Decoupled from n8n**: prompts can be edited without touching workflow JSON.

## Prompt frontmatter

Every prompt file starts with a YAML frontmatter block:

```yaml
---
id: tier2-classifier
version: 1
provider: openrouter
role: llm
temperature: 0.2
max_output_tokens: 4096
response_format: structured_json
description: Tier 2 classification — decides intent + niche + theme + LSI status.
---
```

Followed by the prompt body. Placeholders use `{{double_braces}}` and are filled in by n8n before the LLM call.

## Dynamic model selection (role -> env var)

Prompts never name a concrete model. Instead they declare a **role**, and n8n resolves the role to a concrete OpenRouter model slug at run time by reading the corresponding env var. To swap a model, edit `.env` and restart n8n. Nothing else changes.

| `role` value in frontmatter | Resolved from env var | Default slug (May 2026) |
|---|---|---|
| `llm` | `DEFAULT_LLM_MODEL` | `google/gemini-2.0-flash-001` |
| `cross_validation` | `DEFAULT_CROSS_VALIDATION_MODEL` | `openai/gpt-4o-mini` |
| `embedding` | `DEFAULT_EMBEDDING_MODEL` + `DEFAULT_EMBEDDING_DIMS` | `openai/text-embedding-3-small` @ 768 dim |

`embedding` is only used by code paths that call the `/embeddings` endpoint directly (the embedder n8n nodes); it does not appear in any prompt frontmatter, because prompt files describe chat-completion calls only.

See [docs/adr/0005-openrouter-unified-gateway.md](../docs/adr/0005-openrouter-unified-gateway.md) for the rationale and the operational impact of swapping each model.

## Computing `llm_prompt_hash`

```
sha256(rendered_prompt_text || "::" || resolved_model_slug || "::" || temperature)
```

n8n computes this before each LLM call (after resolving `role` -> concrete model slug) and stores it in `keyword_classifications.llm_prompt_hash`.

When you edit a prompt OR swap the underlying model via `DEFAULT_*_MODEL` env vars, the hash changes -> quality audits track the rollout of the new prompt / new model + can detect agreement-rate shifts attributable to the change.

## Files

- `tier2-classifier.md` — Tier 2 batch classification (intent + niche + theme + LSI status + confidence).
- `onboarding-site-analyzer.md` — WF-ONBOARD step 2: extract proposed pillars + ICP signals from crawled site content.
- `onboarding-questionnaire-validator.md` — WF-ONBOARD step 4: cross-validate questionnaire answers against site crawl.
- `cluster-theme-labeler.md` — WF-03: produce theme_label + content_theme for each cluster.
- `pillar-niche-assigner.md` — WF-03: suggest service_pillar + vertical_niche per cluster with confidence.
- `icp-scorer.md` — WF-04: score a cluster's SERP results against the client's ICP persona.
- `cross-validation-reclassifier.md` — Bidirectional verification: AI second-pass when a human overrides an AI decision.
- `competitor-brand-ner.md` — One-shot NER to extract competitor brand names from raw_keywords + site crawl.
