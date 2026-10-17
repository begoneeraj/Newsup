-- An FCM registration token is a high-entropy device capability. Clients
-- may remove exactly the token they possess, but cannot enumerate tokens.
-- No broad DELETE or SELECT policy is granted on device_tokens.
-- Existing registrations need no update; INSERT ... ON CONFLICT DO NOTHING
-- handles a repeat registration without permission to rewrite other rows.
drop policy if exists "anon can refresh its own token row" on public.device_tokens;
revoke update on public.device_tokens from anon, authenticated;
create or replace function public.unregister_device_token(device_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if device_token is null or length(device_token) < 32 or length(device_token) > 4096 then
    raise exception 'Invalid device token';
  end if;
  delete from public.device_tokens where token = device_token;
end;
$$;
revoke all on function public.unregister_device_token(text) from public;
grant execute on function public.unregister_device_token(text) to anon, authenticated;
