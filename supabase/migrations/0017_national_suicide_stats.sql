-- Migration 0017: national suicide stats for the pinned-statistics banner.
--
-- Extends the pinned_statistics table (originally defined in
-- supabase/migrations/0011_crisis_expansion.sql) rather than adding a new
-- table: pinned_statistics already exists for exactly this purpose ("a
-- small, manually curated table (not scraped)" of headline NCRB figures).
-- A separate national_stats table would just be a second copy of the same
-- mechanism.
--
-- This migration recreates the 0011 pinned_statistics table/policy/seed
-- with `create table if not exists` / `drop ... if exists` guards, because
-- this project's live database turned out to be missing pinned_statistics
-- even though tables from several migrations after 0011 (0012-0014) are
-- present — 0011 apparently never fully applied. Re-running the 0011 block
-- here is a no-op if pinned_statistics already exists with rows; if not, it
-- brings the table up to the same state 0011 was supposed to leave it in
-- before applying the actual 0017 changes below.
--
-- 0017 proper, on top of that baseline:
-- 1. Adds 'public_health' to the category check constraint so an all-India
--    (not student-specific) suicide figure has a category that actually
--    describes it — the existing values (student_welfare, gender_violence,
--    disaster, education, crime) don't fit.
-- 2. Inserts the Total Suicides row.
-- 3. Backfills source_url/source on the Student Suicides row, which shipped
--    in 0011 with source_url left null "pending a verified citation link"
--    — NCRB's site is that citation.
--
-- IMPORTANT: pinned_statistics is a manually-curated, annually-updated table.
-- NCRB publishes the ADSI report once a year, so there is nothing to poll or
-- scrape on any shorter cycle. Do NOT build a fetcher/cron job for this data
-- — update this table by hand (a new migration, or a direct SQL edit) when
-- the next year's ADSI report is out.
--
-- Run this in the Supabase SQL editor. Safe to run whether or not 0011 ever
-- applied.

-- --- 0011 baseline (recreated defensively) ---------------------------------

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

drop policy if exists "Public read access" on pinned_statistics;
create policy "Public read access" on pinned_statistics for select using (true);

insert into pinned_statistics (label, value, unit, year, source, category, display_order)
select 'Student Suicides', 13892, 'cases', 2023, 'NCRB', 'student_welfare', 10
where not exists (select 1 from pinned_statistics where label = 'Student Suicides');

insert into pinned_statistics (label, value, unit, year, source, category, display_order)
select 'Rape Cases', 29670, 'cases', 2023, 'NCRB', 'gender_violence', 20
where not exists (select 1 from pinned_statistics where label = 'Rape Cases');

-- --- 0017 changes -----------------------------------------------------------

alter table pinned_statistics drop constraint if exists pinned_statistics_category_check;
alter table pinned_statistics add constraint pinned_statistics_category_check check (category in (
    'student_welfare', 'gender_violence', 'disaster', 'education', 'crime', 'public_health'
));

insert into pinned_statistics (label, value, unit, year, source, source_url, category, display_order)
select 'Total Suicides', 171418, 'cases', 2023, 'NCRB ADSI 2023', 'https://ncrb.gov.in', 'public_health', 5
where not exists (select 1 from pinned_statistics where label = 'Total Suicides');

update pinned_statistics
set source_url = 'https://ncrb.gov.in', source = 'NCRB ADSI 2023'
where label = 'Student Suicides' and source_url is null;
