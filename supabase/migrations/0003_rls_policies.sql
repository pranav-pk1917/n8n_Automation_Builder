-- =============================================================================
-- Migration: 0003_rls_policies
-- Row Level Security: every table with a client_id column requires the
-- requesting auth user to be a member of that client.
--
-- n8n connects with the service_role key, which BYPASSES RLS by design.
-- RLS is enforced for any future user-facing access (dashboard, intern logins).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Helper function: does the current auth user belong to client_id?
-- -----------------------------------------------------------------------------

create or replace function auth_user_is_member_of(p_client_id uuid)
returns boolean
language sql
security definer
stable
as $$
    select exists (
        select 1
          from client_members
         where client_members.client_id = p_client_id
           and client_members.auth_user_id = auth.uid()
    );
$$;

comment on function auth_user_is_member_of(uuid) is
    'Returns true if the current Supabase auth user is a member of the given client. '
    'Used by RLS policies. SECURITY DEFINER because client_members itself is RLS-protected.';

-- -----------------------------------------------------------------------------
-- Enable RLS on every client-scoped table
-- -----------------------------------------------------------------------------

alter table clients                       enable row level security;
alter table client_members                enable row level security;
alter table services                      enable row level security;
alter table niches                        enable row level security;
alter table seed_keywords                 enable row level security;
alter table competitors                   enable row level security;
alter table competitor_brand_names        enable row level security;
alter table pipeline_runs                 enable row level security;
alter table raw_keywords                  enable row level security;
alter table negative_terms                enable row level security;
alter table positive_terms                enable row level security;
alter table gold_examples                 enable row level security;
alter table keyword_classifications       enable row level security;
alter table clusters                      enable row level security;
alter table keyword_cluster_map           enable row level security;
alter table pages                         enable row level security;
alter table api_cost_log                  enable row level security;
alter table human_reviews                 enable row level security;
alter table quality_audits                enable row level security;
alter table cross_validation_events       enable row level security;
alter table taxonomy_suggestions          enable row level security;
alter table briefs                        enable row level security;
alter table drafts                        enable row level security;
alter table distribution_posts            enable row level security;
alter table gsc_metrics                   enable row level security;

-- -----------------------------------------------------------------------------
-- clients table: a user can see clients they are a member of
-- -----------------------------------------------------------------------------

create policy clients_member_select on clients
    for select using ( auth_user_is_member_of(id) );

create policy clients_owner_update on clients
    for update using (
        exists (
            select 1 from client_members
             where client_members.client_id = clients.id
               and client_members.auth_user_id = auth.uid()
               and client_members.role in ('owner', 'admin')
        )
    );

-- INSERT/DELETE of clients is service-role only (handled by n8n during onboarding).

-- -----------------------------------------------------------------------------
-- client_members: a user can see their own memberships
-- -----------------------------------------------------------------------------

create policy client_members_self on client_members
    for select using ( auth_user_id = auth.uid() );

create policy client_members_owner_manage on client_members
    for all using (
        exists (
            select 1 from client_members cm
             where cm.client_id = client_members.client_id
               and cm.auth_user_id = auth.uid()
               and cm.role in ('owner', 'admin')
        )
    );

-- -----------------------------------------------------------------------------
-- Generic per-client policies for the remaining tables
-- (read access by membership; writes by service-role or admin/editor)
-- -----------------------------------------------------------------------------

-- We use a do-block to apply consistent policies to a list of tables.

do $$
declare
    t_name text;
    read_tables text[] := array[
        'services','niches','seed_keywords','competitors','competitor_brand_names',
        'pipeline_runs','raw_keywords','negative_terms','positive_terms','gold_examples',
        'keyword_classifications','clusters','pages','api_cost_log','human_reviews',
        'quality_audits','cross_validation_events','taxonomy_suggestions',
        'briefs','drafts','distribution_posts','gsc_metrics'
    ];
begin
    foreach t_name in array read_tables loop
        execute format(
            'create policy %I_member_select on %I for select using ( auth_user_is_member_of(client_id) )',
            t_name || '_member_select', t_name
        );
    end loop;
end;
$$;

-- keyword_cluster_map has no client_id directly; join via clusters.
create policy keyword_cluster_map_member_select on keyword_cluster_map
    for select using (
        exists (
            select 1 from clusters
             where clusters.id = keyword_cluster_map.cluster_id
               and auth_user_is_member_of(clusters.client_id)
        )
    );

-- -----------------------------------------------------------------------------
-- Notes on write policies
-- -----------------------------------------------------------------------------

-- In Phase 1, all writes go through n8n using the service_role key (which
-- bypasses RLS). User-facing write paths will be added in Phase 2 with the
-- in-app dashboard. At that point we'll add per-table INSERT/UPDATE policies
-- gated on client_members.role in ('admin','editor').

-- For now, SELECT policies are sufficient to enable a future dashboard to
-- render data without surfacing cross-tenant leaks even if the service role
-- accidentally exposes a query path.
