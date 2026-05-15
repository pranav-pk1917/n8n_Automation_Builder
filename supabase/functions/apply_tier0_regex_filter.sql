-- =============================================================================
-- Function: apply_tier0_regex_filter
-- Port of rebuild_negative_v2.ps1 + rebuild_negative_keywords.ps1.
-- Deterministic regex/contains/exact match of negative and positive terms.
--
-- Writes one row per raw_keyword to keyword_classifications:
--   - negative match    -> status='rejected', decided_by='tier0_regex'
--   - positive match    -> status='passed',   decided_by='tier0_regex'
--   - no match          -> status='pending'   (handed off to Tier 1)
--
-- Returns counts for logging.
-- =============================================================================

create or replace function apply_tier0_regex_filter(
    p_client_id         uuid,
    p_pipeline_run_id   uuid
)
returns table (
    rejected_count  bigint,
    passed_count    bigint,
    pending_count   bigint
)
language plpgsql
as $$
declare
    v_negative_pattern text;
    v_positive_pattern text;
begin

    -- -----------------------------------------------------------------------
    -- Build combined regex patterns from negative_terms and positive_terms.
    -- We honor both per-client rules and global (client_id IS NULL) rules.
    -- For 'exact' match_type we anchor with ^...$.
    -- For 'contains' we use \mword\M boundaries (word-boundary).
    -- For 'regex' we use the term as-is.
    -- -----------------------------------------------------------------------

    select string_agg(
        case match_type
            when 'exact'    then '^' || regexp_replace(term, '([\.\^\$\*\+\?\(\)\[\]\{\}\|\\])', '\\\1', 'g') || '$'
            when 'contains' then '\m' || regexp_replace(term, '([\.\^\$\*\+\?\(\)\[\]\{\}\|\\])', '\\\1', 'g') || '\M'
            when 'regex'    then term
        end,
        '|'
    )
    into v_negative_pattern
    from negative_terms
    where client_id = p_client_id or client_id is null;

    select string_agg(
        case match_type
            when 'exact'    then '^' || regexp_replace(term, '([\.\^\$\*\+\?\(\)\[\]\{\}\|\\])', '\\\1', 'g') || '$'
            when 'contains' then '\m' || regexp_replace(term, '([\.\^\$\*\+\?\(\)\[\]\{\}\|\\])', '\\\1', 'g') || '\M'
            when 'regex'    then term
        end,
        '|'
    )
    into v_positive_pattern
    from positive_terms
    where client_id = p_client_id or client_id is null;

    -- -----------------------------------------------------------------------
    -- Insert one keyword_classifications row per raw_keyword in this run.
    -- Negative wins ties (safety bias: when in doubt, reject).
    -- -----------------------------------------------------------------------

    insert into keyword_classifications (
        raw_keyword_id,
        client_id,
        pipeline_run_id,
        status,
        decided_by,
        decision_reasoning,
        confidence
    )
    select
        rk.id,
        rk.client_id,
        rk.pipeline_run_id,
        case
            when v_negative_pattern is not null
                 and lower(rk.keyword) ~* v_negative_pattern
                then 'rejected'::classification_status_enum
            when v_positive_pattern is not null
                 and lower(rk.keyword) ~* v_positive_pattern
                then 'passed'::classification_status_enum
            else 'pending'::classification_status_enum
        end,
        case
            when v_negative_pattern is not null
                 and lower(rk.keyword) ~* v_negative_pattern
                then 'tier0_regex'::decided_by_enum
            when v_positive_pattern is not null
                 and lower(rk.keyword) ~* v_positive_pattern
                then 'tier0_regex'::decided_by_enum
            else null
        end,
        case
            when v_negative_pattern is not null
                 and lower(rk.keyword) ~* v_negative_pattern
                then 'tier0: matched negative pattern'
            when v_positive_pattern is not null
                 and lower(rk.keyword) ~* v_positive_pattern
                then 'tier0: matched positive pattern'
            else null
        end,
        case
            when v_negative_pattern is not null
                 and lower(rk.keyword) ~* v_negative_pattern
                then 1.000
            when v_positive_pattern is not null
                 and lower(rk.keyword) ~* v_positive_pattern
                then 1.000
            else null
        end
    from raw_keywords rk
    where rk.client_id = p_client_id
      and rk.pipeline_run_id = p_pipeline_run_id
      and not exists (
          select 1
            from keyword_classifications kc
           where kc.raw_keyword_id = rk.id
      );

    -- -----------------------------------------------------------------------
    -- Return counts
    -- -----------------------------------------------------------------------

    return query
    select
        count(*) filter (where kc.status = 'rejected')  as rejected_count,
        count(*) filter (where kc.status = 'passed')    as passed_count,
        count(*) filter (where kc.status = 'pending')   as pending_count
    from keyword_classifications kc
    where kc.client_id = p_client_id
      and kc.pipeline_run_id = p_pipeline_run_id;

end;
$$;

comment on function apply_tier0_regex_filter(uuid, uuid) is
    'Tier 0a: deterministic regex/contains/exact filter using negative_terms and positive_terms. '
    'Idempotent: skips raw_keywords already classified for this run.';
