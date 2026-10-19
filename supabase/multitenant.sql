-- Multi-tenant login: company select -> login (company + email + password must match) -> register with company.
-- Run in the Supabase SQL editor AFTER schema.sql. Safe to re-run.

-- 1. App administrators (can add/remove companies and manage users). No write policies:
--    rows are added only here in the SQL editor / with the service role.
create table if not exists public.app_admins (
  user_id uuid primary key references auth.users on delete cascade
);
alter table public.app_admins enable row level security;
drop policy if exists "own admin row" on public.app_admins;
create policy "own admin row" on public.app_admins for select to authenticated using (user_id = auth.uid());

create or replace function public.is_app_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.app_admins where user_id = auth.uid())
$$;

-- 2. Company names must be unique (they are what users pick from).
create unique index if not exists tenants_name_key on public.tenants (lower(name));

-- 3. The company dropdown is needed before anyone is signed in, so expose only id + name to anon.
create or replace function public.list_companies() returns table (id uuid, name text)
language sql stable security definer set search_path = '' as $$
  select t.id, t.name from public.tenants t order by t.name
$$;
grant execute on function public.list_companies() to anon, authenticated;

-- 4. Registering with a company: the app sends company_id in the sign-up metadata.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name, avatar_url)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email), new.raw_user_meta_data->>'avatar_url');

  if coalesce(new.raw_user_meta_data->>'company_id', '') <> '' then
    insert into public.tenant_members (tenant_id, user_id, role)
    select t.id, new.id, 'member' from public.tenants t
    where t.id = (new.raw_user_meta_data->>'company_id')::uuid
    on conflict do nothing;
  end if;
  return new;
end $$;

-- 5. Admin access on top of the member-only policies from schema.sql.
drop policy if exists "admin manages tenants" on public.tenants;
create policy "admin manages tenants" on public.tenants for all to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());

drop policy if exists "admin manages members" on public.tenant_members;
create policy "admin manages members" on public.tenant_members for all to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());

-- 6. Make yourself the first administrator (replace the email), then sign in via "Administrator sign in".
-- insert into public.app_admins (user_id) select id from auth.users where email = 'you@example.com';
