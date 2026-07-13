-- Migration 0013: evidence trail + dual-tone summaries + re-verification
-- fields for the Government Promises Tracker. See
-- src/ai_processor/groq_processor.py (_GOVT_PROMISE_REVERIFICATION_SYSTEM_PROMPT)
-- and src/pipeline/promise_reverification.py.
--
-- Design notes:
-- * genz_summary mirrors the dual-tone convention already used by
--   fact_checks.genz_summary / ai_tech_reports.headline_genz (see
--   lib/src/models/fact_check.dart::displayClaim).
-- * party is deliberately free text, NOT a check()-constrained enum like
--   category/current_status -- India's party landscape is too open-ended
--   for a closed list the way category's ~10 fixed values are, and is
--   legitimately null for most metro/highway/budget rows (only
--   election_promise rows usually have one). Not added to
--   groq_processor._ENUM_SANITIZE_RULES for the same reason.
-- * implementation_quality/verification_confidence are a new axis
--   orthogonal to current_status: current_status tracks project lifecycle
--   stage (started/ongoing/completed...), implementation_quality tracks
--   how thoroughly that status has been independently verified. A promise
--   can be current_status='completed' while implementation_quality is
--   still 'on_paper_only' if the only evidence is the government's own
--   inauguration press release -- the "never fully_implemented on
--   official-only evidence" rule is enforced in CODE (not just prompted),
--   see src/pipeline/promise_reverification.py::_apply_business_rules.
-- * promise_source distinguishes rows seeded by the one-time manifesto PDF
--   archive import from rows extracted by the normal per-article pipeline.
-- * promise_evidence FKs on govt_promises.id (not project_slug) since
--   evidence rows belong to a specific promise record, not a slug string.
--
-- Run this in the Supabase SQL editor after 0002-0012.

alter table govt_promises
    add column if not exists genz_summary text,
    add column if not exists party text,
    add column if not exists election_year integer,
    add column if not exists promise_source text not null default 'news_article'
        check (promise_source in (
            'news_article', 'election_manifesto', 'budget_document',
            'official_statement', 'other'
        )),
    add column if not exists implementation_quality text
        check (implementation_quality in (
            'not_started', 'on_paper_only', 'partially_implemented',
            'fully_implemented', 'poor_quality_implementation'
        )),
    add column if not exists verification_confidence text not null default 'low'
        check (verification_confidence in ('low', 'medium', 'high')),
    add column if not exists official_claim text,
    add column if not exists ground_reality text,
    add column if not exists last_verified_at timestamptz;

create index if not exists govt_promises_election_year_idx on govt_promises (election_year);
create index if not exists govt_promises_implementation_quality_idx on govt_promises (implementation_quality);
create index if not exists govt_promises_party_idx on govt_promises (party);

create table if not exists promise_evidence (
    id uuid primary key default gen_random_uuid(),
    promise_id uuid not null references govt_promises (id) on delete cascade,
    source_type text not null check (source_type in (
        'parliament_qa', 'cag_report', 'prs_legislative', 'news_article',
        'official_pib', 'mygov_scheme_page', 'manifesto_pdf',
        'budget_document', 'other'
    )),
    source_url text not null default '',
    stance text not null check (stance in (
        'supports_done', 'contradicts_done', 'neutral_update'
    )),
    excerpt_summary text not null,
    observed_at timestamptz not null default now(),
    created_at timestamptz not null default now()
);

create index if not exists promise_evidence_promise_id_idx on promise_evidence (promise_id);
create index if not exists promise_evidence_stance_idx on promise_evidence (stance);
create index if not exists promise_evidence_source_type_idx on promise_evidence (source_type);

-- RLS: same pattern as 0012 -- anon (app) key read-only, pipeline writes
-- with the service-role key which bypasses RLS.
alter table promise_evidence enable row level security;

create policy "Public read access" on promise_evidence for select using (true);
