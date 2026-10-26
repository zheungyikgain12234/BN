-- Domain orders: one order per checkout, one item per domain.
-- Run once in the Supabase SQL editor (after domains.sql).
-- Customers can only read their own orders; the checkout / webhook Edge Functions write with the service role.

create table if not exists public.domain_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'paid', 'failed')),
  currency text not null,
  total numeric(12,2) not null,
  stripe_session_id text unique,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);

create table if not exists public.domain_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.domain_orders on delete cascade,
  domain text not null,
  years int not null check (years > 0),
  price numeric(12,2) not null,
  -- pending: waiting for payment | test_registered: paid, registration only simulated
  -- registered: really registered with 20i | failed: paid but registration failed (see note)
  status text not null default 'pending' check (status in ('pending', 'test_registered', 'registered', 'failed')),
  note text
);

create index if not exists domain_orders_user_idx on public.domain_orders (user_id, created_at desc);
create index if not exists domain_order_items_order_idx on public.domain_order_items (order_id);

alter table public.domain_orders enable row level security;
alter table public.domain_order_items enable row level security;

drop policy if exists "own domain orders" on public.domain_orders;
create policy "own domain orders" on public.domain_orders for select to authenticated using (user_id = auth.uid());

drop policy if exists "own domain order items" on public.domain_order_items;
create policy "own domain order items" on public.domain_order_items for select to authenticated
  using (exists (select 1 from public.domain_orders o where o.id = order_id and o.user_id = auth.uid()));
