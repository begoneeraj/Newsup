-- Tables backing FactCheckSchema / CrisisReportSchema (see src/models/schemas.py),
-- which mirror lib/src/models/fact_check.dart and lib/src/models/crisis_report.dart.
-- Run this once in the Supabase SQL editor before the pipeline's first cron run.

create extension if not exists "pgcrypto";

create table if not exists fact_checks (
    id uuid primary key default gen_random_uuid(),
    claim_text text not null,
    origin text not null,
    status text not null check (
        status in ('VERIFIED', 'FALSE', 'MISLEADING', 'PARTLY_TRUE', 'OUT_OF_CONTEXT', 'SATIRE', 'UNVERIFIED')
    ),
    evidence_confidence integer not null check (evidence_confidence between 0 and 100),
    source_reliability text not null check (source_reliability in ('HIGH', 'MED', 'LOW')),
    independent_confirmations integer not null default 0,
    official_confirmation boolean not null default false,
    sources jsonb not null default '[]',
    expert_analysis text,
    genz_summary text,
    source_url text not null default '',
    created_at timestamptz not null default now()
);

create index if not exists fact_checks_source_url_idx on fact_checks (source_url);
create index if not exists fact_checks_claim_text_idx on fact_checks (claim_text);

create table if not exists crisis_reports (
    id uuid primary key default gen_random_uuid(),
    title text not null,
    status text not null default 'UNRESOLVED' check (
        status in ('UNRESOLVED', 'PARTIALLY_RESOLVED', 'RESOLVED')
    ),
    event_start_date timestamptz not null,
    remedial_actions_count integer not null default 0,
    rti_filings_total integer not null default 0,
    rti_filings_answered integer not null default 0,
    timeline_events jsonb not null default '[]',
    evidence_items jsonb not null default '[]',
    source_url text not null default '',
    created_at timestamptz not null default now()
);

create index if not exists crisis_reports_source_url_idx on crisis_reports (source_url);
create index if not exists crisis_reports_title_idx on crisis_reports (title);

-- The Flutter app reads with the anon key, which is safe to ship in a client
-- build only because these policies restrict it to read-only. The pipeline
-- writes with the service-role key, which bypasses RLS entirely.
alter table fact_checks enable row level security;
alter table crisis_reports enable row level security;

create policy "Public read access" on fact_checks
    for select using (true);

create policy "Public read access" on crisis_reports
    for select using (true);
