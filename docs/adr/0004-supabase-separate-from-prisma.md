# ADR 0004 — Use a separate Supabase project (not the existing Prisma DB)

Status: **Accepted** (Phase 1 build)

Date: 2026-05-14

## Context

Webley Media's existing Next.js site at `Clinet-Projects/WebleyMedia.com/Next.js_Website_Vercel/Webley-Media/` already uses Prisma against a Postgres DB for:
- Auth via Clerk
- Payments (Stripe, Razorpay, PayPal)
- Client/employee portal (`/portal/*`, `/admin/*`)
- Lead capture
- LMS (`/learn/*`)

Phase 1 of SEO-Tools needs a Postgres database with pgvector for the keyword pipeline.

Tempting option: reuse the existing Prisma DB and add new tables there. Lower setup friction, single DB to manage, joins to existing user/client tables are trivial.

## Decision

Use a **separate Supabase project** dedicated to SEO-Tools. Do not share with the Prisma site DB.

## Reasoning

### Blast radius isolation

The site's Prisma DB serves production traffic (auth, payments, leads). A bug in the keyword pipeline that:
- Locks tables for hours during a large CSV ingest
- Exhausts the connection pool
- Pushes the DB into IOPS saturation during cluster computation
- Triggers a long-running pgvector ANN scan

...would degrade the production site for paying clients.

Separate DB = pipeline issues never affect site availability.

### Different access patterns

- Site DB: high concurrency, small queries, latency-sensitive.
- Pipeline DB: batch workloads, large transactions, throughput-sensitive.

Tuning a single Postgres for both is a compromise. Two DBs let each be tuned for its workload.

### Different security postures

- Site DB: user-owned PII (emails, addresses, payment refs). Strict access control.
- Pipeline DB: keyword research data, no PII (or very limited — client name, domain). Service-role keys used heavily by n8n.

Mixing the two means broader service-role-key exposure across more sensitive data.

### pgvector and RLS

Both can live in either DB. Supabase makes both trivial. The decision is about isolation, not capability.

### Cross-DB reads

If we need to join (e.g., for billing), use:
- Postgres FDW (foreign data wrapper) — read-only cross-DB views
- Application-level joins (n8n fetches from both DBs)
- Periodic sync (export site DB IDs into pipeline DB)

All workable. Far less risky than co-location.

## Consequences

### Positive

- Site DB stays untouched and uncontaminated by pipeline work.
- Pipeline schema can evolve freely without site-deploy coordination.
- Different teams/people can have different access to each DB.
- Future SaaS extraction (Phase 5) is easier — SEO-Tools is already standalone.

### Negative

- Two DBs to back up, monitor, and patch.
- Cross-DB joins require extra work.
- Two sets of Supabase credentials.

Worth it.

## Alternatives considered

### Alternative A: Shared Prisma DB with separate schemas

Rejected. Same Postgres = same connection pool, same IOPS budget. The blast radius isn't actually isolated.

### Alternative B: Add pgvector to Prisma DB

Rejected for the reasons above.

### Alternative C: Self-host Postgres (not Supabase)

Rejected for Phase 1. Supabase gives RLS, Auth, pgvector, Storage, and Edge Functions out of the box for free. Self-hosting wastes engineering time at this scale.

## References

- v3 architecture: `../architecture.md` section 7
- Vercel site Prisma config: `Clinet-Projects/WebleyMedia.com/Next.js_Website_Vercel/Webley-Media/prisma/`
