-- =============================================================================
-- Migration: wave-1-foundations
-- Phase 2 update spec, Wave 1.
-- Companion document: SEO-Tools/n8n-workflows/Manual-Review/prd/phase-2-update-spec.md
--
-- Scope (deliberately small):
--   1. onboarding_sessions     (NEW table; durable cross-execution state for WF-ONBOARD's 3 phases)
--   2. keyword_cluster_map     (ALTER: add client_id + pipeline_run_id traceability columns)
--   3. clusters                (ALTER: add worker_cluster_id only — all other PRD-proposed columns already exist)
--   4. raw_keywords            (UNIQUE index promotion — see precheck below before running this section)
--
-- What this migration explicitly does NOT do:
--   - Does NOT create clusters, keyword_cluster_map, pipeline_runs, gold_examples,
--     competitor_brand_names, cross_validation_events, api_cost_log, or any other
--     table from 0001_initial_schema.sql. They all already exist.
--   - Does NOT add clusters.pipeline_run_id / total_volume / avg_kd / priority_score —
--     all already exist in 0001_initial_schema.sql.
--   - Does NOT define apply_tier0_filters / tier1_embed_and_score — those are
--     workflow drift (see OD-1 in phase-2-update-spec.md §0.2), not missing functions.
--
-- Idempotent: every statement uses IF NOT EXISTS / ADD COLUMN IF NOT EXISTS.
-- =============================================================================

set timezone = 'UTC';

-- -----------------------------------------------------------------------------
-- 1. onboarding_sessions (NEW)
-- -----------------------------------------------------------------------------
-- WF-ONBOARD runs as three separate webhook executions (Phase A crawl + LLM,
-- Phase B questionnaire response, Phase C optional flag ack). Phase B/C cannot
-- reference Phase A node outputs because each webhook starts a fresh execution.
-- This table is the durable handoff, keyed by pipeline_run_id.

create table if not exists onboarding_sessions (
    pipeline_run_id         uuid primary key references pipeline_runs(id) on delete cascade,
    client_url              text not null,
    client_name             text not null,
    competitors             text[] not null default '{}',
    seed_keywords           text[] not null default '{}',
    crawled_pages           jsonb not null default '[]'::jsonb,
    llm_site_analysis       jsonb,
    questionnaire_response  jsonb,
    cross_validation        jsonb,
    status                  text not null default 'phase_a',
        -- valid: phase_a, phase_a_complete, awaiting_questionnaire,
        --        phase_b_complete, awaiting_flag_ack, completed, failed
    created_at              timestamptz not null default now(),
    updated_at              timestamptz not null default now()
);

comment on table onboarding_sessions is
    'Durable per-execution state for WF-ONBOARD. Each row is one onboarding attempt, keyed by pipeline_runs.id. Phase B/C re-hydrate by SELECTing this row; Slack modal private_metadata carries the pipeline_run_id between phases.';

create index if not exists idx_onboarding_sessions_status
    on onboarding_sessions(status);

create index if not exists idx_onboarding_sessions_created
    on onboarding_sessions(created_at desc);

-- -----------------------------------------------------------------------------
-- 2. keyword_cluster_map traceability (ALTER existing table)
-- -----------------------------------------------------------------------------
-- The table itself ships in 0001_initial_schema.sql with
-- (keyword_classification_id, cluster_id, role, distance_from_centroid).
-- These two columns let WF-04 / WF-05 filter map rows by client and by run
-- without joining back through clusters every time.

alter table keyword_cluster_map
    add column if not exists client_id uuid references clients(id) on delete cascade;

alter table keyword_cluster_map
    add column if not exists pipeline_run_id uuid references pipeline_runs(id) on delete cascade;

create index if not exists idx_keyword_cluster_map_client
    on keyword_cluster_map(client_id);

create index if not exists idx_keyword_cluster_map_client_run
    on keyword_cluster_map(client_id, pipeline_run_id);

-- -----------------------------------------------------------------------------
-- 3. clusters.worker_cluster_id (ALTER)
-- -----------------------------------------------------------------------------
-- The integer cluster ID returned by the Python HDBSCAN worker. Kept on the
-- clusters row for traceability when re-running clustering with different
-- min_cluster_size / metric / etc. All other PRD-proposed columns
-- (pipeline_run_id, total_volume, avg_kd) already exist on clusters.

alter table clusters
    add column if not exists worker_cluster_id int;

-- -----------------------------------------------------------------------------
-- 4. raw_keywords (client_id, lower(keyword)) UNIQUE
-- -----------------------------------------------------------------------------
-- 0004_indexes.sql already creates a non-unique index on these columns
-- (idx_raw_keywords_client_keyword + idx_raw_keywords_lower_keyword). The
-- Phase-2 spec needs the same expression as a UNIQUE constraint so WF-01 can
-- safely use Supabase Prefer: resolution=merge-duplicates with
-- on_conflict=client_id,keyword. This eliminates the 50k Range cap dedupe path
-- and the unused graveyard branch.
--
-- *** PRE-CHECK BEFORE THIS BLOCK ***
-- Run this first; if it returns any rows, resolve duplicates before continuing:
--
--   select client_id, lower(keyword), count(*)
--     from raw_keywords
--    group by client_id, lower(keyword)
--   having count(*) > 1
--    limit 50;
--
-- If clean, this CREATE UNIQUE INDEX is safe to run.
-- ----------------------------------------------------------------------------

create unique index if not exists uq_raw_keywords_client_keyword
    on raw_keywords (client_id, lower(keyword));

-- The non-unique idx_raw_keywords_lower_keyword from 0004_indexes.sql is now
-- redundant (the unique index covers it), but it is intentionally not dropped
-- here — index drops happen in a follow-up housekeeping migration once we have
-- confirmed via pg_stat_user_indexes that no query plans still reference it.

-- =============================================================================
-- End of wave-1-foundations.
-- Verify with phase-2-update-spec.md §5 "Verification gates".
-- =============================================================================
