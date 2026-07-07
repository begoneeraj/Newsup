-- Migration 0007: rate-limit tracking for the new metered news APIs
-- (NewsData.io, Mediastack) and a fast exact-match dedup pre-filter ahead of
-- the existing pgvector semantic dedup (0002_pgvector_dedup.sql).
--
-- Run this in the Supabase SQL editor after 0002-0006.

-- ---------------------------------------------------------------------------
-- rate_limit_tracking: one row per metered source, read/written by
-- src/database/rate_limiter.py. reset_at is a rolling 24h window from the
-- first call after the last reset — good enough for a daily-quota API; for
-- Mediastack's monthly quota the pipeline tracks a conservative daily slice
-- (see rate_limiter.py) rather than a true monthly window.
-- ---------------------------------------------------------------------------

create table if not exists rate_limit_tracking (
    id uuid primary key default gen_random_uuid(),
    source_name text not null unique,
    calls_used int not null default 0,
    daily_limit int not null,
    reset_at timestamptz not null default now() + interval '1 day',
    updated_at timestamptz not null default now()
);

-- Backend-only table (the pipeline writes with the service-role key, which
-- bypasses RLS). No policies means the anon key used by the Flutter app gets
-- zero access, same deny-by-default posture as every other table here.
alter table rate_limit_tracking enable row level security;

-- ---------------------------------------------------------------------------
-- headline_hash: sha256 of the normalized headline (see
-- src/utils/headline_hash.py), checked before spending an embedding
-- computation or Groq call. Nullable + unique so existing rows stay valid;
-- a duplicate hash insert is treated as a merge candidate, same as the
-- embedding-based path in main.py.
-- ---------------------------------------------------------------------------

alter table fact_checks add column if not exists headline_hash text;
alter table crisis_reports add column if not exists headline_hash text;

create unique index if not exists fact_checks_headline_hash_idx
    on fact_checks (headline_hash) where headline_hash is not null;

create unique index if not exists crisis_reports_headline_hash_idx
    on crisis_reports (headline_hash) where headline_hash is not null;
