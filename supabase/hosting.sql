-- Web hosting: selling prices, basket and orders (same shape as domains.sql + domain_orders.sql).
-- Run once in the Supabase SQL editor (after domains.sql, which defines public.is_app_admin()).
-- Only plans that have a price row appear on the Web Hosting page. Add them in Master Data > Hosting prices.

create table if not exists public.hosting_plan_prices (
  id uuid primary key default gen_random_uuid(),
  plan_name text not null,                    -- shown to customers
  package_type_id text not null,              -- 20i package type id (Master Data can pick it from 20i)
  months int not null check (months > 0),
  price numeric(12,2) not null check (price >= 0),  -- for the whole period
  currency text not null default 'SGD',
  unique (package_type_id, months)
);

create table if not exists public.hosting_cart_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  package_type_id text not null,
  plan_name text not null,
  months int not null check (months > 0),
  domain text not null,                       -- the domain the hosting package is created for
  price numeric(12,2) not null,               -- display only: hosting-checkout re-prices from hosting_plan_prices
  currency text not null default 'SGD',
  created_at timestamptz not null default now(),
  unique (user_id, domain)
);

create table if not exists public.hosting_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'paid', 'failed')),
  currency text not null,
  total numeric(12,2) not null,
  stripe_session_id text unique,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);

create table if not exists public.hosting_order_items (
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

create index if not exists hosting_orders_user_idx on public.hosting_orders (user_id, created_at desc);
create index if not exists hosting_order_items_order_idx on public.hosting_order_items (order_id);

alter table public.hosting_plan_prices enable row level security;
alter table public.hosting_cart_items enable row level security;
alter table public.hosting_orders enable row level security;
alter table public.hosting_order_items enable row level security;

drop policy if exists "hosting prices readable" on public.hosting_plan_prices;
create policy "hosting prices readable" on public.hosting_plan_prices for select to authenticated using (true);
drop policy if exists "hosting prices managed" on public.hosting_plan_prices;
create policy "hosting prices managed" on public.hosting_plan_prices for all to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());

drop policy if exists "own hosting cart" on public.hosting_cart_items;
create policy "own hosting cart" on public.hosting_cart_items for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and not public.is_app_admin()); -- super admins never buy

-- Customers only read their own orders; the checkout / webhook Edge Functions write with the service role.
drop policy if exists "own hosting orders" on public.hosting_orders;
create policy "own hosting orders" on public.hosting_orders for select to authenticated using (user_id = auth.uid());
drop policy if exists "own hosting order items" on public.hosting_order_items;
create policy "own hosting order items" on public.hosting_order_items for select to authenticated
  using (exists (select 1 from public.hosting_orders o where o.id = order_id and o.user_id = auth.uid()));
