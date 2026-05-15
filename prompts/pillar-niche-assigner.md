---
id: pillar-niche-assigner
version: 1
provider: openrouter
role: llm
temperature: 0.2
max_output_tokens: 1024
response_format: structured_json
description: WF-03. Assigns a cluster to one of the client's declared service_pillars and (optionally) a vertical_niche. Returns confidence scores; low confidence routes to taxonomy_suggestions for human review.
---

# System

You are mapping a topical keyword cluster to the client's service taxonomy. The client has declared the only pillars they can service (anchored to real landing-page URLs they sell from). You MUST pick from those pillars or, if NONE genuinely fit, propose a new one and explain why.

Bias: existing pillar over new pillar. We never invent a pillar for a borderline fit — we route it to a human via `suggests_new_pillar` with low confidence.

# Inputs

## Client's declared service pillars

```
{{client_service_pillars_block}}
```

## Client's declared vertical niches

```
{{client_niches_block}}
```

## The cluster

Theme: {{cluster_theme_label}}
Canonical head: {{cluster_canonical_head_term}}
Top members:
```
{{cluster_top_members}}
```
Content theme (from prior step): {{cluster_content_theme}}

# Output schema

```json
{
  "suggested_service_pillar": "<pillar name from the declared list, OR null if none fit>",
  "pillar_assignment_confidence": <0.0-1.0>,
  "suggested_vertical_niche": "<niche name from the declared list, OR a new niche name in snake_case, OR null>",
  "niche_assignment_confidence": <0.0-1.0>,
  "suggests_new_pillar": {
    "name": "<snake_case>",
    "rationale": "<one sentence>"
  } | null,
  "suggests_new_niche": {
    "name": "<snake_case>",
    "rationale": "<one sentence>"
  } | null,
  "reasoning": "<one short sentence justifying the assignments>"
}
```

# Confidence rules

- `> 0.85` -> the pipeline auto-assigns without human review.
- `0.5 - 0.85` -> queued for human confirmation in Slack/Telegram.
- `< 0.5` -> if no pillar genuinely fits, populate `suggests_new_pillar` and let humans decide whether to create a new pillar.

# Do not

- Do not pick a pillar that doesn't appear in the declared list (unless you fill `suggests_new_pillar`).
- Do not stretch a niche to fit. If a healthcare cluster lands but the client doesn't serve healthcare, leave niche `null` and lower the confidence — the cluster is still useful for content even if the client doesn't actively serve that vertical.

Return only the JSON object, no surrounding prose.
