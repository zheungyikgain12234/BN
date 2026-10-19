-- Maps a Biznest user to their 20i StackCP user (one per user).
-- Rows are written only by the stackcp-sso Edge Function (service role).
-- The panel password is never stored: it is derived from the user id + a server secret.
drop table if exists public.stackcp_users;

create table public.stackcp_users (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  stack_user_id  text not null,           -- e.g. "stack-user:5742001"
  panel_username text not null,           -- the StackCP login (the user's email)
  created_at     timestamptz not null default now()
);

alter table public.stackcp_users enable row level security;

create policy "own stackcp mapping" on public.stackcp_users
  for select to authenticated using (user_id = auth.uid());
