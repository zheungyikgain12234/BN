-- SSL certificates: selling prices, basket, orders and purchased certificates (same buy-then-assign flow as
-- licenses, domains, hosting and VPS). Run once in the Supabase SQL editor (after reseller.sql and domains.sql, which
-- define public.is_app_admin(), can_manage_tenant() and public.clients).
-- Only certificates that have a price row appear on the SSL page. Edit them in Master Data > SSL prices.

create table if not exists public.ssl_plan_prices (
  id uuid primary key default gen_random_uuid(),
  plan_name text not null,                    -- shown to customers, e.g. Simple SSL
  class_code text not null,                   -- 20i class-code: tucows-rapidssl | tucows-rapidssl_wildcard | tucows-truebizid_ev
  months int not null check (months > 0),
  price numeric(12,2) not null check (price >= 0),  -- for the whole period
  currency text not null default 'SGD',
  unique (class_code, months)
);

create table if not exists public.ssl_cart_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  class_code text not null,
  plan_name text not null,
  months int not null check (months > 0),
  hostname text not null,                     -- the name on the certificate, e.g. www.example.com or *.example.com
  verification text not null check (verification in ('email', 'dns', 'file')),
  contact jsonb not null,                     -- certificate contact details (individual or business, name, address...)
  price numeric(12,2) not null,               -- display only: ssl-checkout re-prices from ssl_plan_prices
  currency text not null default 'SGD',
  created_at timestamptz not null default now(),
  unique (user_id, hostname, class_code)
);

create table if not exists public.ssl_orders (
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

create table if not exists public.ssl_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.ssl_orders on delete cascade,
  class_code text not null,
  plan_name text not null,
  months int not null check (months > 0),
  hostname text not null,
  verification text not null,
  contact jsonb not null,
  price numeric(12,2) not null,
  -- test_registered: paid, ordering only simulated | registered: really ordered at 20i | failed: see note
  status text not null default 'pending' check (status in ('pending', 'test_registered', 'registered', 'failed')),
  note text
);

create table if not exists public.purchased_ssl (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  order_item_id uuid unique references public.ssl_order_items on delete set null,
  plan_name text not null,
  class_code text not null,
  months int not null check (months > 0),
  hostname text not null,
  verification text not null,
  unit_price numeric(12,2) not null,           -- price the reseller paid us (Master Data price at checkout)
  currency text not null,
  status text not null check (status in ('test_registered', 'registered', 'failed')),
  note text,
  purchased_at timestamptz not null default now(),
  client_id uuid references public.clients on delete set null,
  sell_price numeric(12,2),                    -- what the client pays (reseller markup included)
  assigned_at timestamptz
);

create index if not exists ssl_orders_user_idx on public.ssl_orders (user_id, created_at desc);
create index if not exists ssl_order_items_order_idx on public.ssl_order_items (order_id);
create index if not exists purchased_ssl_tenant_idx on public.purchased_ssl (tenant_id);
create index if not exists purchased_ssl_client_idx on public.purchased_ssl (client_id);

alter table public.ssl_plan_prices enable row level security;
alter table public.ssl_cart_items enable row level security;
alter table public.ssl_orders enable row level security;
alter table public.ssl_order_items enable row level security;
alter table public.purchased_ssl enable row level security;

drop policy if exists "ssl prices readable" on public.ssl_plan_prices;
create policy "ssl prices readable" on public.ssl_plan_prices for select to authenticated using (true);
drop policy if exists "ssl prices managed" on public.ssl_plan_prices;
create policy "ssl prices managed" on public.ssl_plan_prices for all to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());

drop policy if exists "own ssl cart" on public.ssl_cart_items;
create policy "own ssl cart" on public.ssl_cart_items for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and not public.is_app_admin()); -- super admins never buy

-- Customers only read their own orders; the checkout / webhook Edge Functions write with the service role.
drop policy if exists "own ssl orders" on public.ssl_orders;
create policy "own ssl orders" on public.ssl_orders for select to authenticated using (user_id = auth.uid());
drop policy if exists "own ssl order items" on public.ssl_order_items;
create policy "own ssl order items" on public.ssl_order_items for select to authenticated
  using (exists (select 1 from public.ssl_orders o where o.id = order_id and o.user_id = auth.uid()));

drop policy if exists "purchased ssl readable" on public.purchased_ssl;
create policy "purchased ssl readable" on public.purchased_ssl for select to authenticated using (public.can_manage_tenant(tenant_id));
-- purchased_ssl rows are created by stripe-webhook (service role) and changed by assign_ssl() only

-- Assign (or unassign with p_client null) one purchased certificate to a client at the reseller's own price.
create or replace function public.assign_ssl(p_ssl uuid, p_client uuid, p_sell_price numeric) returns void
language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid; v_status text;
begin
  select tenant_id, status into v_tenant, v_status from public.purchased_ssl where id = p_ssl;
  if v_tenant is null or not public.can_manage_tenant(v_tenant) then raise exception 'not allowed'; end if;
  if p_client is not null and v_status = 'failed' then raise exception 'This certificate was not ordered, so it cannot be assigned'; end if;
  if p_client is not null and not exists (select 1 from public.clients where id = p_client and tenant_id = v_tenant) then
    raise exception 'Client does not belong to this company';
  end if;
  update public.purchased_ssl
     set client_id = p_client,
         sell_price = case when p_client is null then null else p_sell_price end,
         assigned_at = case when p_client is null then null else now() end
   where id = p_ssl;
end $$;

grant execute on function public.assign_ssl(uuid, uuid, numeric) to authenticated;

-- Starter certificates, with the one-year prices the panel shop shows (SGD). Only starting values:
-- set your own selling prices in Master Data > SSL prices.
insert into public.ssl_plan_prices (plan_name, class_code, months, price, currency) values
  ('Simple SSL',         'tucows-rapidssl',          12,  63.96, 'SGD'),
  ('Extended SSL',       'tucows-truebizid_ev',      12, 345.00, 'SGD'),
  ('Rapid SSL Wildcard', 'tucows-rapidssl_wildcard', 12, 127.93, 'SGD')
on conflict (class_code, months) do nothing;
