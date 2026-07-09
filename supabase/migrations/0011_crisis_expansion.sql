-- Migration 0011: crisis category expansion, cross-outlet merge tracking, and
-- pinned national statistics.
--
-- 1. New event_type/type values so weather disasters and exam issues stop
--    being lumped into the generic weather_disaster/exam_leak buckets:
--    flood, cyclone, heatwave, weather_alert, suicide_spree. (earthquake,
--    exam_leak, exam_delay already existed and are reused as-is.)
--
-- 2. merge_count / report_count + updated_at: 0010 only stopped an *exact*
--    duplicate headline from minting a second `crises` row; it did nothing
--    for the differently-worded case (e.g. "Heavy rain floods UP" vs "UP
--    flooding hits Lucknow"), and neither table tracked how many outlets/
--    reports had been folded into a row. See src/utils/fuzzy_match.py and
--    supabase_client.find_mergeable_public_event / merge_public_event /
--    bump_crisis_report for the app-side logic that uses these columns.
--
-- 3. pinned_statistics: a small, manually curated table (not scraped) for
--    the "India 2023 Stats" banner atop Crisis Tracker — distinct from the
--    existing `statistics` table, which is an unranked, undeduped dump of
--    whatever Groq extracts from article text at ingest time.
--
-- Run this in the Supabase SQL editor after 0002-0010.

alter table public_events drop constraint if exists public_events_event_type_check;
alter table public_events add constraint public_events_event_type_check check (event_type in (
    'exam_leak', 'student_suicide', 'gender_violence', 'weather_disaster',
    'earthquake', 'ai_tech', 'exam_delay', 'other_crisis',
    'court_case', 'government_policy', 'economy', 'crime', 'technology', 'misc',
    'flood', 'cyclone', 'heatwave', 'weather_alert', 'suicide_spree'
));

alter table crises drop constraint if exists crises_type_check;
alter table crises add constraint crises_type_check check (type in (
    'exam_leak', 'student_suicide', 'gender_violence', 'weather_disaster',
    'earthquake', 'ai_tech', 'exam_delay', 'other_crisis',
    'flood', 'cyclone', 'heatwave', 'weather_alert', 'suicide_spree'
));

alter table public_events add column if not exists merge_count integer not null default 1;

alter table crises add column if not exists report_count integer not null default 1;
alter table crises add column if not exists updated_at timestamptz not null default now();

create table if not exists pinned_statistics (
    id uuid primary key default gen_random_uuid(),
    label text not null,
    value numeric not null,
    unit text,
    year integer not null,
    source text not null,
    source_url text,
    category text not null check (category in (
        'student_welfare', 'gender_violence', 'disaster', 'education', 'crime'
    )),
    display_order integer not null default 0,
    active boolean not null default true,
    updated_at timestamptz not null default now()
);

create index if not exists pinned_statistics_active_idx on pinned_statistics (active, display_order);

alter table pinned_statistics enable row level security;

create policy "Public read access" on pinned_statistics for select using (true);

-- Seed the two figures requested for the initial banner. source_url is left
-- null pending a verified citation link (see project plan) — fill in once
-- confirmed rather than shipping a placeholder link.
insert into pinned_statistics (label, value, unit, year, source, category, display_order) values
    ('Student Suicides', 13892, 'cases', 2023, 'NCRB', 'student_welfare', 10),
    ('Rape Cases', 29670, 'cases', 2023, 'NCRB', 'gender_violence', 20);
