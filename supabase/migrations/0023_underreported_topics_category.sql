-- Migration 0023: Fixes the Underreported Topics pipeline being completely
-- broken since launch. src/pipeline/underreported_topics.py has always sent
-- a "category" field (see TRACKED_TOPICS, used for UI grouping) when
-- creating an underreported_topics row, but migration 0015 never created
-- that column. Every insert has been failing with PGRST204 ("Could not
-- find the 'category' column of 'underreported_topics' in the schema
-- cache") since the feature shipped, so the table has zero rows and the
-- app only ever shows the "No gaps computed yet" empty state.
--
-- Run this in the Supabase SQL editor.

alter table underreported_topics
    add column if not exists category text;
