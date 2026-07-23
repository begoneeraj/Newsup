-- Migration 0019: 5-year NCRB ADSI history for total and student suicides.
--
-- Deliberately a separate table from pinned_statistics (0011/0017/0018):
-- pinned_statistics holds a single current-year figure per label for the
-- always-visible Crisis Tracker banner. This table holds a multi-year
-- series for a detail screen that is NOT pinned or shown on any main feed —
-- it's reachable only via a low-key entry point (see
-- lib/src/screens/national_data_screen.dart), since suicide statistics are
-- sensitive content that shouldn't be the first thing users see.
--
-- Manually curated, annually updated, same as pinned_statistics — NCRB is
-- the only official source and publishes once a year with a 1-2 year lag.
-- Do NOT build a fetcher/cron job for this. Add a row per category when the
-- next ADSI report comes out.

create table if not exists suicide_stats_history (
    id uuid primary key default gen_random_uuid(),
    category text not null check (category in ('total_suicides', 'student_suicides')),
    year integer not null,
    value integer not null,
    source text not null default 'NCRB ADSI',
    source_url text,
    created_at timestamptz not null default now(),
    unique (category, year)
);

create index if not exists suicide_stats_history_category_year_idx on suicide_stats_history (category, year);

alter table suicide_stats_history enable row level security;

drop policy if exists "Public read access" on suicide_stats_history;
create policy "Public read access" on suicide_stats_history for select using (true);

insert into suicide_stats_history (category, year, value, source, source_url) values
    ('total_suicides', 2020, 153052, 'NCRB ADSI 2020', 'https://ncrb.gov.in'),
    ('total_suicides', 2021, 164033, 'NCRB ADSI 2021', 'https://ncrb.gov.in'),
    ('total_suicides', 2022, 170924, 'NCRB ADSI 2022', 'https://ncrb.gov.in'),
    ('total_suicides', 2023, 171418, 'NCRB ADSI 2023', 'https://ncrb.gov.in'),
    ('total_suicides', 2024, 170746, 'NCRB ADSI 2024', 'https://ncrb.gov.in'),
    ('student_suicides', 2020, 12526, 'NCRB ADSI 2020', 'https://ncrb.gov.in'),
    ('student_suicides', 2021, 13089, 'NCRB ADSI 2021', 'https://ncrb.gov.in'),
    ('student_suicides', 2022, 13044, 'NCRB ADSI 2022', 'https://ncrb.gov.in'),
    ('student_suicides', 2023, 13892, 'NCRB ADSI 2023', 'https://ncrb.gov.in'),
    ('student_suicides', 2024, 14488, 'NCRB ADSI 2024', 'https://ncrb.gov.in')
on conflict (category, year) do update set
    value = excluded.value,
    source = excluded.source,
    source_url = excluded.source_url;
