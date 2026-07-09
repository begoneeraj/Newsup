-- Migration 0012: four new expansion modules — student crisis, AI & tech,
-- government promises tracker, court case tracker. See
-- truthlens_expansion_prompt.md (Parts 1-6) and src/ai_processor/groq_processor.py
-- / src/main.py::route_expansion_module / src/database/supabase_client.py.
--
-- Adapted from the source spec: the spec's tables FK source_headline_id to a
-- `news_headlines` table that doesn't exist in this project. Every other
-- table in this codebase dedupes on a `headline_hash` text column instead
-- (see 0007_rate_limiting_and_headline_hash.sql, 0010_crises_headline_hash.sql)
-- so that convention is used here too.
--
-- student_crisis_reports / ai_tech_reports are one-shot article extractions,
-- deduped by headline_hash (like `crises`/`statistics`).
-- govt_promises / court_cases are living records updated over time, keyed on
-- project_slug / case_slug respectively (see supabase_client.upsert_govt_promise
-- / upsert_court_case).
--
-- Run this in the Supabase SQL editor after 0002-0011.

create table if not exists student_crisis_reports (
    id uuid primary key default gen_random_uuid(),
    exam_or_context text not null,
    crisis_type text not null check (crisis_type in (
        'paper_leak', 'suicide', 'protest', 'coaching_misconduct',
        'university_action', 'scholarship', 'mental_health', 'other'
    )),
    severity text not null check (severity in ('critical', 'high', 'medium', 'low')),
    affected_count integer,
    state text,
    institution text,
    government_response text,
    student_demand text,
    court_involvement boolean not null default false,
    fact_check_flag boolean not null default false,
    headline_plain text not null,
    headline_genz text,
    key_facts jsonb not null default '[]',
    missing_info text,
    next_step_to_watch text not null,
    source_url text not null default '',
    headline_hash text,
    processed_at timestamptz not null default now()
);

create index if not exists student_crisis_reports_headline_hash_idx on student_crisis_reports (headline_hash);
create index if not exists student_crisis_reports_crisis_type_idx on student_crisis_reports (crisis_type);
create index if not exists student_crisis_reports_severity_idx on student_crisis_reports (severity);

create table if not exists ai_tech_reports (
    id uuid primary key default gen_random_uuid(),
    tech_category text not null check (tech_category in (
        'ai_model', 'ai_policy', 'semiconductor', 'funding', 'deepfake',
        'india_ai_mission', 'robotics', 'data_centre', 'big_tech', 'incident', 'other'
    )),
    india_relevance boolean not null default false,
    india_angle text,
    companies_involved jsonb not null default '[]',
    countries_involved jsonb not null default '[]',
    claim_type text not null check (claim_type in (
        'launch', 'regulation', 'funding', 'controversy', 'research',
        'acquisition', 'ban', 'other'
    )),
    hype_check text not null check (hype_check in ('overhyped', 'neutral', 'understated')),
    technical_accuracy text not null check (technical_accuracy in (
        'accurate', 'minor_errors', 'misleading', 'cannot_verify'
    )),
    headline_plain text not null,
    headline_genz text,
    key_facts jsonb not null default '[]',
    what_this_means_for_india text not null,
    next_milestone text,
    sources_to_verify jsonb not null default '[]',
    source_url text not null default '',
    headline_hash text,
    processed_at timestamptz not null default now()
);

create index if not exists ai_tech_reports_headline_hash_idx on ai_tech_reports (headline_hash);
create index if not exists ai_tech_reports_tech_category_idx on ai_tech_reports (tech_category);
create index if not exists ai_tech_reports_india_relevance_idx on ai_tech_reports (india_relevance);

create table if not exists govt_promises (
    id uuid primary key default gen_random_uuid(),
    project_name text not null,
    project_slug text unique,
    category text not null check (category in (
        'metro', 'highway', 'smart_city', 'ai_mission', 'semiconductor',
        'social_scheme', 'defence', 'budget_allocation', 'election_promise', 'other'
    )),
    announcing_body text not null,
    state_or_national text not null check (state_or_national in ('national', 'state')),
    state text,
    announced_date date,
    promised_completion_date date,
    revised_completion_date date,
    current_status text not null check (current_status in (
        'announced', 'started', 'ongoing', 'delayed', 'stalled', 'completed', 'cancelled'
    )),
    budget_allocated_crore numeric,
    budget_spent_crore numeric,
    broken_promise_flag boolean not null default false,
    broken_promise_detail text,
    beneficiaries text,
    headline_plain text not null,
    ai_summary text not null,
    key_facts jsonb not null default '[]',
    next_milestone text,
    verification_sources jsonb not null default '[]',
    source_url text not null default '',
    headline_hash text,
    last_updated timestamptz not null default now()
);

create index if not exists govt_promises_category_idx on govt_promises (category);
create index if not exists govt_promises_current_status_idx on govt_promises (current_status);
create index if not exists govt_promises_broken_promise_flag_idx on govt_promises (broken_promise_flag);

create table if not exists court_cases (
    id uuid primary key default gen_random_uuid(),
    case_title text not null,
    case_number text,
    case_slug text unique,
    is_new_case boolean not null default true,
    court text not null check (court in (
        'supreme_court', 'high_court', 'ngt', 'nclt', 'nclat', 'cbi_court', 'other'
    )),
    high_court_state text,
    case_category text not null check (case_category in (
        'constitutional', 'criminal', 'environmental', 'corporate',
        'electoral', 'pil', 'service_matter', 'other'
    )),
    petitioner text not null,
    respondent text not null,
    core_legal_question text not null,
    petitioner_argument text not null,
    respondent_argument text,
    last_hearing_date date,
    last_hearing_outcome text,
    next_hearing_date date,
    current_order text,
    key_documents jsonb not null default '[]',
    impact_if_petitioner_wins text not null,
    impact_if_respondent_wins text not null,
    headline_plain text not null,
    ai_summary text not null,
    key_facts jsonb not null default '[]',
    follow_up_trigger text,
    source_url text not null default '',
    headline_hash text,
    last_updated timestamptz not null default now()
);

create index if not exists court_cases_court_idx on court_cases (court);
create index if not exists court_cases_case_category_idx on court_cases (case_category);
create index if not exists court_cases_next_hearing_date_idx on court_cases (next_hearing_date);

-- RLS: same pattern as 0006/0007/0008 — anon (app) key gets read-only
-- access, the pipeline writes with the service-role key which bypasses RLS.
alter table student_crisis_reports enable row level security;
alter table ai_tech_reports enable row level security;
alter table govt_promises enable row level security;
alter table court_cases enable row level security;

create policy "Public read access" on student_crisis_reports for select using (true);
create policy "Public read access" on ai_tech_reports for select using (true);
create policy "Public read access" on govt_promises for select using (true);
create policy "Public read access" on court_cases for select using (true);
