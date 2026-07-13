-- Migration 0014: Science & Research module, Data Stories module, Slow
-- Crises trend-tracking module, and a feed_suppressed flag for the NEET
-- daily-quota gate (see main.py::NEET_DAILY_QUOTA / _is_neet_item).
--
-- Design notes:
-- * science_research_reports / data_stories are one-shot extractions
--   (article/story write-ups), deduped by headline_hash -- same convention
--   0012 established for student_crisis_reports/ai_tech_reports. Neither
--   is a living record that gets updated over time the way govt_promises/
--   court_cases are, so no slug-based upsert is needed.
-- * slow_crises IS a living record (keyed on crisis_slug, like
--   govt_promises.project_slug), because a tracked crisis's severity
--   changes over time as new data comes in -- see
--   src/pipeline/slow_crisis_quant.py::_compute_severity. The number
--   backing that severity must never come from Groq, only from the
--   official dataset each Track 1 job pulls; crisis_data_points is the
--   append-only quantitative trail that severity is computed FROM.
-- * crisis_data_points / crisis_narrative_updates FK to slow_crises.id
--   (not to a headline table), same FK-to-parent-id shape 0013 used for
--   promise_evidence -> govt_promises.id.
-- * feed_suppressed defaults to false and in practice stays false for
--   every row that's actually inserted, since the NEET quota gate in
--   main.py skips over-quota items *before* the Groq call entirely
--   (nothing is ever inserted with feed_suppressed=true this way) --
--   the column exists for forward-compatibility if that gate's behavior
--   changes to "insert but hide" later, not because current code sets it.
--
-- Run this in the Supabase SQL editor after 0002-0013.

alter table student_crisis_reports
    add column if not exists feed_suppressed boolean not null default false;

create index if not exists student_crisis_reports_feed_suppressed_idx
    on student_crisis_reports (feed_suppressed);

create table if not exists science_research_reports (
    id uuid primary key default gen_random_uuid(),
    headline_hash text unique,
    headline_plain text not null,
    genz_summary text,
    field text not null check (field in (
        'space', 'biology', 'physics', 'chemistry', 'environment',
        'medicine', 'materials', 'other'
    )),
    institution text,
    india_relevance boolean not null default false,
    what_this_means text,
    key_facts jsonb not null default '[]',
    source_url text not null default '',
    processed_at timestamptz not null default now()
);

create index if not exists science_research_reports_headline_hash_idx
    on science_research_reports (headline_hash);
create index if not exists science_research_reports_field_idx
    on science_research_reports (field);

create table if not exists data_stories (
    id uuid primary key default gen_random_uuid(),
    headline_hash text unique,
    slug text,
    title text not null,
    genz_title text,
    dataset_source text not null,
    headline_stat text,
    narrative_summary text not null,
    genz_summary text,
    chart_data jsonb not null default '[]',
    published_at timestamptz not null default now()
);

create index if not exists data_stories_headline_hash_idx on data_stories (headline_hash);

create table if not exists slow_crises (
    id uuid primary key default gen_random_uuid(),
    crisis_slug text unique not null,
    title text not null,
    category text not null check (category in (
        'water', 'air_pollution', 'groundwater', 'healthcare_capacity',
        'education_dropout', 'judiciary_delay', 'infrastructure',
        'housing_affordability'
    )),
    region text,
    description text,
    genz_description text,
    current_severity text check (current_severity in (
        'stable', 'worsening', 'improving', 'critical'
    )),
    last_computed_at timestamptz,
    data_source text
);

create index if not exists slow_crises_category_idx on slow_crises (category);

create table if not exists crisis_data_points (
    id uuid primary key default gen_random_uuid(),
    crisis_id uuid not null references slow_crises (id) on delete cascade,
    value numeric not null,
    unit text not null,
    recorded_date date not null,
    source_url text not null default '',
    note text,
    created_at timestamptz not null default now()
);

create index if not exists crisis_data_points_crisis_id_idx
    on crisis_data_points (crisis_id, recorded_date desc);

create table if not exists crisis_narrative_updates (
    id uuid primary key default gen_random_uuid(),
    crisis_id uuid not null references slow_crises (id) on delete cascade,
    headline_hash text unique,
    narrative text not null,
    genz_narrative text,
    source_url text not null default '',
    generated_at timestamptz not null default now()
);

create index if not exists crisis_narrative_updates_crisis_id_idx
    on crisis_narrative_updates (crisis_id, generated_at desc);
create index if not exists crisis_narrative_updates_headline_hash_idx
    on crisis_narrative_updates (headline_hash);

-- RLS: same pattern as 0012/0013 -- anon (app) key read-only, pipeline
-- writes with the service-role key which bypasses RLS.
alter table science_research_reports enable row level security;
alter table data_stories enable row level security;
alter table slow_crises enable row level security;
alter table crisis_data_points enable row level security;
alter table crisis_narrative_updates enable row level security;

create policy "Public read access" on science_research_reports for select using (true);
create policy "Public read access" on data_stories for select using (true);
create policy "Public read access" on slow_crises for select using (true);
create policy "Public read access" on crisis_data_points for select using (true);
create policy "Public read access" on crisis_narrative_updates for select using (true);
