-- VPS: selling prices, operating systems, basket, orders and purchased VPS (same buy-then-assign flow as
-- licenses, domains and hosting). Run once in the Supabase SQL editor (after reseller.sql and domains.sql, which
-- define public.is_app_admin(), can_manage_tenant() and public.clients).
-- Only plans that have a price row appear on the VPS page. Add them in Master Data > VPS prices.

create table if not exists public.vps_plan_prices (
  id uuid primary key default gen_random_uuid(),
  plan_name text not null,                    -- shown to customers, e.g. 1 Core Unmanaged VPS
  vps_type text not null,                     -- 20i VPS type, e.g. vps-a (shop product code vps:a); "a" is also accepted
  months int not null check (months > 0),
  price numeric(12,2) not null check (price >= 0),  -- for the whole period
  currency text not null default 'SGD',
  unique (vps_type, months)
);

create table if not exists public.vps_os_options (
  id uuid primary key default gen_random_uuid(),
  label text not null,                        -- shown to customers, e.g. Ubuntu 22.04
  code text not null unique                   -- 20i OS code, e.g. ubuntu22.04
);

create table if not exists public.vps_cart_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  vps_type text not null,
  plan_name text not null,
  months int not null check (months > 0),
  os_code text not null,
  os_label text not null,
  location text not null,                     -- dc_location-lhr (UK) | dc_location-dfw (USA)
  server_name text not null,
  price numeric(12,2) not null,               -- display only: vps-checkout re-prices from vps_plan_prices
  currency text not null default 'SGD',
  created_at timestamptz not null default now(),
  unique (user_id, server_name)
);

create table if not exists public.vps_orders (
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

create table if not exists public.vps_order_items (
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
  -- test_registered: paid, creation only simulated | registered: server really ordered at 20i | failed: see note
  status text not null default 'pending' check (status in ('pending', 'test_registered', 'registered', 'failed')),
  note text
);

create table if not exists public.purchased_vps (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  order_item_id uuid unique references public.vps_order_items on delete set null,
  plan_name text not null,
  vps_type text not null,
  months int not null check (months > 0),
  os_label text not null,
  location text not null,
  server_name text not null,
  unit_price numeric(12,2) not null,           -- price the reseller paid us (Master Data price at checkout)
  currency text not null,
  status text not null check (status in ('test_registered', 'registered', 'failed')),
  note text,
  purchased_at timestamptz not null default now(),
  client_id uuid references public.clients on delete set null,
  sell_price numeric(12,2),                    -- what the client pays (reseller markup included)
  assigned_at timestamptz
);

create index if not exists vps_orders_user_idx on public.vps_orders (user_id, created_at desc);
create index if not exists vps_order_items_order_idx on public.vps_order_items (order_id);
create index if not exists purchased_vps_tenant_idx on public.purchased_vps (tenant_id);
create index if not exists purchased_vps_client_idx on public.purchased_vps (client_id);

alter table public.vps_plan_prices enable row level security;
alter table public.vps_os_options enable row level security;
alter table public.vps_cart_items enable row level security;
alter table public.vps_orders enable row level security;
alter table public.vps_order_items enable row level security;
alter table public.purchased_vps enable row level security;

drop policy if exists "vps prices readable" on public.vps_plan_prices;
create policy "vps prices readable" on public.vps_plan_prices for select to authenticated using (true);
drop policy if exists "vps prices managed" on public.vps_plan_prices;
create policy "vps prices managed" on public.vps_plan_prices for all to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());

drop policy if exists "vps os readable" on public.vps_os_options;
create policy "vps os readable" on public.vps_os_options for select to authenticated using (true);
drop policy if exists "vps os managed" on public.vps_os_options;
create policy "vps os managed" on public.vps_os_options for all to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());

drop policy if exists "own vps cart" on public.vps_cart_items;
create policy "own vps cart" on public.vps_cart_items for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and not public.is_app_admin()); -- super admins never buy

-- Customers only read their own orders; the checkout / webhook Edge Functions write with the service role.
drop policy if exists "own vps orders" on public.vps_orders;
create policy "own vps orders" on public.vps_orders for select to authenticated using (user_id = auth.uid());
drop policy if exists "own vps order items" on public.vps_order_items;
create policy "own vps order items" on public.vps_order_items for select to authenticated
  using (exists (select 1 from public.vps_orders o where o.id = order_id and o.user_id = auth.uid()));

drop policy if exists "purchased vps readable" on public.purchased_vps;
create policy "purchased vps readable" on public.purchased_vps for select to authenticated using (public.can_manage_tenant(tenant_id));
-- purchased_vps rows are created by stripe-webhook (service role) and changed by assign_vps() only

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

-- Starter operating systems (codes copied from the panel's VPS order page). Edit in Master Data > VPS operating systems.
insert into public.vps_os_options (label, code) values
  ('Ubuntu 22.04', 'ubuntu22.04'), ('Ubuntu 20.04', 'ubuntu20.04'), ('Debian 12', 'debian12'), ('Debian 11', 'debian11'),
  ('Alma Linux 9', 'almalinux9'), ('Rocky Linux 9', 'rockylinux9'), ('Fedora 40', 'fedora40'), ('CentOS 7', 'rhel7')
on conflict (code) do nothing;

-- Starter plans: the nine unmanaged VPS products from the panel shop (shop code vps:a ... vps:i -> 20i type vps-a ... vps-i),
-- monthly price in SGD as the shop shows it. These are only starting values: set your own selling prices in
-- Master Data > VPS prices (and add other periods there).
insert into public.vps_plan_prices (plan_name, vps_type, months, price, currency) values
  ('1 Core Unmanaged VPS',  'vps-a', 1,   17.90, 'SGD'),
  ('2 Core Unmanaged VPS',  'vps-b', 1,   25.58, 'SGD'),
  ('4 Core Unmanaged VPS',  'vps-c', 1,   42.21, 'SGD'),
  ('6 Core Unmanaged VPS',  'vps-d', 1,   84.43, 'SGD'),
  ('8 Core Unmanaged VPS',  'vps-e', 1,  135.61, 'SGD'),
  ('10 Core Unmanaged VPS', 'vps-f', 1,  337.76, 'SGD'),
  ('12 Core Unmanaged VPS', 'vps-g', 1,  639.71, 'SGD'),
  ('16 Core Unmanaged VPS', 'vps-h', 1, 1279.44, 'SGD'),
  ('20 Core Unmanaged VPS', 'vps-i', 1, 1535.33, 'SGD')
on conflict (vps_type, months) do nothing;
