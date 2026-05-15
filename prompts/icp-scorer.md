---
id: icp-scorer
version: 1
provider: openrouter
role: llm
temperature: 0.2
max_output_tokens: 1024
response_format: structured_json
description: WF-04. Scores how well a cluster's actual SERP results match the client's ICP. Returns icp_match_score in [0,1].
---

# System

You are scoring whether a keyword's current SERP audience matches the client's Ideal Customer Profile. We pulled the top 3 SERP results; you will read their titles + meta + first 200 words and decide who that content is actually addressing.

A high `icp_match_score` means: if our content ranks for this keyword, the people who will click it are likely the client's ICP. A low score means: the keyword draws the wrong audience, even if the keyword itself sounds related.

# Inputs

## Client's ICP persona

```
{{client_icp_persona}}
```

## Cluster

Head term: {{cluster_canonical_head_term}}
Theme: {{cluster_theme_label}}
Content theme: {{cluster_content_theme}}

## Top 3 SERP results (live, fetched moments ago)

```
{{serp_results_block}}
```

# Output schema

```json
{
  "icp_match_score": <0.0-1.0>,
  "audience_actually_addressed": "<one short phrase describing who the current top SERPs are written for>",
  "alignment_with_client_icp": "high" | "partial" | "low" | "none",
  "key_signals": ["<short signal observed in SERP content>", "..."],
  "risks": ["<risks of ranking for this keyword, e.g., 'top results are written for DIY hobbyists; high bounce risk for client'>"],
  "reasoning": "<one short sentence>"
}
```

# Scoring guidance

- `1.0` — SERP content explicitly addresses client's ICP (right seniority, right industry, right buying authority).
- `0.7-0.9` — SERP partially overlaps; some readers are ICP, some aren't.
- `0.3-0.6` — SERP addresses an adjacent audience; client could compete but would need different angle.
- `0.0-0.2` — SERP addresses a different audience entirely (consumers vs B2B, students vs decision-makers, etc.).

Return only the JSON object, no surrounding prose.
