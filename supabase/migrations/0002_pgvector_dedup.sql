-- Migration 0002: semantic deduplication via pgvector.
-- Run this after supabase/schema.sql has already created fact_checks and
-- crisis_reports. Safe to re-run (every statement is idempotent).

create extension if not exists vector;

alter table fact_checks add column if not exists embedding vector(384);
alter table crisis_reports add column if not exists embedding vector(384);

-- Approximate nearest-neighbor indexes for cosine similarity search. ivfflat
-- clusters around the data present at index-build time, so once each table
-- has a few hundred+ embedded rows, run `reindex index <name>` to improve
-- recall — an index built on a near-empty table still works, just with
-- weaker clustering.
create index if not exists fact_checks_embedding_idx
    on fact_checks using ivfflat (embedding vector_cosine_ops) with (lists = 50);

create index if not exists crisis_reports_embedding_idx
    on crisis_reports using ivfflat (embedding vector_cosine_ops) with (lists = 50);

-- Semantic similarity search, called from the Python pipeline before deciding
-- whether a new item is a near-duplicate of an existing row. `<=>` is
-- pgvector's cosine *distance* operator, so similarity = 1 - distance.
create or replace function match_fact_checks (
    query_embedding vector(384),
    match_threshold float,
    match_count int
)
returns table (id uuid, claim_text text, similarity float)
language sql stable
as $$
    select
        fact_checks.id,
        fact_checks.claim_text,
        1 - (fact_checks.embedding <=> query_embedding) as similarity
    from fact_checks
    where fact_checks.embedding is not null
        and 1 - (fact_checks.embedding <=> query_embedding) > match_threshold
    order by fact_checks.embedding <=> query_embedding
    limit match_count;
$$;

create or replace function match_crisis_reports (
    query_embedding vector(384),
    match_threshold float,
    match_count int
)
returns table (id uuid, title text, similarity float)
language sql stable
as $$
    select
        crisis_reports.id,
        crisis_reports.title,
        1 - (crisis_reports.embedding <=> query_embedding) as similarity
    from crisis_reports
    where crisis_reports.embedding is not null
        and 1 - (crisis_reports.embedding <=> query_embedding) > match_threshold
    order by crisis_reports.embedding <=> query_embedding
    limit match_count;
$$;

-- Atomic evidence-append, used instead of inserting a new row when a
-- near-duplicate is found. A single UPDATE avoids the read-modify-write race
-- a fetch-then-write from Python would have.
create or replace function append_fact_check_source (row_id uuid, new_source jsonb)
returns void
language sql
as $$
    update fact_checks
    set sources = sources || jsonb_build_array(new_source)
    where id = row_id;
$$;

create or replace function append_crisis_evidence (row_id uuid, new_evidence jsonb)
returns void
language sql
as $$
    update crisis_reports
    set evidence_items = evidence_items || jsonb_build_array(new_evidence)
    where id = row_id;
$$;
