-- Migration 0009: public_events — a generalized, dual-written aggregation
-- layer over fact_checks / crisis_reports / crises (see
-- src/pipeline/public_events.py). Does NOT replace those tables; they keep
-- working exactly as before. This is Phase 1 of a larger "Public Events"
-- roadmap (see project plan) — schema only, populated starting in Phase 2.
--
-- event_type is intentionally a trimmed subset of a much larger eventual
-- vocabulary: the 8 existing `crises.type` values plus a handful of general
-- buckets. Extend the check constraint in a later migration once a phase
-- actually produces a new type — cheap to do, not worth over-provisioning now.
--
-- No lat/lon: geocoding is out of scope until a real map feature exists.
--
-- Run this in the Supabase SQL editor after 0002-0008.

create table if not exists public_events (
    id uuid primary key default gen_random_uuid(),
    title text not null,
    summary text not null,

    event_type text not null check (event_type in (
        'exam_leak', 'student_suicide', 'gender_violence', 'weather_disaster',
        'earthquake', 'ai_tech', 'exam_delay', 'other_crisis',
        'court_case', 'government_policy', 'economy', 'crime', 'technology', 'misc'
    )),
    category text,
    subcategory text,

    importance_score integer check (importance_score between 0 and 100),
    severity text check (severity in ('low', 'medium', 'high')),
    status text check (status in ('ongoing', 'resolved', 'developing')),

    country text default 'India',
    state text,
    district text,
    city text,

    start_date timestamptz,
    end_date timestamptz,
    last_updated timestamptz not null default now(),

    confidence float check (confidence between 0 and 1),

    official_sources jsonb not null default '[]',
    media_sources jsonb not null default '[]',
    reddit_sources jsonb not null default '[]',
    youtube_sources jsonb not null default '[]',

    timeline jsonb not null default '[]',
    tags text[] not null default '{}',
    keywords text[] not null default '{}',

    embedding vector(384),
    related_events uuid[] not null default '{}',

    image_url text,
    notification_sent boolean not null default false,
    verified boolean not null default false,

    -- Provenance / idempotent dual-write key — see insert_public_event in
    -- src/database/supabase_client.py.
    source_table text check (source_table in ('fact_checks', 'crisis_reports', 'crises')),
    source_id uuid,
    headline_hash text,
    source_url text,
    unique (source_table, source_id),

    created_at timestamptz not null default now()
);

create index if not exists public_events_event_type_idx on public_events (event_type);
create index if not exists public_events_severity_idx on public_events (severity);
create index if not exists public_events_status_idx on public_events (status);
create index if not exists public_events_source_idx on public_events (source_table, source_id);

-- Same ivfflat cosine-similarity index as fact_checks/crisis_reports (0002).
create index if not exists public_events_embedding_idx
    on public_events using ivfflat (embedding vector_cosine_ops) with (lists = 50);

-- Same shape as match_fact_checks / match_crisis_reports (0002), retargeted.
create or replace function match_public_events(
    query_embedding vector(384),
    match_threshold float,
    match_count int
)
returns table (id uuid, title text, similarity float)
language sql stable
as $$
    select
        public_events.id,
        public_events.title,
        1 - (public_events.embedding <=> query_embedding) as similarity
    from public_events
    where 1 - (public_events.embedding <=> query_embedding) > match_threshold
    order by similarity desc
    limit match_count;
$$;

-- RLS: same house style as every other table — anon (app) key gets
-- read-only access, the pipeline writes with the service-role key which
-- bypasses RLS entirely.
alter table public_events enable row level security;

create policy "Public read access" on public_events for select using (true);
