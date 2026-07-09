-- Migration 0008: crisis-classifier tags (`crises`) and extracted
-- quantitative statistics (`statistics`) — two new, additive tables backing
-- the crisis classifier (MODEL_COMPLEX) and stats extractor (MODEL_FAST)
-- prompts in src/ai_processor/groq_processor.py, routed via
-- main.route_article(). Independent of the existing fact_checks /
-- crisis_reports pipeline: `crises` is a lightweight type/severity/tag
-- classification (not the RTI/timeline-driven crisis_reports), and
-- `statistics` has no analogue elsewhere.
--
-- Run this in the Supabase SQL editor after 0002-0007.

create table if not exists crises (
    id uuid primary key default gen_random_uuid(),
    type text not null check (type in (
        'exam_leak', 'student_suicide', 'gender_violence', 'weather_disaster',
        'earthquake', 'ai_tech', 'exam_delay', 'other_crisis'
    )),
    title text not null,
    severity text not null check (severity in ('low', 'medium', 'high')),
    status text not null check (status in ('ongoing', 'resolved', 'developing')),
    trigger_keyword text,
    tags text[] not null default '{}',
    description text not null,
    affects_students boolean not null default false,
    source_headline text not null default '',
    created_at timestamptz not null default now()
);

create index if not exists crises_type_idx on crises (type);
create index if not exists crises_severity_idx on crises (severity);

create table if not exists statistics (
    id uuid primary key default gen_random_uuid(),
    metric text not null,
    value numeric not null,
    year integer,
    source text not null,
    category text not null check (category in (
        'student_welfare', 'gender_violence', 'disaster', 'education', 'ai_adoption'
    )),
    created_at timestamptz not null default now()
);

create index if not exists statistics_category_idx on statistics (category);
create index if not exists statistics_metric_idx on statistics (metric);

-- RLS: same pattern as 0006/0007 — anon (app) key gets read-only access, the
-- pipeline writes with the service-role key which bypasses RLS entirely.
alter table crises enable row level security;
alter table statistics enable row level security;

create policy "Public read access" on crises for select using (true);
create policy "Public read access" on statistics for select using (true);
