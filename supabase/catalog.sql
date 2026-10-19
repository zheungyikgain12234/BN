-- Software catalog (app-store style): per-company software, categories, cart, role-based access, media storage.
-- Run in the Supabase SQL editor AFTER schema.sql and multitenant.sql. Safe to re-run.
--
-- Roles
--   super admin    : row in public.app_admins            -> manages companies + users (and may edit any catalog)
--   company admin  : tenant_members.role = 'admin'       -> adds/edits software of their own company
--   customer       : tenant_members.role = 'member'      -> browses the whole catalogue (all companies)

-- 1. Helpers (security definer so policies never recurse into tenant_members RLS)
create or replace function public.is_member(t uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.tenant_members where tenant_id = t and user_id = auth.uid())
$$;

create or replace function public.can_manage_tenant(t uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.is_app_admin()
      or exists (select 1 from public.tenant_members where tenant_id = t and user_id = auth.uid() and role = 'admin')
$$;

create or replace function public.is_any_company_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select public.is_app_admin()
      or exists (select 1 from public.tenant_members where user_id = auth.uid() and role = 'admin')
$$;

-- 2. Categories (shown as the filter chips in the store). `icon` is a Material icon name the app resolves.
create table if not exists public.software_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  icon text,
  sort_order int not null default 0
);
create unique index if not exists software_categories_name_key on public.software_categories (lower(name));

-- 3. Products become company-scoped (tenant_id null = visible to every company).
alter table public.products add column if not exists tenant_id uuid references public.tenants on delete cascade;
alter table public.products add column if not exists category_id uuid references public.software_categories on delete set null;
alter table public.products add column if not exists price numeric(12,2);
alter table public.products add column if not exists currency text;
alter table public.products add column if not exists created_at timestamptz not null default now();

-- carry over any existing free-text categories
insert into public.software_categories (name)
select distinct trim(category) from public.products where coalesce(trim(category), '') <> ''
on conflict do nothing;
update public.products p set category_id = c.id
from public.software_categories c
where p.category_id is null and lower(c.name) = lower(trim(p.category));

-- 4. Shopping cart (one row per user + product)
create table if not exists public.cart_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  product_id uuid not null references public.products on delete cascade,
  quantity int not null default 1 check (quantity > 0),
  created_at timestamptz not null default now(),
  unique (user_id, product_id)
);

-- 5. Row level security
alter table public.software_categories enable row level security;
alter table public.cart_items enable row level security;

drop policy if exists "catalog readable" on public.products;
drop policy if exists "products visible" on public.products;
create policy "products visible" on public.products for select to authenticated
  using (true); -- the Software store shows every company's apps; only managing is limited by company
drop policy if exists "products managed" on public.products;
create policy "products managed" on public.products for all to authenticated
  using (public.can_manage_tenant(tenant_id)) with check (public.can_manage_tenant(tenant_id));

drop policy if exists "screenshots readable" on public.product_screenshots;
drop policy if exists "screenshots visible" on public.product_screenshots;
create policy "screenshots visible" on public.product_screenshots for select to authenticated
  using (exists (select 1 from public.products p where p.id = product_id));
drop policy if exists "screenshots managed" on public.product_screenshots;
create policy "screenshots managed" on public.product_screenshots for all to authenticated
  using (exists (select 1 from public.products p where p.id = product_id and public.can_manage_tenant(p.tenant_id)))
  with check (exists (select 1 from public.products p where p.id = product_id and public.can_manage_tenant(p.tenant_id)));

drop policy if exists "categories readable" on public.software_categories;
create policy "categories readable" on public.software_categories for select to authenticated using (true);
drop policy if exists "categories managed" on public.software_categories;
create policy "categories managed" on public.software_categories for all to authenticated
  using (public.is_any_company_admin()) with check (public.is_any_company_admin());

drop policy if exists "comments readable" on public.product_comments;
drop policy if exists "comments visible" on public.product_comments;
create policy "comments visible" on public.product_comments for select to authenticated
  using (exists (select 1 from public.products p where p.id = product_id));
drop policy if exists "admin deletes comments" on public.product_comments;
create policy "admin deletes comments" on public.product_comments for delete to authenticated
  using (exists (select 1 from public.products p where p.id = product_id and public.can_manage_tenant(p.tenant_id)));

drop policy if exists "own cart" on public.cart_items;
create policy "own cart" on public.cart_items for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- 6. Media bucket: public read; users write only inside a folder named after their own user id.
insert into storage.buckets (id, name, public) values ('catalog-media', 'catalog-media', true)
on conflict (id) do nothing;

drop policy if exists "catalog media read" on storage.objects;
create policy "catalog media read" on storage.objects for select using (bucket_id = 'catalog-media');
drop policy if exists "catalog media upload" on storage.objects;
create policy "catalog media upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'catalog-media' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "catalog media delete" on storage.objects;
create policy "catalog media delete" on storage.objects for delete to authenticated
  using (bucket_id = 'catalog-media' and (storage.foldername(name))[1] = auth.uid()::text);

-- 7. Masters: the lists the app form picks from (category is above). Admins manage them in the app.
create table if not exists public.software_tags (
  id uuid primary key default gen_random_uuid(),
  name text not null
);
create unique index if not exists software_tags_name_key on public.software_tags (lower(name));

create table if not exists public.pricing_models (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort_order int not null default 0
);
create unique index if not exists pricing_models_name_key on public.pricing_models (lower(name));

create table if not exists public.currencies (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text,
  sort_order int not null default 0
);
create unique index if not exists currencies_code_key on public.currencies (lower(code));

-- keep whatever values existing apps already use
insert into public.software_tags (name)
select distinct trim(t) from public.products, unnest(tags) as t where coalesce(trim(t), '') <> ''
on conflict do nothing;
insert into public.pricing_models (name)
select distinct trim(pricing_model) from public.products where coalesce(trim(pricing_model), '') <> ''
on conflict do nothing;
insert into public.currencies (code)
select distinct upper(trim(currency)) from public.products where coalesce(trim(currency), '') <> ''
on conflict do nothing;

alter table public.software_tags enable row level security;
alter table public.pricing_models enable row level security;
alter table public.currencies enable row level security;

drop policy if exists "tags readable" on public.software_tags;
create policy "tags readable" on public.software_tags for select to authenticated using (true);
drop policy if exists "tags managed" on public.software_tags;
create policy "tags managed" on public.software_tags for all to authenticated
  using (public.is_any_company_admin()) with check (public.is_any_company_admin());

drop policy if exists "pricing models readable" on public.pricing_models;
create policy "pricing models readable" on public.pricing_models for select to authenticated using (true);
drop policy if exists "pricing models managed" on public.pricing_models;
create policy "pricing models managed" on public.pricing_models for all to authenticated
  using (public.is_any_company_admin()) with check (public.is_any_company_admin());

drop policy if exists "currencies readable" on public.currencies;
create policy "currencies readable" on public.currencies for select to authenticated using (true);
drop policy if exists "currencies managed" on public.currencies;
create policy "currencies managed" on public.currencies for all to authenticated
  using (public.is_any_company_admin()) with check (public.is_any_company_admin());
