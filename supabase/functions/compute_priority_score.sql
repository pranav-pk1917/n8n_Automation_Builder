-- =============================================================================
-- Function: compute_priority_score
-- Computes cluster priority score per the formula in architecture.md section 8.
--
-- priority_score = (commercial_intent_weight * 5)
--                + (icp_match_score * 3)
--                + (log(total_volume + 1) * 1)
--                - (avg_kd * 0.5)
--                + (first_party_data_bonus * 2)
--                + (pillar_match_bonus * 1.5)
--                + (niche_focus_bonus * 1)
--                - (cannibalization_risk_penalty * 3)
--
-- Inputs are read from the cluster + its keyword members. Returns the score.
-- Idempotent: calling it twice returns the same value for the same inputs.
-- =============================================================================

create or replace function compute_priority_score(
    p_cluster_id  uuid
)
returns numeric
language plpgsql
stable
as $$
declare
    v_cluster                       clusters%rowtype;
    v_intent_weight                 numeric;
    v_first_party_bonus             numeric := 0;
    v_pillar_match_bonus            numeric := 0;
    v_niche_focus_bonus             numeric := 0;
    v_cannibalization_penalty       numeric := 0;
    v_score                         numeric;
begin
    select * into v_cluster from clusters where id = p_cluster_id;

    if not found then
        raise exception 'cluster % not found', p_cluster_id;
    end if;

    -- ---------------------------------------------------------------------
    -- Commercial intent weight
    -- ---------------------------------------------------------------------
    v_intent_weight := case v_cluster.intent_type
        when 'transactional'              then 5
        when 'commercial_investigation'   then 3
        when 'navigational_branded'       then 4
        when 'local'                      then 4
        when 'informational'              then 1
        when 'navigational_other'         then 0
        when 'navigational_competitor'    then -10
        else 0
    end;

    -- ---------------------------------------------------------------------
    -- First-party data bonus: average across cluster members
    -- ---------------------------------------------------------------------
    select coalesce(
        avg(case when kc.first_party_data_available then 1 else 0 end),
        0
    )
    into v_first_party_bonus
    from keyword_classifications kc
    join keyword_cluster_map kcm on kcm.keyword_classification_id = kc.id
    where kcm.cluster_id = p_cluster_id;

    -- ---------------------------------------------------------------------
    -- Pillar match bonus: 1 if a pillar was assigned, 0 otherwise
    -- ---------------------------------------------------------------------
    v_pillar_match_bonus := case
        when v_cluster.suggested_service_pillar is not null
             and v_cluster.suggested_service_pillar <> ''
            then 1
        else 0
    end;

    -- ---------------------------------------------------------------------
    -- Niche focus bonus: 1 if the assigned niche is active for this client
    -- ---------------------------------------------------------------------
    if v_cluster.suggested_vertical_niche_id is not null then
        select case when status = 'active' then 1 else 0 end
          into v_niche_focus_bonus
          from niches
         where id = v_cluster.suggested_vertical_niche_id;
    end if;
    v_niche_focus_bonus := coalesce(v_niche_focus_bonus, 0);

    -- ---------------------------------------------------------------------
    -- Cannibalization risk penalty: 1 if a risk page is flagged
    -- ---------------------------------------------------------------------
    v_cannibalization_penalty := case
        when v_cluster.cannibalization_risk_page_id is not null then 1
        else 0
    end;

    -- ---------------------------------------------------------------------
    -- Final formula
    -- ---------------------------------------------------------------------
    v_score :=  (v_intent_weight                                  * 5.0)
              + (coalesce((select avg(icp_match_score)
                             from keyword_classifications kc
                             join keyword_cluster_map kcm on kcm.keyword_classification_id = kc.id
                            where kcm.cluster_id = p_cluster_id), 0) * 3.0)
              + (ln(greatest(v_cluster.total_volume, 0) + 1)        * 1.0)
              - (coalesce(v_cluster.avg_kd, 0)                      * 0.5)
              + (v_first_party_bonus                                * 2.0)
              + (v_pillar_match_bonus                               * 1.5)
              + (v_niche_focus_bonus                                * 1.0)
              - (v_cannibalization_penalty                          * 3.0);

    return v_score;
end;
$$;

comment on function compute_priority_score(uuid) is
    'Per-cluster priority scoring formula. See docs/architecture.md section 8. '
    'Pure function; safe to recompute after any input change.';

-- =============================================================================
-- Convenience: bulk-update priority_score for all clusters in a pipeline run.
-- =============================================================================

create or replace function refresh_priority_scores(
    p_pipeline_run_id uuid
)
returns int
language plpgsql
as $$
declare
    v_updated int;
begin
    with updated as (
        update clusters
           set priority_score = compute_priority_score(id)
         where pipeline_run_id = p_pipeline_run_id
         returning id
    )
    select count(*) into v_updated from updated;
    return v_updated;
end;
$$;

comment on function refresh_priority_scores(uuid) is
    'Recomputes priority_score for all clusters in a given pipeline run.';
