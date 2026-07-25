-- Migration 0016: Underreported Topics narrative module. Adds a table to
-- store the weekly AI-generated narrative summaries for the most
-- underreported topics, implementing Phase 3 of the feature's roadmap.
--
-- See pipeline.underreported_topics.run_underreported_topics_narrative_update.

create table if not exists underreported_topic_narratives (
    id uuid primary key default gen_random_uuid(),
    topic_id uuid not null references underreported_topics (id) on delete cascade,
    narrative_summary text not null,
    genz_summary text,
    generated_at timestamptz not null default now(),
    headline_hash text unique not null
);

create index if not exists underreported_topic_narratives_topic_id_idx
    on underreported_topic_narratives (topic_id, generated_at desc);

-- RLS: same read-only pattern as other pipeline-written tables.
alter table underreported_topic_narratives enable row level security;

create policy "Public read access" on underreported_topic_narratives for select using (true);

-- Add narrative fields to the parent underreported_topics table to cache
-- the latest narrative, avoiding a join on the main listing endpoint.
alter table underreported_topics add column if not exists latest_narrative_summary text;
alter table underreported_topics add column if not exists latest_narrative_genz_summary text;