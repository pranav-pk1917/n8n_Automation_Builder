-- =============================================================================
-- Function: check_cost_ceiling
-- Pre-batch cost guardrail. See docs/adr/0003-cost-ceiling-auto-pause.md.
--
-- Inputs:
--   p_pipeline_run_id - the run to check
--   p_predicted_additional_usd - the cost we are about to incur in the next batch
--
-- Returns a row indicating whether the next batch is allowed and, if not,
-- the reason. n8n inspects this row and either proceeds or pauses + alerts.
-- =============================================================================

create or replace function check_cost_ceiling(
    p_pipeline_run_id           uuid,
    p_predicted_additional_usd  numeric
)
returns table (
    allowed             boolean,
    reason              text,
    cost_so_far_usd     numeric,
    cost_ceiling_usd    numeric,
    projected_total_usd numeric
)
language plpgsql
stable
as $$
declare
    v_run pipeline_runs%rowtype;
begin
    select * into v_run from pipeline_runs where id = p_pipeline_run_id;

    if not found then
        return query
        select false, 'pipeline_run not found', null::numeric, null::numeric, null::numeric;
        return;
    end if;

    -- A null ceiling means cost-gating is disabled for this run (e.g., page_sync).
    if v_run.cost_ceiling_usd is null then
        return query
        select true,
               'no ceiling configured',
               v_run.cost_so_far_usd,
               null::numeric,
               v_run.cost_so_far_usd + coalesce(p_predicted_additional_usd, 0);
        return;
    end if;

    return query
    select
        (v_run.cost_so_far_usd + coalesce(p_predicted_additional_usd, 0)) <= v_run.cost_ceiling_usd,
        case
            when (v_run.cost_so_far_usd + coalesce(p_predicted_additional_usd, 0)) <= v_run.cost_ceiling_usd
                then 'within ceiling'
            else 'projected total exceeds ceiling'
        end,
        v_run.cost_so_far_usd,
        v_run.cost_ceiling_usd,
        v_run.cost_so_far_usd + coalesce(p_predicted_additional_usd, 0);
end;
$$;

comment on function check_cost_ceiling(uuid, numeric) is
    'Pre-batch cost guardrail. Returns whether the next batch should proceed. '
    'See docs/adr/0003-cost-ceiling-auto-pause.md.';

-- =============================================================================
-- Convenience: locks the ceiling at run start based on clients.config
-- =============================================================================

create or replace function lock_run_cost_ceiling(
    p_pipeline_run_id uuid
)
returns numeric
language plpgsql
as $$
declare
    v_client_id             uuid;
    v_monthly_budget        numeric;
    v_expected_runs         numeric;
    v_ceiling_pct           numeric;
    v_ceiling               numeric;
begin
    select client_id into v_client_id from pipeline_runs where id = p_pipeline_run_id;

    select
        coalesce((config->>'monthly_api_budget_usd')::numeric, 50),
        coalesce((config->>'expected_runs_per_month')::numeric, 4),
        coalesce((config->>'per_run_cost_ceiling_pct')::numeric, 150)
      into v_monthly_budget, v_expected_runs, v_ceiling_pct
      from clients
     where id = v_client_id;

    v_ceiling := (v_monthly_budget / nullif(v_expected_runs, 0)) * (v_ceiling_pct / 100.0);

    update pipeline_runs
       set cost_ceiling_usd = v_ceiling
     where id = p_pipeline_run_id;

    return v_ceiling;
end;
$$;

comment on function lock_run_cost_ceiling(uuid) is
    'Computes and locks the per-run cost ceiling at the start of a pipeline run. '
    'Reads monthly_api_budget_usd / expected_runs_per_month / per_run_cost_ceiling_pct from clients.config.';
