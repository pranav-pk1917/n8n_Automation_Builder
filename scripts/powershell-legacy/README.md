# Legacy PowerShell scripts

Original PowerShell + VBA + text-file artifacts from the pre-pipeline workflow. **Preserved for reference and one-time data migration. Not part of the canonical pipeline.**

These files come from `C:\Users\prana\OneDrive\Documents\Webley Media\SEO\` and represent ~6 months of hand-rolled keyword processing. They are still useful for:

1. **Validation reference** — when porting filter logic into Postgres functions, comparing outputs against these scripts catches regressions.
2. **Curated data migration** — the `.txt` files contain hand-curated keyword lists (confirmed negatives, review queues, positive examples) that should be migrated INTO the new Supabase schema as `negative_terms`, `positive_terms`, and `gold_examples`. See "Data migration" below.
3. **Ad-hoc one-offs** — if a future Excel-based workflow is needed, these are good starting points.

## Migration status

### PowerShell scripts

| Script | What it does | Status in new system |
|---|---|---|
| `rebuild_negative_v2.ps1` | Rebuilds the master negative-keyword list with prefix/suffix variations | **PORTED** -> `supabase/functions/apply_tier0_regex_filter.sql` |
| `rebuild_negative_keywords.ps1` | Earlier version of the above | **PORTED** -> same as above |
| `categorize_keywords_final.ps1` | Marks keywords by color (red=negative, green=positive) in Excel via OpenXML | **REMOVED** — replaced by `keyword_classifications.status` + Google Sheet conditional formatting |
| `categorize_keywords.ps1` / `_v2.ps1` / `_v3.ps1` / `_v4.ps1` | Earlier iterations of the above | **REMOVED** |
| `combine_keywords.ps1` / `_v2.ps1` | Merges multiple per-competitor CSV exports into a single master CSV | **PORTED** -> WF-01 ingest workflow (handles dedup + normalization too) |
| `extract_keywords.ps1` | Strips a column from an Excel sheet | **PORTED** -> WF-01 ingest step |
| `update_and_filter.ps1` | Updates an Excel sheet's color-coding based on negative match | **REMOVED** — color-coding now in Sheet view via conditional formatting on `priority_score` |
| `analyze_csv2_patterns.ps1` / `_v2` / `_v3` / `_v4` / `_simple` | Exploratory pattern-finding scripts used to identify which negative terms to add | **NOT PORTED** — exploratory; not part of recurring pipeline. Replaced by the NER pass in `prompts/competitor-brand-ner.md` for competitor brands and by the Tier 2 LLM for general intent classification. |

### Text-file artifacts (curated data — migrate into Supabase)

| File | What it contains | Migrate to |
|---|---|---|
| `confirmed_negative_keywords.txt` | Hand-confirmed negative match terms | `negative_terms` table with `match_type='contains'`, `client_id=Webley` |
| `keep_as_negative.txt` | Borderline keywords that the user decided are negative | `negative_terms` (same) |
| `remove_from_negative.txt` | Keywords that were incorrectly classified as negative and should be EXCLUDED from the negative list | Used as **anti-examples** during migration to filter the `negative_terms` import |
| `extracted_keywords.txt` | Raw extracted keyword list from a SEMrush export | Discard (raw data lives in `raw_keywords` table going forward) |
| `csv2_negative_matches.txt` | Output of `analyze_csv2_patterns.ps1` showing which CSV rows matched negative patterns | Discard (audit trail now lives in `keyword_classifications`) |
| `needs_manual_review.txt` | Keywords flagged for human review | Migrate to `human_reviews` table with subject_type='keyword' |
| `needs_review.txt` | Same as above (older version) | Discard if `needs_manual_review.txt` is the latest |
| `review_later.txt` | Keywords parked for future review | Same as `needs_manual_review.txt` |
| `removed_keywords.txt` | Keywords that were removed from the final list | Migrate to `keyword_classifications` with `status='rejected'` to seed the graveyard cache |
| `potential_clients.txt` | Companies / brands the user identified as potential clients (not competitors!) | Not part of this pipeline — informational only |
| `service_buyer_keywords.txt` | The user's curated list of keywords representing service-buyer intent | Migrate to `positive_terms` (split into individual terms) and to `gold_examples` (label='positive') |
| `VBA SCRIPT for text filtering.txt` | The VBA code used to color-code cells in Excel | **REMOVED** functionally — kept for historical context |

## Data migration plan

When the new Supabase schema is deployed, write a one-shot migration script that:

1. Reads `confirmed_negative_keywords.txt` -> upserts into `negative_terms` for the Webley client.
2. Reads `keep_as_negative.txt` -> upserts into `negative_terms`.
3. Reads `remove_from_negative.txt` -> removes those terms from `negative_terms` (or excludes them at insert time).
4. Reads `service_buyer_keywords.txt` -> upserts into `positive_terms` AND inserts 50 sampled entries as `gold_examples` with `label='positive'`.
5. Reads `removed_keywords.txt` -> inserts into `keyword_classifications` with a synthetic `pipeline_run_id` (one historical run named `migration_2026_05`) and `status='graveyard'`, so future runs auto-skip.
6. Reads `needs_manual_review.txt` -> inserts into `human_reviews` as pending items for the next intern to triage.

This migration is a one-time job. Put it in `scripts/one-off/migrate_legacy_data.py` (or `.ts`) when ready.

## Why preserve the originals

- Audit trail: if Tier 0 regex produces different output than the legacy scripts on the same input, we can run both side-by-side to find the regression.
- Onboarding new interns: they can read the originals to understand "how this used to be done" before the new system existed. Helps with mental model.
- Recovery: if any data is lost during migration, the `.txt` files have the raw curated lists.

## Do not

- Do not modify these files. They are read-only history.
- Do not run the PowerShell scripts as part of the production pipeline. They are explicitly out of the loop now.
- Do not commit additional `.txt` raw keyword exports here. New raw data goes into Supabase via WF-01.
