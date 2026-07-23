-- Migration 0018: refresh pinned_statistics suicide figures to NCRB's ADSI
-- 2024 report (released May 2026), which supersedes the ADSI 2023 figures
-- seeded in 0017.
--
-- pinned_statistics is a manually-curated, annually-updated table (see 0017)
-- — NCRB is the only official source for these numbers and it publishes
-- once a year with a lag of 1-2 years, so there is no "live" count to fetch.
-- Do NOT build a fetcher/cron job for this data. When the next ADSI report
-- is out, add another migration like this one rather than a live source.
--
-- Run this in the Supabase SQL editor after 0017.

update pinned_statistics
set value = 170746, year = 2024, source = 'NCRB ADSI 2024', updated_at = now()
where label = 'Total Suicides';

update pinned_statistics
set value = 14488, year = 2024, source = 'NCRB ADSI 2024', updated_at = now()
where label = 'Student Suicides';
