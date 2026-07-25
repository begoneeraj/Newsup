-- Migration 0015: Underreported Topics module. Compares real official/niche
-- source activity (PRS Legislative bills, sansad.in eLibrary papers, CAG
-- audit reports -- see src/pipeline/underreported_topics.py) against
-- mainstream news volume (Google News RSS + GDELT DOC 2.0 API, including
-- Hindi/Tamil-scoped GDELT counts) for a fixed catalog of real civic
-- topics, and surfaces the ones with the largest coverage gap.
--
-- Same living-record + append-only-points shape 0014 established for
-- slow_crises/crisis_data_points: underreported_topics is keyed on
-- topic_slug and only ever caches the latest gap_score/counts;
-- underreported_topic_points is the full daily history each score/count
-- pair is computed from -- both niche_count/mainstream_count and gap_score
-- are plain arithmetic (see the module's _compute_gap_score), never a Groq
-- guess, same rule 0014's slow_crises module follows.
--
-- Run this in the Supabase SQL editor after 0002-0014.

create table if not exists underreported_topics (
    id uuid primary key default gen_random_uuid(),
    topic_slug text unique not null,
    title text not null,
    data_source text,
    current_gap_score numeric,
    current_niche_count integer,
    current_mainstream_count integer,
    last_computed_at timestamptz
);

create index if not exists underreported_topics_gap_score_idx
    on underreported_topics (current_gap_score desc);

create table if not exists underreported_topic_points (
    id uuid primary key default gen_random_uuid(),
    topic_id uuid not null references underreported_topics (id) on delete cascade,
    recorded_date date not null,
    niche_count integer not null default 0,
    mainstream_count integer not null default 0,
    hindi_mainstream_count integer not null default 0,
    tamil_mainstream_count integer not null default 0,
    gap_score numeric not null default 0,
    states jsonb not null default '[]',
    example_niche_sources jsonb not null default '[]',
    example_mainstream_sources jsonb not null default '[]',
    created_at timestamptz not null default now()
);

create index if not exists underreported_topic_points_topic_id_idx
    on underreported_topic_points (topic_id, recorded_date desc);

-- RLS: same pattern as 0012/0013/0014 -- anon (app) key read-only, pipeline
-- writes with the service-role key which bypasses RLS.
alter table underreported_topics enable row level security;
alter table underreported_topic_points enable row level security;

create policy "Public read access" on underreported_topics for select using (true);
create policy "Public read access" on underreported_topic_points for select using (true);
