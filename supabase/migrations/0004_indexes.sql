-- =============================================================================
-- Migration: 0004_indexes
-- Performance indexes for hot query paths. ivfflat vector indexes are in 0002.
--
-- Note: this file was edited after initial creation to remove a broken
-- `create index ... (select ...)` definition that Postgres rejects with
-- `0A000: cannot use subquery in index expression`. The migration was never
-- successfully applied anywhere before that fix, so editing in place was
-- preferred over a 0005 cleanup migration. Every `create index` is now
-- idempotent via `if not exists` so partial re-runs are safe.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Lookup by (client_id, ...) is the dominant access pattern
-- -----------------------------------------------------------------------------

create index if not exists idx_raw_keywords_client_run
    on raw_keywords (client_id, pipeline_run_id);
create index if not exists idx_raw_keywords_client_keyword
    on raw_keywords (client_id, lower(keyword));

create index if not exists idx_keyword_classifications_client_run
    on keyword_classifications (client_id, pipeline_run_id);

create index if not exists idx_keyword_classifications_status
    on keyword_classifications (client_id, status);

create index if not exists idx_keyword_classifications_intent
    on keyword_classifications (client_id, intent_type);

create index if not exists idx_keyword_classifications_raw
    on keyword_classifications (raw_keyword_id);

create index if not exists idx_clusters_client_run
    on clusters (client_id, pipeline_run_id);

create index if not exists idx_clusters_priority
    on clusters (client_id, priority_score desc nulls last);

create index if not exists idx_clusters_pillar
    on clusters (client_id, suggested_service_pillar);

create index if not exists idx_keyword_cluster_map_cluster
    on keyword_cluster_map (cluster_id);
create index if not exists idx_keyword_cluster_map_kc
    on keyword_cluster_map (keyword_classification_id);

create index if not exists idx_pipeline_runs_client
    on pipeline_runs (client_id, started_at desc);

create index if not exists idx_api_cost_log_run
    on api_cost_log (pipeline_run_id);
create index if not exists idx_api_cost_log_client_date
    on api_cost_log (client_id, created_at desc);

create index if not exists idx_human_reviews_open
    on human_reviews (client_id, subject_type)
    where decision is null;

create index if not exists idx_quality_audits_client_recent
    on quality_audits (client_id, created_at desc);

create index if not exists idx_cross_validation_events_open
    on cross_validation_events (client_id, severity)
    where resolved = false;

create index if not exists idx_taxonomy_suggestions_open
    on taxonomy_suggestions (client_id, kind)
    where status = 'pending';

create index if not exists idx_negative_terms_client
    on negative_terms (client_id);
create index if not exists idx_positive_terms_client
    on positive_terms (client_id);

create index if not exists idx_competitor_brand_names_client
    on competitor_brand_names (client_id, confirmed_by_human);

create index if not exists idx_pages_client_pillar
    on pages (client_id, service_pillar);
create index if not exists idx_pages_client_url
    on pages (client_id, url_path);

-- -----------------------------------------------------------------------------
-- Graveyard cache lookup (skip previously-rejected keywords on re-ingest).
--
-- WF-01 ingest deduplicates by joining raw_keywords against
-- keyword_classifications and checking status in ('rejected','graveyard').
-- A subquery inside an index expression is not legal in Postgres, so instead
-- we index the source column (raw_keywords.keyword, lowercased) and let the
-- application query do the join. The existing idx_keyword_classifications_raw
-- (above) covers the join from the classification side.
--
-- Reference query for WF-01:
--   SELECT 1 FROM raw_keywords rk
--   JOIN keyword_classifications kc ON kc.raw_keyword_id = rk.id
--   WHERE rk.client_id = $1
--     AND lower(rk.keyword) = lower($2)
--     AND kc.status IN ('rejected','graveyard');
-- which uses idx_raw_keywords_lower_keyword + idx_keyword_classifications_raw.
-- -----------------------------------------------------------------------------

create index if not exists idx_raw_keywords_lower_keyword
    on raw_keywords (client_id, lower(keyword));
