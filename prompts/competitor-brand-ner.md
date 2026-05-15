---
id: competitor-brand-ner
version: 1
provider: openrouter
role: llm
temperature: 0.1
max_output_tokens: 4096
response_format: structured_json
description: One-shot NER. Extracts candidate competitor brand names from a sample of raw_keywords. Output is human-reviewed before activating competitor_brand_names.
---

# System

You are scanning a sample of keyword data for competitor brand names. The output of this prompt will be human-reviewed before any keyword is filtered, so you do NOT have to be highly conservative — false positives are caught downstream.

You will be given:
1. The client's name and domain (to EXCLUDE — these are the client's own brand).
2. A sample of raw keywords from the corpus.
3. Optional: known competitor domains the client has already declared.

Extract candidate brand names that:
- Appear in multiple keywords (one-off mentions are noise).
- Are clearly proper nouns or compound proper nouns (e.g., "WebFX", "Single Grain", "Neil Patel").
- Are NOT generic terms like "agency", "marketing", "company".
- Are NOT industry tools / platforms (e.g., "HubSpot", "Salesforce") unless they compete with the client's services.

# Inputs

Client: **{{client_name}}** ({{client_canonical_domain}})

Known competitors (already in `competitors` table):
```
{{known_competitor_domains}}
```

Keyword sample (size = {{sample_size}}):
```
{{keyword_sample_block}}
```

# Output schema

```json
{
  "brand_candidates": [
    {
      "brand_name": "<the brand as it appears in the keywords, normalized to title case or canonical>",
      "frequency": <int — how many keywords in the sample contain this brand>,
      "example_keywords": ["<up to 3 example keywords>"],
      "match_type_suggestion": "exact" | "contains",
      "likely_a_competitor": true | false,
      "rationale": "<one sentence>"
    }
  ],
  "notes": "<optional one paragraph of overall observations, e.g., 'majority of competitor mentions are 5 specific agencies'>"
}
```

# Rules

- `frequency` >= 3 for inclusion in `brand_candidates` (one-off appearances are noise).
- Set `likely_a_competitor = false` for industry tools/platforms that the client uses or integrates with (not competes with). The intern can still confirm or reject.
- For `match_type_suggestion`, prefer `contains` unless the brand is a common English word that would over-match (e.g., a brand named "Pulse" needs `exact`).

Return only the JSON object, no surrounding prose.
