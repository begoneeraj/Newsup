-- Migration 0024: RLS audit + hardening for the 7 tables added since the
-- schema.sql baseline that hadn't been re-checked as a group:
-- fact_checks_v2, student_crisis_reports, ai_tech_reports, govt_promises,
-- court_cases, publisher_track_record, rate_limit_tracking.
--
-- AUDIT FINDINGS (read against the live migration history before writing
-- this file):
--   fact_checks_v2           -- RLS already enabled (0006, re-asserted 0022).
--                                Public SELECT policy already present. No
--                                INSERT/UPDATE/DELETE policy ever existed.
--   student_crisis_reports   -- RLS already enabled (0012). Public SELECT
--                                policy already present. No write policy.
--   ai_tech_reports          -- RLS already enabled (0012). Public SELECT
--                                policy already present. No write policy.
--   govt_promises            -- RLS already enabled (0012). Public SELECT
--                                policy already present. No write policy.
--   court_cases              -- RLS already enabled (0012). Public SELECT
--                                policy already present. No write policy.
--   publisher_track_record   -- RLS already enabled (0021). Public SELECT
--                                policy already present. No write policy.
--   rate_limit_tracking      -- RLS already enabled (0007). NO policies at
--                                all, i.e. already deny-all to anon
--                                (including SELECT) -- correct, since this
--                                table is an internal Python-pipeline quota
--                                counter (src/database/rate_limiter.py) that
--                                the Flutter app never reads. Left as
--                                deny-all rather than opened up to anon
--                                SELECT: granting read access here would be
--                                pure over-exposure (leaks per-source API
--                                quota usage) with no product need behind
--                                it. If a future admin dashboard needs to
--                                read this table, add a scoped policy then.
--
-- Net result of the audit: no table was missing RLS, and no table had a
-- write policy exposed to anon/authenticated. This migration doesn't change
-- effective behavior; it (a) makes every policy idempotent-safe to rerun,
-- (b) replaces the unscoped `using (true)` SELECT policies (which apply to
-- the Postgres pseudo-role PUBLIC, i.e. every role including anon and
-- authenticated) with policies explicitly scoped `to anon` so intent is
-- visible directly in the policy instead of implied, and (c) adds explicit
-- REVOKE statements as belt-and-suspenders against Supabase's default
-- table-level grants, so a missing/dropped RLS policy can never alone
-- reopen write access -- see "No public INSERT" note below.
--
-- Service-role access (Python backend, src/database/supabase_client.py) is
-- unaffected either way: the service_role Postgres role has BYPASSRLS,
-- so it always has full read/write regardless of any policy here.
--
-- Run this in the Supabase SQL editor after 0002-0023.

-- ---------------------------------------------------------------------------
-- Helper pattern applied to each table below:
--   1. ALTER TABLE ... ENABLE ROW LEVEL SECURITY  (idempotent; no-op if
--      already enabled)
--   2. REVOKE INSERT, UPDATE, DELETE FROM anon, authenticated  (belt and
--      suspenders: even if every policy on the table were dropped tomorrow,
--      these roles still couldn't write without a fresh explicit GRANT)
--   3. DROP POLICY IF EXISTS + CREATE POLICY ... TO anon FOR SELECT
--      (explicit role scope; same read-only behavior as before)
-- No table gets an INSERT/UPDATE/DELETE policy for anon or authenticated —
-- that's rule 3 (no public INSERT under any condition) satisfied by
-- omission, reinforced by the REVOKEs.
-- ---------------------------------------------------------------------------

-- fact_checks_v2 -------------------------------------------------------------
alter table fact_checks_v2 enable row level security;
revoke insert, update, delete on fact_checks_v2 from anon, authenticated;
drop policy if exists "Public read access" on fact_checks_v2;
drop policy if exists "Anon read-only access" on fact_checks_v2;
create policy "Anon read-only access" on fact_checks_v2
    for select to anon, authenticated using (true);

-- student_crisis_reports ------------------------------------------------------
alter table student_crisis_reports enable row level security;
revoke insert, update, delete on student_crisis_reports from anon, authenticated;
drop policy if exists "Public read access" on student_crisis_reports;
drop policy if exists "Anon read-only access" on student_crisis_reports;
create policy "Anon read-only access" on student_crisis_reports
    for select to anon, authenticated using (true);

-- ai_tech_reports --------------------------------------------------------------
alter table ai_tech_reports enable row level security;
revoke insert, update, delete on ai_tech_reports from anon, authenticated;
drop policy if exists "Public read access" on ai_tech_reports;
drop policy if exists "Anon read-only access" on ai_tech_reports;
create policy "Anon read-only access" on ai_tech_reports
    for select to anon, authenticated using (true);

-- govt_promises ------------------------------------------------------------
alter table govt_promises enable row level security;
revoke insert, update, delete on govt_promises from anon, authenticated;
drop policy if exists "Public read access" on govt_promises;
drop policy if exists "Anon read-only access" on govt_promises;
create policy "Anon read-only access" on govt_promises
    for select to anon, authenticated using (true);

-- court_cases ----------------------------------------------------------------
alter table court_cases enable row level security;
revoke insert, update, delete on court_cases from anon, authenticated;
drop policy if exists "Public read access" on court_cases;
drop policy if exists "Anon read-only access" on court_cases;
create policy "Anon read-only access" on court_cases
    for select to anon, authenticated using (true);

-- publisher_track_record ------------------------------------------------------
alter table publisher_track_record enable row level security;
revoke insert, update, delete on publisher_track_record from anon, authenticated;
drop policy if exists "Public read access" on publisher_track_record;
drop policy if exists "Anon read-only access" on publisher_track_record;
create policy "Anon read-only access" on publisher_track_record
    for select to anon, authenticated using (true);

-- rate_limit_tracking ----------------------------------------------------------
-- Deliberately NO select policy for anon/authenticated -- see audit note
-- above. Deny-all to those roles is the intended state, not a gap.
alter table rate_limit_tracking enable row level security;
revoke select, insert, update, delete on rate_limit_tracking from anon, authenticated;

-- ---------------------------------------------------------------------------
-- The three checks below are process/config facts, not something a SQL
-- migration enforces -- recorded here as the result of auditing the rest of
-- the repo alongside these policies, so the full picture lives in one place:
--
--   [x] Flutter uses the Supabase anon/publishable key, not service role.
--       lib/main.dart reads SUPABASE_PUBLISHABLE_KEY via --dart-define at
--       build time; no service-role key or hardcoded JWT appears anywhere
--       under lib/.
--   [x] Service-role key exists only in GitHub Actions secrets + local .env.
--       src/database/supabase_client.py reads SUPABASE_SERVICE_KEY from the
--       environment; every *_cron.yml workflow under .github/workflows/
--       injects it from `secrets.SUPABASE_SERVICE_KEY`; .env is listed in
--       .gitignore and is not tracked in git (only .env.example, which ships
--       blank placeholder values, is committed).
--   [x] No table in this migration grants public/anon INSERT under any
--       condition (see per-table REVOKEs above). The one anon-INSERT policy
--       that exists anywhere in this project is on `device_tokens`
--       (0005_device_tokens.sql, `with check (true)`) -- an intentionally
--       different case (a client registering its own push token, not one of
--       the 7 audited tables here) and out of scope for this migration.
-- ---------------------------------------------------------------------------
