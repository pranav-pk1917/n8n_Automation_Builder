-- =============================================================================
-- Migration: 0002_pgvector
-- Enables pgvector and converts embedding placeholder columns from text to vector(768).
-- Run AFTER 0001_initial_schema.sql.
-- =============================================================================

create extension if not exists vector with schema public;

-- Convert placeholder text columns to vector(768).
-- ALTER ... USING null::vector(768) wipes any text data in those columns,
-- which is intentional: nothing real is stored at this stage.

alter table gold_examples
    alter column embedding type vector(768) using null::vector(768);

alter table keyword_classifications
    alter column embedding type vector(768) using null::vector(768);

alter table pages
    alter column embedding type vector(768) using null::vector(768);

-- IVFFLAT indexes for similarity search.
-- We pick a small lists value (100) suitable for ~100k vectors per client.
-- Tune later as data scales (rule of thumb: lists = sqrt(rows)).
-- Indexes must be built AFTER some rows exist for IVFFLAT to be effective;
-- creating them empty here is fine, they will populate as data lands.

create index gold_examples_embedding_idx
    on gold_examples
    using ivfflat (embedding vector_cosine_ops)
    with (lists = 100);

create index keyword_classifications_embedding_idx
    on keyword_classifications
    using ivfflat (embedding vector_cosine_ops)
    with (lists = 200);

create index pages_embedding_idx
    on pages
    using ivfflat (embedding vector_cosine_ops)
    with (lists = 50);

-- Helper view: gold positive/negative centroids per client.
-- Used by Tier 1 embedding-similarity filter.
create or replace view v_gold_centroids as
select
    client_id,
    label,
    avg(embedding)::vector(768)         as centroid,
    count(*)                            as example_count
from gold_examples
where embedding is not null
group by client_id, label;

comment on view v_gold_centroids is
    'Per-client per-label centroid of gold_examples embeddings. '
    'Tier 1 cosine similarity compares each keyword against the positive and negative centroids.';
