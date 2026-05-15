# Supabase

This directory holds the Postgres schema, RLS policies, and helper functions for the SEO-Tools keyword pipeline.

## Setup

1. Create a **new** Supabase project (NOT shared with any client-facing site).
2. Run migrations in order:

```bash
# From repo root
supabase db push --linked
# OR using psql directly:
psql "$SUPABASE_DB_URL" -f supabase/migrations/0001_initial_schema.sql
psql "$SUPABASE_DB_URL" -f supabase/migrations/0002_pgvector.sql
psql "$SUPABASE_DB_URL" -f supabase/migrations/0003_rls_policies.sql
psql "$SUPABASE_DB_URL" -f supabase/migrations/0004_indexes.sql
```

3. Install Postgres functions:

```bash
psql "$SUPABASE_DB_URL" -f supabase/functions/apply_tier0_regex_filter.sql
psql "$SUPABASE_DB_URL" -f supabase/functions/apply_tier0_competitor_navigational_filter.sql
psql "$SUPABASE_DB_URL" -f supabase/functions/compute_priority_score.sql
psql "$SUPABASE_DB_URL" -f supabase/functions/check_cost_ceiling.sql
```

4. (Optional, for development) Load seed data:

```bash
psql "$SUPABASE_DB_URL" -f supabase/seed/dummy_clients.sql
```

## Conventions

- Migrations are **forward-only and numbered**. Never edit a shipped migration; write a new one.
- All tables that contain client-scoped data have a `client_id` column and an RLS policy referencing `client_members`.
- All functions are `SECURITY DEFINER` only when they need to bypass RLS (and are owned by a privileged role). Default to `SECURITY INVOKER`.
- All enums are named in the migration that introduces them; never inline enum-by-CHECK constraints.

## Directory layout

```
supabase/
  migrations/        forward-only schema changes
  functions/         reusable Postgres functions (filters, scoring, guards)
  policies/          (reserved) standalone RLS policies if we ever split them from migrations
  seed/              development seed data
  README.md          this file
```

## Backup strategy

Daily point-in-time-recovery is enabled by default on Supabase paid plans. For free-tier projects, schedule a manual `pg_dump` daily via n8n.

## When extracting to its own repo

The migrations are self-contained — running them on a fresh Supabase project recreates the entire schema. No external dependencies.
