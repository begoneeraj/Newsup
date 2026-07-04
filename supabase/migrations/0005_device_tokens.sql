-- Migration 0005: FCM device tokens for crisis-report push notifications.
-- Run this in the Supabase SQL editor.
--
-- The anon (app) key may insert/update its own token but never read the
-- table back — the notify-crisis Edge Function reads it using the service
-- role key, which bypasses RLS entirely.

create table if not exists device_tokens (
  token text primary key,
  platform text not null default 'android',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table device_tokens enable row level security;

create policy "anon can register a token" on device_tokens
  for insert
  to anon
  with check (true);

create policy "anon can refresh its own token row" on device_tokens
  for update
  to anon
  using (true)
  with check (true);
