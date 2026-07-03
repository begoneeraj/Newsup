-- Migration 0003: public storage bucket for preserved Reddit image evidence.
-- Already applied directly via the Storage Management API for this project;
-- kept here so a fresh Supabase project can be brought to the same state.
-- Safe to re-run (on conflict does nothing).

insert into storage.buckets (id, name, public)
values ('evidence_vault', 'evidence_vault', true)
on conflict (id) do nothing;
