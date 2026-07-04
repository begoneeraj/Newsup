-- Migration 0004: transparency column showing which phrase in the source
-- text made Groq classify this as an ongoing institutional crisis (routed
-- to the larger MODEL_COMPLEX model). Nullable — existing rows stay valid.
-- Run this in the Supabase SQL editor.

alter table crisis_reports
add column if not exists trigger_keyword text;
