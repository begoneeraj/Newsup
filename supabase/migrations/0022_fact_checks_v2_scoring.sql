-- Migration 0022: adds combined fake-probability scoring
-- (ml.fake_probability.calculate_fake_probability) to fact_checks_v2.
--
-- scoring_breakdown stores the full dict returned by calculate_fake_probability
-- (fake_probability, label, source_credibility, content_score,
-- corroboration_score) so the individual signals stay inspectable even
-- though credibility_label/fake_probability are also broken out into their
-- own columns for querying/filtering.
--
-- fact_checks_v2 itself turned out to be missing from this project's live
-- database even though migration 0006 (which creates it) predates this one —
-- the same "migration never fully applied" situation noted in migration
-- 0017's header re: pinned_statistics. So this recreates the 0006
-- fact_checks_v2 table/index/policy with `if not exists` guards first (a
-- no-op if 0006 did apply), then adds the 0022 columns on top. Requires
-- fact_checks (0001/schema.sql) to already exist, since fact_checks_v2
-- references it.
--
-- Run this in the Supabase SQL editor.

-- --- 0006 baseline (recreated defensively) ---------------------------------

create table if not exists fact_checks_v2 (
    id uuid primary key default gen_random_uuid(),
    fact_check_id uuid not null unique references fact_checks(id) on delete cascade,
    claim text not null,
    status text not null check (status in ('VERIFIED', 'DISPUTED', 'NEEDS_MORE_INFO')),
    evidence jsonb not null default '[]',
    verdict text not null,
    confidence float not null check (confidence between 0 and 1),
    perspectives jsonb,
    created_at timestamptz not null default now()
);

create index if not exists fact_checks_v2_fact_check_idx on fact_checks_v2 (fact_check_id);

alter table fact_checks_v2 enable row level security;

drop policy if exists "Public read access" on fact_checks_v2;
create policy "Public read access" on fact_checks_v2 for select using (true);

-- --- 0022 changes -----------------------------------------------------------

alter table fact_checks_v2
    add column if not exists fake_probability float check (fake_probability between 0 and 1),
    add column if not exists credibility_label text check (credibility_label in ('Likely Real', 'Uncertain', 'Likely Fake')),
    add column if not exists scoring_breakdown jsonb;
