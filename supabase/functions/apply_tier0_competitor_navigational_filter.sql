-- =============================================================================
-- Function: apply_tier0_competitor_navigational_filter
-- Flags keywords containing competitor brand names as 'navigational_competitor'
-- intent. Routing depends on clients.config.navigational_competitor_strategy:
--   - 'reject_all'             -> status='rejected'
--   - 'allow_comparison_only'  -> status='needs_review' if keyword contains
--                                  comparison signals (vs, alternative,
--                                  comparison, competitor, better than, etc.);
--                                  else 'rejected'.
--
-- Only runs on raw_keywords that are still 'pending' after Tier 0a.
-- =============================================================================

create or replace function apply_tier0_competitor_navigational_filter(
    p_client_id         uuid,
    p_pipeline_run_id   uuid
)
returns table (
    rejected_count          bigint,
    needs_review_count      bigint
)
language plpgsql
as $$
declare
    v_brand_pattern             text;
    v_strategy                  text;
    v_comparison_signal_pattern text := '\m(vs|versus|alternative|alternatives|comparison|compared|competitor|competitors|better than|instead of|or)\M';
begin

    -- ---------------------------------------------------------------------
    -- Build a combined brand-name pattern. Only confirmed brands are used.
    -- ---------------------------------------------------------------------

    select string_agg(
        case match_type
            when 'exact'    then '^' || regexp_replace(brand_name, '([\.\^\$\*\+\?\(\)\[\]\{\}\|\\])', '\\\1', 'g') || '$'
            when 'contains' then '\m' || regexp_replace(brand_name, '([\.\^\$\*\+\?\(\)\[\]\{\}\|\\])', '\\\1', 'g') || '\M'
            else            '\m' || regexp_replace(brand_name, '([\.\^\$\*\+\?\(\)\[\]\{\}\|\\])', '\\\1', 'g') || '\M'
        end,
        '|'
    )
    into v_brand_pattern
    from competitor_brand_names
    where client_id = p_client_id
      and confirmed_by_human = true;

    -- Nothing to do if no brands configured for this client
    if v_brand_pattern is null then
        return query select 0::bigint, 0::bigint;
        return;
    end if;

    -- ---------------------------------------------------------------------
    -- Read the strategy from clients.config (default = 'allow_comparison_only')
    -- ---------------------------------------------------------------------

    select coalesce(
        config ->> 'navigational_competitor_strategy',
        'allow_comparison_only'
    )
    into v_strategy
    from clients
    where id = p_client_id;

    -- ---------------------------------------------------------------------
    -- Update keyword_classifications for the matching pending rows.
    -- ---------------------------------------------------------------------

    update keyword_classifications kc
       set intent_type        = 'navigational_competitor'::intent_type_enum,
           decided_by         = 'tier0_competitor_domain'::decided_by_enum,
           confidence         = 1.000,
           decision_reasoning = case v_strategy
               when 'reject_all'
                   then 'tier0b: matched competitor brand; strategy=reject_all'
               when 'allow_comparison_only'
                   then case
                       when lower(rk.keyword) ~* v_comparison_signal_pattern
                           then 'tier0b: competitor brand + comparison signal; routed to needs_review'
                       else 'tier0b: competitor brand without comparison signal; rejected'
                   end
               else 'tier0b: matched competitor brand'
           end,
           status = case v_strategy
               when 'reject_all'
                   then 'rejected'::classification_status_enum
               when 'allow_comparison_only'
                   then case
                       when lower(rk.keyword) ~* v_comparison_signal_pattern
                           then 'needs_review'::classification_status_enum
                       else 'rejected'::classification_status_enum
                   end
               else 'rejected'::classification_status_enum
           end
      from raw_keywords rk
     where kc.raw_keyword_id = rk.id
       and kc.client_id = p_client_id
       and kc.pipeline_run_id = p_pipeline_run_id
       and kc.status = 'pending'
       and lower(rk.keyword) ~* v_brand_pattern;

    -- ---------------------------------------------------------------------
    -- Return counts
    -- ---------------------------------------------------------------------

    return query
    select
        count(*) filter (where status = 'rejected' and intent_type = 'navigational_competitor')         as rejected_count,
        count(*) filter (where status = 'needs_review' and intent_type = 'navigational_competitor')     as needs_review_count
    from keyword_classifications
    where client_id = p_client_id
      and pipeline_run_id = p_pipeline_run_id;

end;
$$;

comment on function apply_tier0_competitor_navigational_filter(uuid, uuid) is
    'Tier 0b: deterministic competitor-brand navigational filter. '
    'Strategy from clients.config.navigational_competitor_strategy: reject_all | allow_comparison_only.';
