-- BizNest Hub schema: the ONLY schema file. Run it in the Supabase SQL editor, then run seed.sql.
-- It starts by deleting the app's tables, so running it again resets everything (users in auth.users are kept).
-- Current scope: login/companies, software store, resellers + clients, domain names, VPS and Hosting Packages.
-- SSL is not in here yet; its tables are dropped and will be added back later.
--
-- Roles
--   super admin     : row in public.app_admins    -> manages companies, users, software, master data; never buys
--   reseller admin  : tenant_members.role='admin'  -> manages software + clients, buys, assigns to clients with own markup
--   reseller        : tenant_members.role='member' -> manages software + clients, assigns purchased items; cannot buy
-- All money in the system is SGD.

-- 0. Reset ------------------------------------------------------------------------------------------------------
drop table if exists
  public.purchased_domains, public.domain_order_items, public.domain_orders, public.domain_cart_items, public.domain_tld_prices, public.app_settings, -- app_settings: old table, no longer used
 
  public.licenses, public.orders, public.clients, public.cart_items,
  public.product_comments, public.product_screenshots, public.products,
  public.software_tags, public.pricing_models, public.software_categories, public.currencies,
  public.app_admins, public.tenant_members, public.tenants, public.profiles,
  -- SSL is not in scope yet (old tables); the VPS and hosting tables are rebuilt in sections 5b and 5c
  public.purchased_hosting, public.hosting_order_items, public.hosting_orders, public.hosting_cart_items, public.hosting_plan_prices,
  public.purchased_vps, public.vps_order_items, public.vps_orders, public.vps_cart_items, public.vps_addon_prices, public.vps_os_options, public.vps_locations, public.vps_plan_prices,
  public.purchased_ssl, public.ssl_order_items, public.ssl_orders, public.ssl_cart_items, public.ssl_plan_prices
  cascade;
drop function if exists public.handle_new_user() cascade;

-- 1. People and companies ---------------------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  full_name text,
  job_title text,
  avatar_url text
);

create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text,
  domain text,
  plan text default 'enterprise',
  seats_active int default 0
);
create unique index tenants_name_key on public.tenants (lower(name));

create table public.tenant_members (
  tenant_id uuid references public.tenants on delete cascade,
  user_id uuid references auth.users on delete cascade,
  role text default 'member',
  primary key (tenant_id, user_id)
);

-- App administrators. No write policies: rows are added only in the SQL editor / with the service role.
create table public.app_admins (
  user_id uuid primary key references auth.users on delete cascade
);

-- Maps a user to their 20i StackCP user. Written only by the stackcp-sso Edge Function (service role).
-- NOT dropped by the reset above: it mirrors users that exist at 20i, and losing it locks those users out of the panel.
create table if not exists public.stackcp_users (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  stack_user_id  text not null,           -- e.g. "stack-user:5742001"
  panel_username text not null,           -- the StackCP login (the user's email)
  created_at     timestamptz not null default now()
);

-- 2. Helpers (security definer so policies never recurse into tenant_members RLS) --------------------------------
create or replace function public.is_app_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.app_admins where user_id = auth.uid())
$$;

create or replace function public.is_member(t uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.tenant_members where tenant_id = t and user_id = auth.uid())
$$;

-- Every reseller (member) manages their own company's data, not only admins.
create or replace function public.can_manage_tenant(t uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.is_app_admin()
      or exists (select 1 from public.tenant_members where tenant_id = t and user_id = auth.uid())
$$;

create or replace function public.is_any_company_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select public.is_app_admin()
      or exists (select 1 from public.tenant_members where user_id = auth.uid() and role = 'admin')
$$;

-- reseller admin: may buy for tenant t. A super admin belongs to no company and never buys.
create or replace function public.can_buy_for_tenant(t uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select not public.is_app_admin()
     and exists (select 1 from public.tenant_members where tenant_id = t and user_id = auth.uid() and role = 'admin')
$$;

-- The company dropdown is needed before anyone is signed in, so expose only id + name to anon.
create or replace function public.list_companies() returns table (id uuid, name text)
language sql stable security definer set search_path = '' as $$
  select t.id, t.name from public.tenants t order by t.name
$$;
grant execute on function public.list_companies() to anon, authenticated;

-- Auto-create a profile on sign-up; the app sends company_id in the sign-up metadata to join a company.
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
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- 3. Software store ---------------------------------------------------------------------------------------------
-- Master lists the software form picks from. `icon` is a Material icon name the app resolves.
create table public.software_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  icon text,
  sort_order int not null default 0
);
create unique index software_categories_name_key on public.software_categories (lower(name));

create table public.software_tags (
  id uuid primary key default gen_random_uuid(),
  name text not null
);
create unique index software_tags_name_key on public.software_tags (lower(name));

create table public.pricing_models (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort_order int not null default 0
);
create unique index pricing_models_name_key on public.pricing_models (lower(name));

-- tenant_id null = visible to every company
create table public.products (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants on delete cascade,
  category_id uuid references public.software_categories on delete set null,
  name text not null,
  category text,
  description text,
  about text,
  pricing_model text,
  price numeric(12,2),
  currency text not null default 'SGD',
  price_label text,
  seat_price text,
  rating numeric default 0,
  rating_count int default 0,
  image_url text,
  publisher text,
  publisher_code text,
  sku text,
  version text,
  billing_cycle text,
  min_commitment text,
  cloud_targets text,
  multi_tenant boolean default false,
  tags text[] default '{}',
  sort_order int default 0,
  created_at timestamptz not null default now()
);

create table public.product_screenshots (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products on delete cascade,
  title text, caption text, image_url text not null,
  sort_order int default 0
);

create table public.product_comments (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products on delete cascade,
  user_id uuid references public.profiles on delete cascade default auth.uid(),
  body text not null,
  badge text,
  attachment_name text, attachment_url text, attachment_type text,
  endorsements int default 0,
  replies int default 0,
  created_at timestamptz default now()
);

create table public.cart_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  product_id uuid not null references public.products on delete cascade,
  quantity int not null default 1 check (quantity > 0),
  created_at timestamptz not null default now(),
  unique (user_id, product_id)
);

-- Reassigning before deleting a master value. security definer because a company admin cannot update
-- other companies' apps directly, yet the master list is shared by every company.
--   kind: category (old/new are category ids) | tag | pricing_model.  new_value null = clear it from the apps.
create or replace function public.master_usage(kind text, old_value text) returns int
language plpgsql stable security definer set search_path = '' as $$
declare n int;
begin
  if not public.is_any_company_admin() then raise exception 'not allowed'; end if;
  if kind = 'category' then
    select count(*) into n from public.products where category_id = old_value::uuid;
  elsif kind = 'tag' then
    select count(*) into n from public.products where old_value = any(tags);
  elsif kind = 'pricing_model' then
    select count(*) into n from public.products where pricing_model = old_value;
  else
    raise exception 'unknown kind %', kind;
  end if;
  return n;
end $$;

create or replace function public.reassign_master(kind text, old_value text, new_value text) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  if not public.is_any_company_admin() then raise exception 'not allowed'; end if;
  if kind = 'category' then
    update public.products set category_id = nullif(new_value, '')::uuid where category_id = old_value::uuid;
  elsif kind = 'tag' then
    update public.products
       set tags = case when new_value is null or new_value = ''
                       then array_remove(tags, old_value)
                       else (select coalesce(array_agg(distinct t), '{}') from unnest(array_replace(tags, old_value, new_value)) as t) end
     where old_value = any(tags);
  elsif kind = 'pricing_model' then
    update public.products set pricing_model = nullif(new_value, '') where pricing_model = old_value;
  else
    raise exception 'unknown kind %', kind;
  end if;
  get diagnostics n = row_count;
  return n;
end $$;
grant execute on function public.master_usage(text, text) to authenticated;
grant execute on function public.reassign_master(text, text, text) to authenticated;

-- 4. Resellers: clients, orders, licenses -----------------------------------------------------------------------
create table public.clients (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  name text not null,
  contact_name text,
  email text,
  phone text,
  notes text,
  created_by uuid default auth.uid() references auth.users on delete set null,
  created_at timestamptz not null default now()
);
create index clients_tenant_idx on public.clients (tenant_id);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  created_at timestamptz not null default now()
);

-- one row per purchased unit
create table public.licenses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  order_id uuid references public.orders on delete set null,
  product_id uuid not null references public.products on delete restrict,
  unit_price numeric(12,2) not null default 0,   -- catalogue price paid by the reseller
  currency text not null default 'SGD',
  purchased_at timestamptz not null default now(),
  client_id uuid references public.clients on delete set null,
  sell_price numeric(12,2),                       -- what the client pays (reseller markup included)
  assigned_at timestamptz
);
create index licenses_tenant_idx on public.licenses (tenant_id);
create index licenses_client_idx on public.licenses (client_id);

-- Checkout: turns the caller's cart into licenses for tenant p_tenant.
--   p_lines: one entry per license unit, in order: [{ "cart_item_id": uuid, "client_id": uuid|null, "sell_price": number|null }]
--   The n-th entry of a cart item applies to its n-th unit; units without an entry stay unassigned.
create or replace function public.checkout(p_tenant uuid, p_lines jsonb default '[]') returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_order uuid;
  r record;
  n int;
  v_client uuid;
  v_price numeric;
begin
  if not public.can_buy_for_tenant(p_tenant) then raise exception 'Only a reseller admin can purchase licenses'; end if;
  if not exists (select 1 from public.cart_items where user_id = auth.uid()) then raise exception 'Your cart is empty'; end if;

  insert into public.orders (tenant_id) values (p_tenant) returning id into v_order;

  for r in
    select ci.id as cart_id, ci.quantity, p.id as product_id, coalesce(p.price, 0) as price
    from public.cart_items ci join public.products p on p.id = ci.product_id
    where ci.user_id = auth.uid()
  loop
    for n in 1..r.quantity loop
      v_client := null; v_price := null;
      select nullif(x.l->>'client_id', '')::uuid, nullif(x.l->>'sell_price', '')::numeric
        into v_client, v_price
        from (
          select l, row_number() over (order by idx) as rn
          from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) with ordinality as t(l, idx)
          where l->>'cart_item_id' = r.cart_id::text
        ) x
        where x.rn = n;

      if v_client is not null and not exists (select 1 from public.clients where id = v_client and tenant_id = p_tenant) then
        raise exception 'Client does not belong to this company';
      end if;

      insert into public.licenses (tenant_id, order_id, product_id, unit_price, client_id, sell_price, assigned_at)
      values (p_tenant, v_order, r.product_id, r.price, v_client,
              case when v_client is null then null else coalesce(v_price, r.price) end,
              case when v_client is null then null else now() end);
    end loop;
  end loop;

  delete from public.cart_items where user_id = auth.uid();
  return v_order;
end $$;

-- Assign (or unassign with p_client null) one license to a client at the reseller's own price.
create or replace function public.assign_license(p_license uuid, p_client uuid, p_sell_price numeric) returns void
language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid;
begin
  select tenant_id into v_tenant from public.licenses where id = p_license;
  if v_tenant is null or not public.can_manage_tenant(v_tenant) then raise exception 'not allowed'; end if;
  if p_client is not null and not exists (select 1 from public.clients where id = p_client and tenant_id = v_tenant) then
    raise exception 'Client does not belong to this company';
  end if;
  update public.licenses
     set client_id = p_client,
         sell_price = case when p_client is null then null else p_sell_price end,
         assigned_at = case when p_client is null then null else now() end
   where id = p_license;
end $$;
grant execute on function public.checkout(uuid, jsonb) to authenticated;
grant execute on function public.assign_license(uuid, uuid, numeric) to authenticated;

-- 5. Domain names -----------------------------------------------------------------------------------------------
-- Master Data > Domain prices (admin only). The TLD is picked from the 20i shop list, never typed.
-- Selling price per year = cost x (1 + profit %), rounded to the cent. The profit % is compulsory on every TLD.
-- A reseller buys any number of years: total = years x price_per_year. Always SGD.
create table public.domain_tld_prices (
  id uuid primary key default gen_random_uuid(),
  tld text not null unique,                   -- without the dot, lowercase: com, co.uk
  cost_per_year numeric(12,2) not null check (cost_per_year >= 0),  -- what 20i charges per year (copied from the 20i shop)
  profit_percent numeric(6,2) not null check (profit_percent >= 0)  -- markup on the cost, e.g. 10 = cost + 10%
);

-- What the app and checkout read: the table plus the computed selling price.
create view public.domain_prices with (security_invoker = true) as
select p.id, p.tld, p.cost_per_year, p.profit_percent,
       round(p.cost_per_year * (1 + p.profit_percent / 100), 2) as price_per_year
from public.domain_tld_prices p;
grant select on public.domain_prices to authenticated, service_role;

create table public.domain_cart_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  domain text not null,
  years int not null check (years > 0),
  price numeric(12,2) not null,               -- price for the whole duration, as shown when added
  panel_item_id text,                         -- this item's id in the 20i panel basket (so it can be removed from there too)
  currency text not null default 'SGD',
  created_at timestamptz not null default now(),
  unique (user_id, domain)
);

-- One order per checkout, one item per domain. Written by the domain-checkout / stripe-webhook Edge Functions.
create table public.domain_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  tenant_id uuid references public.tenants on delete set null,   -- which company bought it
  status text not null default 'pending' check (status in ('pending', 'paid', 'failed')),
  currency text not null default 'SGD',
  total numeric(12,2) not null,
  stripe_session_id text unique,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
create index domain_orders_user_idx on public.domain_orders (user_id, created_at desc);

create table public.domain_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.domain_orders on delete cascade,
  domain text not null,
  years int not null check (years > 0),
  price numeric(12,2) not null,
  -- pending: waiting for payment | test_registered: paid, registration only simulated
  -- registered: really registered with 20i | failed: paid but registration failed (see note)
  status text not null default 'pending' check (status in ('pending', 'test_registered', 'registered', 'failed')),
  note text,
  panel_item_id text                          -- copied from the cart; the webhook removes it from the 20i panel basket
);
create index domain_order_items_order_idx on public.domain_order_items (order_id);

-- The domain version of public.licenses. Rows are added by stripe-webhook when a payment is confirmed.
create table public.purchased_domains (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  order_item_id uuid unique references public.domain_order_items on delete set null,
  domain text not null,
  years int not null check (years > 0),
  unit_price numeric(12,2) not null,           -- price the reseller paid (Master Data price x years at checkout)
  currency text not null default 'SGD',
  -- test_registered: paid, registration only simulated | registered: really registered at 20i | failed: see note
  status text not null check (status in ('test_registered', 'registered', 'failed')),
  note text,
  purchased_at timestamptz not null default now(),
  client_id uuid references public.clients on delete set null,
  sell_price numeric(12,2),                    -- what the client pays (reseller markup included)
  assigned_at timestamptz
);
create index purchased_domains_tenant_idx on public.purchased_domains (tenant_id);
create index purchased_domains_client_idx on public.purchased_domains (client_id);

-- Assign (or unassign with p_client null) one purchased domain to a client at the reseller's own price.
create or replace function public.assign_domain(p_domain uuid, p_client uuid, p_sell_price numeric) returns void
language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid; v_status text;
begin
  select tenant_id, status into v_tenant, v_status from public.purchased_domains where id = p_domain;
  if v_tenant is null or not public.can_manage_tenant(v_tenant) then raise exception 'not allowed'; end if;
  if p_client is not null and v_status = 'failed' then raise exception 'This domain was not registered, so it cannot be assigned'; end if;
  if p_client is not null and not exists (select 1 from public.clients where id = p_client and tenant_id = v_tenant) then
    raise exception 'Client does not belong to this company';
  end if;
  update public.purchased_domains
     set client_id = p_client,
         sell_price = case when p_client is null then null else p_sell_price end,
         assigned_at = case when p_client is null then null else now() end
   where id = p_domain;
end $$;
grant execute on function public.assign_domain(uuid, uuid, numeric) to authenticated;

-- 5b. VPS -------------------------------------------------------------------------------------------------------
-- Same idea as domains: Master Data > VPS prices (admin only). The plan, its billing period and 20i's cost for the WHOLE
-- period are picked from the 20i shop, never typed. Selling price = cost x (1 + profit %), rounded to the cent. Always SGD.
-- Nothing is seeded: add plans, add-ons, operating systems and locations in Master Data.
create table public.vps_plan_prices (
  id uuid primary key default gen_random_uuid(),
  plan_name text not null,                    -- from 20i, e.g. 1 Core Unmanaged VPS
  vps_type text not null,                     -- 20i VPS type, e.g. vps-a (shop product code vps:a)
  months int not null check (months > 0),
  cost numeric(12,2) not null check (cost >= 0),    -- what 20i charges for the whole period (copied from the 20i shop)
  profit_percent numeric(6,2) not null check (profit_percent >= 0),
  unique (vps_type, months)
);

-- cPanel licence, snapshot backup and extra disks; ordered from 20i right after the server is created (addVpsAddon).
create table public.vps_addon_prices (
  id uuid primary key default gen_random_uuid(),
  label text not null,                        -- from 20i, e.g. cPanel Pro (Max 30 Sites)
  product_spec text not null,                 -- 20i productSpec: vps_addon-cpanelpro | vps_addon-backup | vps_addon-disk100GB ...
  months int not null check (months > 0),     -- billing period; the add-on renews separately from the server
  cost numeric(12,2) not null check (cost >= 0),
  profit_percent numeric(6,2) not null check (profit_percent >= 0),
  unique (product_spec, months)
);

-- What the app and vps-checkout read: the tables plus the computed selling price.
create view public.vps_prices with (security_invoker = true) as
select p.id, p.plan_name, p.vps_type, p.months, p.cost, p.profit_percent,
       round(p.cost * (1 + p.profit_percent / 100), 2) as price, 'SGD'::text as currency
from public.vps_plan_prices p;
create view public.vps_addons_priced with (security_invoker = true) as
select a.id, a.label, a.product_spec, a.months, a.cost, a.profit_percent,
       round(a.cost * (1 + a.profit_percent / 100), 2) as price, 'SGD'::text as currency
from public.vps_addon_prices a;
grant select on public.vps_prices, public.vps_addons_priced to authenticated, service_role;

create table public.vps_os_options (
  id uuid primary key default gen_random_uuid(),
  label text not null,                        -- shown to customers, e.g. Ubuntu 22.04
  code text not null unique                   -- 20i OS code, e.g. ubuntu22.04 (picked from 20i)
);

-- Data centres the reseller offers. 20i's addVPS takes the code (e.g. dc_location-lhr); the label is what customers see.
create table public.vps_locations (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  label text not null
);

create table public.vps_cart_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  vps_type text not null,
  plan_name text not null,
  months int not null check (months > 0),
  os_code text not null,
  os_label text not null,
  location text not null,                     -- a vps_locations.code
  server_name text not null,
  price numeric(12,2) not null,               -- display only: vps-checkout re-prices from vps_prices
  currency text not null default 'SGD',
  addons jsonb not null default '[]',         -- [{ spec, months }]
  panel_item_id text,                         -- this server's id in the 20i panel basket (so it can be removed from there too)
  created_at timestamptz not null default now(),
  unique (user_id, server_name)
);

create table public.vps_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  tenant_id uuid references public.tenants on delete set null,
  status text not null default 'pending' check (status in ('pending', 'paid', 'failed')),
  currency text not null,
  total numeric(12,2) not null,
  stripe_session_id text unique,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
create index vps_orders_user_idx on public.vps_orders (user_id, created_at desc);

create table public.vps_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.vps_orders on delete cascade,
  vps_type text not null,
  plan_name text not null,
  months int not null check (months > 0),
  os_code text not null,
  os_label text not null,
  location text not null,
  server_name text not null,
  price numeric(12,2) not null,
  addons jsonb not null default '[]',         -- [{ spec, label, months, price }] as charged
  -- test_registered: paid, creation only simulated | registered: server really ordered at 20i | failed: see note
  status text not null default 'pending' check (status in ('pending', 'test_registered', 'registered', 'failed')),
  note text
);
create index vps_order_items_order_idx on public.vps_order_items (order_id);

create table public.purchased_vps (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  order_item_id uuid unique references public.vps_order_items on delete set null,
  plan_name text not null,
  vps_type text not null,
  months int not null check (months > 0),
  os_label text not null,
  location text not null,
  server_name text not null,
  unit_price numeric(12,2) not null,           -- price the reseller paid (Master Data price at checkout)
  currency text not null,
  addons jsonb not null default '[]',
  status text not null check (status in ('test_registered', 'registered', 'failed')),
  note text,
  purchased_at timestamptz not null default now(),
  client_id uuid references public.clients on delete set null,
  sell_price numeric(12,2),                    -- what the client pays (reseller markup included)
  assigned_at timestamptz
);
create index purchased_vps_tenant_idx on public.purchased_vps (tenant_id);
create index purchased_vps_client_idx on public.purchased_vps (client_id);

-- Assign (or unassign with p_client null) one purchased VPS to a client at the reseller's own price.
create or replace function public.assign_vps(p_vps uuid, p_client uuid, p_sell_price numeric) returns void
language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid; v_status text;
begin
  select tenant_id, status into v_tenant, v_status from public.purchased_vps where id = p_vps;
  if v_tenant is null or not public.can_manage_tenant(v_tenant) then raise exception 'not allowed'; end if;
  if p_client is not null and v_status = 'failed' then raise exception 'This VPS was not created, so it cannot be assigned'; end if;
  if p_client is not null and not exists (select 1 from public.clients where id = p_client and tenant_id = v_tenant) then
    raise exception 'Client does not belong to this company';
  end if;
  update public.purchased_vps
     set client_id = p_client,
         sell_price = case when p_client is null then null else p_sell_price end,
         assigned_at = case when p_client is null then null else now() end
   where id = p_vps;
end $$;
grant execute on function public.assign_vps(uuid, uuid, numeric) to authenticated;

alter table public.vps_plan_prices enable row level security;
alter table public.vps_addon_prices enable row level security;
alter table public.vps_os_options enable row level security;
alter table public.vps_locations enable row level security;
alter table public.vps_cart_items enable row level security;
alter table public.vps_orders enable row level security;
alter table public.vps_order_items enable row level security;
alter table public.purchased_vps enable row level security;

-- everyone reads the prices and lists; only a super admin changes them
create policy "vps prices readable" on public.vps_plan_prices for select to authenticated using (true);
create policy "vps prices managed" on public.vps_plan_prices for all to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());
create policy "vps addon prices readable" on public.vps_addon_prices for select to authenticated using (true);
create policy "vps addon prices managed" on public.vps_addon_prices for all to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());
create policy "vps os readable" on public.vps_os_options for select to authenticated using (true);
create policy "vps os managed" on public.vps_os_options for all to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());
create policy "vps locations readable" on public.vps_locations for select to authenticated using (true);
create policy "vps locations managed" on public.vps_locations for all to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());
create policy "own vps cart" on public.vps_cart_items for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and not public.is_app_admin()); -- super admins never buy
-- customers only read their own orders; the checkout / webhook Edge Functions write with the service role
create policy "own vps orders" on public.vps_orders for select to authenticated using (user_id = auth.uid());
create policy "own vps order items" on public.vps_order_items for select to authenticated
  using (exists (select 1 from public.vps_orders o where o.id = order_id and o.user_id = auth.uid()));
-- purchased_vps rows are created by stripe-webhook (service role) and changed by assign_vps() only
create policy "purchased vps readable" on public.purchased_vps for select to authenticated using (public.can_manage_tenant(tenant_id));

-- 5c. Hosting Packages ------------------------------------------------------------------------------------------
-- Same idea as domains and VPS: Master Data > Hosting Package prices (admin only). The plan, its billing period and 20i's
-- cost for the WHOLE period are picked from the 20i shop, never typed. Selling price = cost x (1 + profit %), rounded to
-- the cent. Always SGD. Nothing is seeded.
create table public.hosting_plan_prices (
  id uuid primary key default gen_random_uuid(),
  plan_name text not null,                    -- from 20i, shown to customers
  package_type_id text not null,              -- 20i package type id (what addWeb needs)
  months int not null check (months > 0),
  cost numeric(12,2) not null check (cost >= 0),    -- what 20i charges for the whole period (copied from the 20i shop)
  profit_percent numeric(6,2) not null check (profit_percent >= 0),
  unique (package_type_id, months)
);

-- What the app and hosting-checkout read: the table plus the computed selling price.
create view public.hosting_prices with (security_invoker = true) as
select p.id, p.plan_name, p.package_type_id, p.months, p.cost, p.profit_percent,
       round(p.cost * (1 + p.profit_percent / 100), 2) as price, 'SGD'::text as currency
from public.hosting_plan_prices p;
grant select on public.hosting_prices to authenticated, service_role;

create table public.hosting_cart_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  package_type_id text not null,
  plan_name text not null,
  months int not null check (months > 0),
  domain text not null,                       -- the domain the hosting package is created for
  price numeric(12,2) not null,               -- display only: hosting-checkout re-prices from hosting_prices
  currency text not null default 'SGD',
  panel_item_id text,                         -- this package's id in the 20i panel basket (so it can be removed from there too)
  created_at timestamptz not null default now(),
  unique (user_id, domain)
);

create table public.hosting_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  tenant_id uuid references public.tenants on delete set null,   -- which company bought it
  status text not null default 'pending' check (status in ('pending', 'paid', 'failed')),
  currency text not null,
  total numeric(12,2) not null,
  stripe_session_id text unique,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
create index hosting_orders_user_idx on public.hosting_orders (user_id, created_at desc);

create table public.hosting_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.hosting_orders on delete cascade,
  package_type_id text not null,
  plan_name text not null,
  months int not null check (months > 0),
  domain text not null,
  price numeric(12,2) not null,
  -- pending: waiting for payment | test_registered: paid, creation only simulated
  -- registered: package really created at 20i | failed: paid but creation failed (see note)
  status text not null default 'pending' check (status in ('pending', 'test_registered', 'registered', 'failed')),
  note text
);
create index hosting_order_items_order_idx on public.hosting_order_items (order_id);

create table public.purchased_hosting (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  order_item_id uuid unique references public.hosting_order_items on delete set null,
  plan_name text not null,
  package_type_id text not null,
  months int not null check (months > 0),
  domain text not null,
  unit_price numeric(12,2) not null,           -- price the reseller paid (Master Data price at checkout)
  currency text not null,
  status text not null check (status in ('test_registered', 'registered', 'failed')),
  note text,
  purchased_at timestamptz not null default now(),
  client_id uuid references public.clients on delete set null,
  sell_price numeric(12,2),                    -- what the client pays (reseller markup included)
  assigned_at timestamptz
);
create index purchased_hosting_tenant_idx on public.purchased_hosting (tenant_id);
create index purchased_hosting_client_idx on public.purchased_hosting (client_id);

-- Assign (or unassign with p_client null) one purchased hosting package to a client at the reseller's own price.
create or replace function public.assign_hosting(p_hosting uuid, p_client uuid, p_sell_price numeric) returns void
language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid; v_status text;
begin
  select tenant_id, status into v_tenant, v_status from public.purchased_hosting where id = p_hosting;
  if v_tenant is null or not public.can_manage_tenant(v_tenant) then raise exception 'not allowed'; end if;
  if p_client is not null and v_status = 'failed' then raise exception 'This package was not created, so it cannot be assigned'; end if;
  if p_client is not null and not exists (select 1 from public.clients where id = p_client and tenant_id = v_tenant) then
    raise exception 'Client does not belong to this company';
  end if;
  update public.purchased_hosting
     set client_id = p_client,
         sell_price = case when p_client is null then null else p_sell_price end,
         assigned_at = case when p_client is null then null else now() end
   where id = p_hosting;
end $$;
grant execute on function public.assign_hosting(uuid, uuid, numeric) to authenticated;

alter table public.hosting_plan_prices enable row level security;
alter table public.hosting_cart_items enable row level security;
alter table public.hosting_orders enable row level security;
alter table public.hosting_order_items enable row level security;
alter table public.purchased_hosting enable row level security;

create policy "hosting prices readable" on public.hosting_plan_prices for select to authenticated using (true);
create policy "hosting prices managed" on public.hosting_plan_prices for all to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());
create policy "own hosting cart" on public.hosting_cart_items for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and not public.is_app_admin()); -- super admins never buy
-- customers only read their own orders; the checkout / webhook Edge Functions write with the service role
create policy "own hosting orders" on public.hosting_orders for select to authenticated using (user_id = auth.uid());
create policy "own hosting order items" on public.hosting_order_items for select to authenticated
  using (exists (select 1 from public.hosting_orders o where o.id = order_id and o.user_id = auth.uid()));
-- purchased_hosting rows are created by stripe-webhook (service role) and changed by assign_hosting() only
create policy "purchased hosting readable" on public.purchased_hosting for select to authenticated using (public.can_manage_tenant(tenant_id));

-- 6. Row level security -----------------------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.tenants enable row level security;
alter table public.tenant_members enable row level security;
alter table public.app_admins enable row level security;
alter table public.stackcp_users enable row level security;
alter table public.software_categories enable row level security;
alter table public.software_tags enable row level security;
alter table public.pricing_models enable row level security;
alter table public.products enable row level security;
alter table public.product_screenshots enable row level security;
alter table public.product_comments enable row level security;
alter table public.cart_items enable row level security;
alter table public.clients enable row level security;
alter table public.orders enable row level security;
alter table public.licenses enable row level security;
alter table public.domain_tld_prices enable row level security;
alter table public.domain_cart_items enable row level security;
alter table public.domain_orders enable row level security;
alter table public.domain_order_items enable row level security;
alter table public.purchased_domains enable row level security;

create policy "profiles readable" on public.profiles for select to authenticated using (true);
create policy "own profile update" on public.profiles for update to authenticated using (id = auth.uid());

create policy "own memberships" on public.tenant_members for select to authenticated using (user_id = auth.uid());
create policy "admin manages members" on public.tenant_members for all to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());
create policy "member tenants" on public.tenants for select to authenticated
  using (exists (select 1 from public.tenant_members m where m.tenant_id = id and m.user_id = auth.uid()));
create policy "admin manages tenants" on public.tenants for all to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());
create policy "own admin row" on public.app_admins for select to authenticated using (user_id = auth.uid());
drop policy if exists "own stackcp mapping" on public.stackcp_users;
create policy "own stackcp mapping" on public.stackcp_users for select to authenticated using (user_id = auth.uid());

-- software masters
create policy "categories readable" on public.software_categories for select to authenticated using (true);
create policy "categories managed" on public.software_categories for all to authenticated
  using (public.is_any_company_admin()) with check (public.is_any_company_admin());
create policy "tags readable" on public.software_tags for select to authenticated using (true);
create policy "tags managed" on public.software_tags for all to authenticated
  using (public.is_any_company_admin()) with check (public.is_any_company_admin());
create policy "pricing models readable" on public.pricing_models for select to authenticated using (true);
create policy "pricing models managed" on public.pricing_models for all to authenticated
  using (public.is_any_company_admin()) with check (public.is_any_company_admin());

-- products: the store shows every company's apps; only managing is limited by company
create policy "products visible" on public.products for select to authenticated using (true);
create policy "products managed" on public.products for all to authenticated
  using (public.can_manage_tenant(tenant_id)) with check (public.can_manage_tenant(tenant_id));
create policy "screenshots visible" on public.product_screenshots for select to authenticated
  using (exists (select 1 from public.products p where p.id = product_id));
create policy "screenshots managed" on public.product_screenshots for all to authenticated
  using (exists (select 1 from public.products p where p.id = product_id and public.can_manage_tenant(p.tenant_id)))
  with check (exists (select 1 from public.products p where p.id = product_id and public.can_manage_tenant(p.tenant_id)));
create policy "comments visible" on public.product_comments for select to authenticated
  using (exists (select 1 from public.products p where p.id = product_id));
create policy "post own comment" on public.product_comments for insert to authenticated with check (user_id = auth.uid());
create policy "delete own comment" on public.product_comments for delete to authenticated using (user_id = auth.uid());
create policy "admin deletes comments" on public.product_comments for delete to authenticated
  using (exists (select 1 from public.products p where p.id = product_id and public.can_manage_tenant(p.tenant_id)));
create policy "own cart" on public.cart_items for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- clients: strictly members of the company (no super-admin bypass)
create policy "clients own company" on public.clients for all to authenticated
  using (public.is_member(tenant_id)) with check (public.is_member(tenant_id));
create policy "orders readable" on public.orders for select to authenticated using (public.can_manage_tenant(tenant_id));
-- licenses are created by checkout() and changed by assign_license() only (no direct write policies)
create policy "licenses readable" on public.licenses for select to authenticated using (public.can_manage_tenant(tenant_id));

-- domains: everyone reads the prices; only a super admin changes them
create policy "domain prices readable" on public.domain_tld_prices for select to authenticated using (true);
create policy "domain prices managed" on public.domain_tld_prices for all to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());
create policy "own domain cart" on public.domain_cart_items for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and not public.is_app_admin()); -- super admins never buy
create policy "own domain orders" on public.domain_orders for select to authenticated using (user_id = auth.uid());
create policy "own domain order items" on public.domain_order_items for select to authenticated
  using (exists (select 1 from public.domain_orders o where o.id = order_id and o.user_id = auth.uid()));
-- purchased_domains: rows are created by stripe-webhook (service role) and changed by assign_domain() only
create policy "purchased domains readable" on public.purchased_domains for select to authenticated using (public.can_manage_tenant(tenant_id));

-- 7. Media bucket: public read; users write only inside a folder named after their own user id ---------------------
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

-- 8. Make yourself the first super admin (replace the email), then sign in via "Administrator sign in".
-- insert into public.app_admins (user_id) select id from auth.users where email = 'you@example.com';
