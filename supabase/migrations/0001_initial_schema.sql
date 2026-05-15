-- =============================================================================
-- Migration: 0001_initial_schema
-- Phase 1 v3.2 schema. Multi-tenant keyword pipeline.
-- See docs/architecture.md and docs/adr/0001-three-axis-taxonomy.md.
-- =============================================================================

set timezone = 'UTC';

-- -----------------------------------------------------------------------------
-- Enums (named, not inlined)
-- -----------------------------------------------------------------------------

create type onboarding_status_enum as enum (
    'pending',
    'crawled',
    'questionnaire_complete',
    'validated',
    'active',
    'suspended'
);

create type client_member_role_enum as enum (
    'owner',
    'admin',
    'editor',
    'viewer'
);

create type match_type_enum as enum (
    'exact',
    'contains',
    'regex'
);

create type label_enum as enum (
    'positive',
    'negative'
);

create type competitor_brand_source_enum as enum (
    'manual',
    'ner_extracted',
    'crawled'
);

create type classification_status_enum as enum (
    'pending',
    'passed',
    'rejected',
    'needs_review',
    'human_overridden',
    'graveyard'
);

create type decided_by_enum as enum (
    'tier0_regex',
    'tier0_competitor_domain',
    'tier1_embedding',
    'tier2_llm',
    'human_reviewer'
);

create type intent_type_enum as enum (
    'informational',
    'commercial_investigation',
    'transactional',
    'navigational_competitor',
    'navigational_branded',
    'navigational_other',
    'local'
);

create type cluster_member_role_enum as enum (
    'head',
    'lsi_variant',
    'long_tail_supporting',
    'modifier'
);

create type page_source_enum as enum (
    'next_static',
    'wordpress',
    'landing_page',
    'crawl_discovered'
);

create type pipeline_run_kind_enum as enum (
    'onboard',
    'page_sync',
    'ingest',
    'filter',
    'cluster',
    'score'
);

create type pipeline_run_status_enum as enum (
    'running',
    'completed',
    'failed',
    'paused_cost_ceiling',
    'paused_quality_drift'
);

create type human_review_subject_enum as enum (
    'keyword',
    'cluster',
    'competitor_brand',
    'pillar_assignment',
    'niche_proposal',
    'theme_proposal',
    'config_value',
    'cost_ceiling_breach',
    'quality_drift'
);

create type human_review_decision_enum as enum (
    'approve',
    'reject',
    'escalate',
    'skip',
    'reroute',
    'extend_ceiling_by',
    'abort_run'
);

create type quality_audit_type_enum as enum (
    'random_sample',
    'disagreement_followup'
);

create type cross_validation_event_type_enum as enum (
    'human_override_ai_recheck',
    'ai_decision_human_review',
    'gold_example_refresh_revalidation',
    'questionnaire_vs_crawl_mismatch',
    'cost_ceiling_hit',
    'quality_drift_alert',
    'cannibalization_risk_flagged'
);

create type cross_validation_actor_enum as enum (
    'ai',
    'human'
);

create type cross_validation_severity_enum as enum (
    'low',
    'medium',
    'high'
);

create type taxonomy_suggestion_kind_enum as enum (
    'new_pillar',
    'new_niche',
    'new_content_theme',
    'merge_pillars',
    'merge_niches',
    'split_cluster'
);

create type taxonomy_suggestion_status_enum as enum (
    'pending',
    'accepted',
    'rejected'
);

create type niche_status_enum as enum (
    'active',
    'proposed',
    'rejected'
);

create type niche_source_enum as enum (
    'onboarding_declared',
    'discovered_via_data'
);

-- -----------------------------------------------------------------------------
-- Core tenant tables
-- -----------------------------------------------------------------------------

create table clients (
    id                  uuid primary key default gen_random_uuid(),
    name                text not null,
    slug                text not null unique,
    canonical_domain    text,
    config              jsonb not null default '{}'::jsonb,
    onboarding_status   onboarding_status_enum not null default 'pending',
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now()
);
comment on table clients is
    'One row per agency client. config jsonb holds service_pillars, icp_persona, brand_voice, '
    'monthly_api_budget_usd, expected_runs_per_month, per_run_cost_ceiling_pct, review_tier, '
    'navigational_competitor_strategy, hitl_channels, hitl_routing, negative_overrides, positive_overrides.';

create table client_members (
    id              uuid primary key default gen_random_uuid(),
    client_id       uuid not null references clients(id) on delete cascade,
    auth_user_id    uuid not null,                                          -- Supabase auth.users.id
    role            client_member_role_enum not null default 'viewer',
    created_at      timestamptz not null default now(),
    unique (client_id, auth_user_id)
);
comment on table client_members is 'Maps Supabase auth users to clients. Used by RLS policies.';

create table services (
    id              uuid primary key default gen_random_uuid(),
    client_id       uuid not null references clients(id) on delete cascade,
    pillar_name     text not null,                                          -- references the pillar key in clients.config.service_pillars
    name            text not null,
    description     text,
    created_at      timestamptz not null default now()
);

create table niches (
    id              uuid primary key default gen_random_uuid(),
    client_id       uuid not null references clients(id) on delete cascade,
    name            text not null,
    description     text,
    source          niche_source_enum not null default 'onboarding_declared',
    status          niche_status_enum not null default 'active',
    created_at      timestamptz not null default now(),
    unique (client_id, name)
);

-- -----------------------------------------------------------------------------
-- Ingest + filter tables
-- -----------------------------------------------------------------------------

create table seed_keywords (
    id              uuid primary key default gen_random_uuid(),
    client_id       uuid not null references clients(id) on delete cascade,
    service_id      uuid references services(id) on delete set null,
    niche_id        uuid references niches(id) on delete set null,
    keyword         text not null,
    created_at      timestamptz not null default now()
);

create table competitors (
    id                  uuid primary key default gen_random_uuid(),
    client_id           uuid not null references clients(id) on delete cascade,
    domain              text not null,
    seed_keyword_id     uuid references seed_keywords(id) on delete set null,
    position            int,                                                -- SERP position when discovered
    discovered_at       timestamptz not null default now()
);

create table competitor_brand_names (
    id                      uuid primary key default gen_random_uuid(),
    client_id               uuid not null references clients(id) on delete cascade,
    brand_name              text not null,
    match_type              match_type_enum not null default 'contains',
    source                  competitor_brand_source_enum not null default 'manual',
    confirmed_by_human      boolean not null default false,
    created_at              timestamptz not null default now()
);
comment on table competitor_brand_names is
    'Feeds Tier 0b competitor-navigational filter. NER auto-populates; human confirms before activation.';

create table pipeline_runs (
    id                  uuid primary key default gen_random_uuid(),
    client_id           uuid not null references clients(id) on delete cascade,
    kind                pipeline_run_kind_enum not null,
    status              pipeline_run_status_enum not null default 'running',
    started_at          timestamptz not null default now(),
    finished_at         timestamptz,
    triggered_by        text,                                               -- 'cron', 'webhook', 'manual:<user>'
    cost_so_far_usd     numeric(10, 4) not null default 0,
    cost_ceiling_usd    numeric(10, 4),                                     -- locked at run start; nullable for runs that don't gate on cost (e.g., page_sync)
    input_summary       jsonb,
    output_summary      jsonb
);
comment on column pipeline_runs.cost_so_far_usd is
    'Rolling sum of api_cost_log.usd_cost for this run. Updated by triggers.';

create table raw_keywords (
    id                  uuid primary key default gen_random_uuid(),
    client_id           uuid not null references clients(id) on delete cascade,
    pipeline_run_id     uuid not null references pipeline_runs(id) on delete cascade,
    keyword             text not null,
    volume              int,
    kd                  numeric(5, 2),
    cpc                 numeric(10, 4),
    competition         numeric(5, 4),
    source_competitor   text,
    serp_features       jsonb,
    intent_semrush      text,
    imported_at         timestamptz not null default now()
);

create table negative_terms (
    id              uuid primary key default gen_random_uuid(),
    client_id       uuid references clients(id) on delete cascade,         -- null = global rule
    term            text not null,
    match_type      match_type_enum not null default 'contains',
    created_at      timestamptz not null default now()
);

create table positive_terms (
    id              uuid primary key default gen_random_uuid(),
    client_id       uuid references clients(id) on delete cascade,
    term            text not null,
    match_type      match_type_enum not null default 'contains',
    created_at      timestamptz not null default now()
);

create table gold_examples (
    id              uuid primary key default gen_random_uuid(),
    client_id       uuid not null references clients(id) on delete cascade,
    keyword         text not null,
    label           label_enum not null,
    embedding       text,                                                   -- placeholder; replaced by vector(768) in 0002_pgvector
    notes           text,
    added_by        text,
    created_at      timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Classification with audit trail
-- -----------------------------------------------------------------------------

create table keyword_classifications (
    id                          uuid primary key default gen_random_uuid(),
    raw_keyword_id              uuid not null references raw_keywords(id) on delete cascade,
    client_id                   uuid not null references clients(id) on delete cascade,
    pipeline_run_id             uuid not null references pipeline_runs(id) on delete cascade,
    status                      classification_status_enum not null default 'pending',
    decided_by                  decided_by_enum,
    decision_reasoning          text,
    confidence                  numeric(4, 3),                              -- 0.000 to 1.000
    intent_type                 intent_type_enum,
    niche_hint                  text,                                        -- LLM-derived; freeform until matched to niches.id
    content_theme_hint          text,                                        -- LLM-derived
    icp_match_score             numeric(4, 3),
    first_party_data_available  boolean not null default false,
    embedding                   text,                                        -- placeholder; replaced by vector(768) in 0002_pgvector
    llm_prompt_hash             text,
    human_override              boolean not null default false,
    reviewed_by                 text,
    reviewed_at                 timestamptz,
    ai_second_pass_agrees       boolean,                                     -- null until cross-validation engine runs
    classified_at               timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Clustering (3-axis labels + LSI role)
-- -----------------------------------------------------------------------------

create table clusters (
    id                              uuid primary key default gen_random_uuid(),
    client_id                       uuid not null references clients(id) on delete cascade,
    pipeline_run_id                 uuid not null references pipeline_runs(id) on delete cascade,
    canonical_head_term             text not null,
    theme_label                     text,
    suggested_service_pillar        text,                                    -- matches a pillar key in clients.config.service_pillars; null if no match
    pillar_assignment_confidence    numeric(4, 3),
    suggested_vertical_niche_id     uuid references niches(id) on delete set null,
    niche_assignment_confidence     numeric(4, 3),
    content_theme                   text,
    intent_type                     intent_type_enum,
    keyword_count                   int not null default 0,
    total_volume                    bigint not null default 0,
    avg_kd                          numeric(5, 2),
    priority_score                  numeric(8, 3),
    cannibalization_risk_page_id    uuid,                                    -- FK added in 0004_indexes after pages exists; column declared here
    cannibalization_similarity      numeric(4, 3),
    distribution_strategy           jsonb,                                   -- Phase 3 reserved
    target_page_id                  uuid,                                    -- Phase 2 reserved
    last_clustered_at               timestamptz not null default now()
);
comment on table clusters is
    'A cluster is one cell in the (pillar x niche x theme) cube. See docs/adr/0001-three-axis-taxonomy.md.';

create table keyword_cluster_map (
    id                          uuid primary key default gen_random_uuid(),
    keyword_classification_id   uuid not null references keyword_classifications(id) on delete cascade,
    cluster_id                  uuid not null references clusters(id) on delete cascade,
    role                        cluster_member_role_enum not null default 'long_tail_supporting',
    distance_from_centroid      numeric(6, 4),
    unique (keyword_classification_id, cluster_id)
);

-- -----------------------------------------------------------------------------
-- Site pages (active in Phase 1 for cannibalization checks)
-- -----------------------------------------------------------------------------

create table pages (
    id                          uuid primary key default gen_random_uuid(),
    client_id                   uuid not null references clients(id) on delete cascade,
    url_path                    text not null,
    title                       text,
    meta_description            text,
    source                      page_source_enum not null,
    wp_post_id                  bigint,
    service_pillar              text,
    intent_type                 intent_type_enum,
    embedding                   text,                                        -- placeholder; replaced by vector(768) in 0002_pgvector
    last_seen_at                timestamptz not null default now(),
    gsc_clicks_30d              int,                                          -- Phase 4 reserved
    gsc_impressions_30d         int,                                          -- Phase 4 reserved
    unique (client_id, url_path)
);

-- Now that pages exists, add the FK for clusters.cannibalization_risk_page_id
alter table clusters
    add constraint clusters_cannibalization_risk_page_id_fkey
    foreign key (cannibalization_risk_page_id) references pages(id) on delete set null;

alter table clusters
    add constraint clusters_target_page_id_fkey
    foreign key (target_page_id) references pages(id) on delete set null;

-- -----------------------------------------------------------------------------
-- Audit + cost + quality + cross-validation
-- -----------------------------------------------------------------------------

create table api_cost_log (
    id                  uuid primary key default gen_random_uuid(),
    pipeline_run_id     uuid not null references pipeline_runs(id) on delete cascade,
    client_id           uuid not null references clients(id) on delete cascade,
    provider            text not null,                                       -- 'gemini', 'openai', 'serpapi', etc.
    model               text,
    operation           text not null,                                       -- 'embedding', 'classify', 'cluster_label', 'serp_lookup'
    input_tokens        int,
    output_tokens       int,
    usd_cost            numeric(10, 6) not null default 0,
    created_at          timestamptz not null default now()
);

create table human_reviews (
    id                  uuid primary key default gen_random_uuid(),
    pipeline_run_id     uuid references pipeline_runs(id) on delete set null,
    client_id           uuid not null references clients(id) on delete cascade,
    subject_type        human_review_subject_enum not null,
    subject_id          uuid not null,
    question            text,
    decision            human_review_decision_enum,
    decision_metadata   jsonb,
    decided_by          text,
    decided_at          timestamptz,
    notes               text,
    created_at          timestamptz not null default now()
);

create table quality_audits (
    id                          uuid primary key default gen_random_uuid(),
    client_id                   uuid not null references clients(id) on delete cascade,
    pipeline_run_id             uuid references pipeline_runs(id) on delete set null,
    keyword_classification_id   uuid not null references keyword_classifications(id) on delete cascade,
    ai_decision                 text,
    ai_confidence               numeric(4, 3),
    human_decision              text,
    agreement                   boolean,
    audit_type                  quality_audit_type_enum not null default 'random_sample',
    created_at                  timestamptz not null default now()
);

create table cross_validation_events (
    id                      uuid primary key default gen_random_uuid(),
    client_id               uuid not null references clients(id) on delete cascade,
    pipeline_run_id         uuid references pipeline_runs(id) on delete set null,
    subject_type            human_review_subject_enum,
    subject_id              uuid,
    event_type              cross_validation_event_type_enum not null,
    actor                   cross_validation_actor_enum not null,
    decision_before         text,
    decision_after          text,
    agreement               boolean,
    evidence                jsonb,
    severity                cross_validation_severity_enum not null default 'low',
    resolved                boolean not null default false,
    resolved_at             timestamptz,
    created_at              timestamptz not null default now()
);

create table taxonomy_suggestions (
    id                      uuid primary key default gen_random_uuid(),
    client_id               uuid not null references clients(id) on delete cascade,
    kind                    taxonomy_suggestion_kind_enum not null,
    suggested_value         text not null,
    rationale               text,
    evidence_cluster_ids    uuid[] not null default '{}'::uuid[],
    status                  taxonomy_suggestion_status_enum not null default 'pending',
    decided_by              text,
    decided_at              timestamptz,
    created_at              timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Reserved tables for Phase 2-4 (schema-locked to avoid future migrations)
-- -----------------------------------------------------------------------------

create table briefs (
    id              uuid primary key default gen_random_uuid(),
    client_id       uuid not null references clients(id) on delete cascade,
    cluster_id      uuid references clusters(id) on delete set null,
    -- Phase 2 fields added in a future migration
    created_at      timestamptz not null default now()
);

create table drafts (
    id              uuid primary key default gen_random_uuid(),
    client_id       uuid not null references clients(id) on delete cascade,
    brief_id        uuid references briefs(id) on delete set null,
    -- Phase 2 fields added in a future migration
    created_at      timestamptz not null default now()
);

create table distribution_posts (
    id              uuid primary key default gen_random_uuid(),
    client_id       uuid not null references clients(id) on delete cascade,
    -- Phase 3 fields added in a future migration
    created_at      timestamptz not null default now()
);

create table gsc_metrics (
    id              uuid primary key default gen_random_uuid(),
    client_id       uuid not null references clients(id) on delete cascade,
    page_id         uuid references pages(id) on delete cascade,
    -- Phase 4 fields added in a future migration
    created_at      timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- updated_at triggers
-- -----------------------------------------------------------------------------

create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger clients_set_updated_at
    before update on clients
    for each row execute function set_updated_at();

-- -----------------------------------------------------------------------------
-- Rolling cost tracker trigger
-- -----------------------------------------------------------------------------

create or replace function increment_pipeline_run_cost()
returns trigger
language plpgsql
as $$
begin
    update pipeline_runs
       set cost_so_far_usd = cost_so_far_usd + new.usd_cost
     where id = new.pipeline_run_id;
    return new;
end;
$$;

create trigger api_cost_log_increment_run
    after insert on api_cost_log
    for each row execute function increment_pipeline_run_cost();

-- -----------------------------------------------------------------------------
-- End of 0001
-- -----------------------------------------------------------------------------
