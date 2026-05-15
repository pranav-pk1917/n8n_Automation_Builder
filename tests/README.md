# Tests

End-to-end smoke tests and fixtures for the pipeline.

## Layout

```
tests/
  fixtures/
    sample_semrush_export.csv         small synthetic SEMrush-shaped CSV
    expected_tier0_filter_output.csv  reference output for Tier 0 regression check
    gold_examples_starter.csv         starter gold examples for Webley
  e2e/
    test_tier0_filter.sql             pgTAP smoke for Postgres functions
    test_clustering_worker.py         calls the Python worker against a deterministic input set
    test_pipeline_end_to_end.md       manual checklist for a full run
```

## Strategy

- **Postgres functions** are tested via pgTAP-style SQL assertions in `e2e/`.
- **Python worker** uses pytest against a local Supabase instance (or a mocked client).
- **n8n workflows** are tested by running them against fixture inputs and asserting Supabase state after.
- **Cross-system smoke** uses `test_pipeline_end_to_end.md` as a manual checklist for first deploy.

Add proper test runners (pytest config, pgTAP setup, n8n test harness) as Phase 1 nears completion.
