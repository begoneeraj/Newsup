-- Migration 0010: dedup for the `crises` table. It previously had no dedup
-- at all (see 0008's comment "no dedup ... a near-duplicate crisis tag is
-- cheap") — in practice this meant the same viral story reported by several
-- outlets minted a fresh `crises` row (and, via dual-write, a fresh
-- public_events row) per outlet, which reads as repeated/duplicate news to
-- an end user even though each row is technically unique. This adds the
-- same fast exact-match headline-hash pre-filter fact_checks/crisis_reports
-- already use (see 0007_rate_limiting_and_headline_hash.sql), checked in
-- main.py before spending a crisis-classification Groq call.
--
-- Run this in the Supabase SQL editor after 0002-0009.

alter table crises add column if not exists headline_hash text;

create unique index if not exists crises_headline_hash_idx
    on crises (headline_hash) where headline_hash is not null;
