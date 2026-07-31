-- Migration 0021: publisher_track_record — per-publisher, per-topic history
-- of how often a publisher's articles get flagged as fake, so the pipeline
-- (or a future UI) can surface "this publisher has been wrong about X before"
-- instead of only ever judging a single article in isolation.
--
-- One row per (publisher_name, topic) pair, incremented every time an
-- article from that publisher on that topic is processed — see
-- src/database/publisher_track_record.py::update_publisher_record.
--
-- Run this in the Supabase SQL editor.

create table if not exists publisher_track_record (
    id uuid primary key default gen_random_uuid(),
    publisher_name text not null,
    topic text not null,
    total_articles integer not null default 0,
    flagged_fake_count integer not null default 0,
    -- Nullable rather than 0 when total_articles is 0 — "no data yet" and
    -- "confirmed 0% fake rate" are different claims and must not collapse
    -- into the same value.
    fake_rate float,
    last_updated timestamptz not null default now(),
    unique (publisher_name, topic)
);

create index if not exists publisher_track_record_publisher_idx on publisher_track_record (publisher_name);

-- RLS: same pattern as schema.sql — anon (app) key gets read-only access,
-- the pipeline writes with the service-role key which bypasses RLS entirely.
alter table publisher_track_record enable row level security;

create policy "Public read access" on publisher_track_record for select using (true);
