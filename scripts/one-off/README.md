# One-off scripts

Scripts that run once (or rarely) for migrations, bootstraps, and bulk operations. Not part of the recurring pipeline.

## Conventions

- One file per task. Name with intent: `migrate_legacy_data.py`, `bootstrap_gold_examples.py`, `recompute_all_priority_scores.py`.
- Idempotent where possible. Re-running should not corrupt state.
- Top-of-file docstring states: what it does, what data it touches, whether it's destructive, how to dry-run.
- Always have a `--dry-run` flag.

## Pending one-offs

- `migrate_legacy_data.py` — see `scripts/powershell-legacy/README.md` "Data migration plan".
- `bootstrap_competitor_brand_ner.py` — runs `competitor-brand-ner` prompt over the legacy keyword sample to seed `competitor_brand_names` for Webley.
- `bootstrap_gold_examples.py` — for a freshly onboarded client, generate 5-10 initial gold positive + 5-10 initial gold negative examples using the client config + an LLM call, then insert into `gold_examples`.
- `recompute_priority_scores.py` — wrapper around the Postgres `refresh_priority_scores(pipeline_run_id)` function for a given client / date range. Useful after the priority formula is tuned.

These will be added as the pipeline goes into operation.
