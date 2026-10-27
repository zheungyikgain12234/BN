-- Purchased hosting: the hosting version of public.purchased_domains / public.licenses.
-- A reseller admin buys hosting (hosting-checkout + Stripe); when the payment is confirmed, stripe-webhook adds one row
-- here per package, at the price the reseller paid (unit_price). The reseller then assigns each package to a client at
-- their own selling price (assign_hosting), so the difference is their profit.
-- Run once in the Supabase SQL editor (after hosting.sql and reseller.sql).

-- Which company bought it (set by hosting-checkout).
alter table public.hosting_orders add column if not exists tenant_id uuid references public.tenants on delete set null;

create table if not exists public.purchased_hosting (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  order_item_id uuid unique references public.hosting_order_items on delete set null,
  plan_name text not null,
  package_type_id text not null,
  months int not null check (months > 0),
  domain text not null,
  unit_price numeric(12,2) not null,           -- price the reseller paid us (Master Data price at checkout)
  currency text not null,
  -- test_registered: paid, creation only simulated | registered: package really created at 20i | failed: see note
  status text not null check (status in ('test_registered', 'registered', 'failed')),
  note text,
  purchased_at timestamptz not null default now(),
  client_id uuid references public.clients on delete set null,
  sell_price numeric(12,2),                    -- what the client pays (reseller markup included)
  assigned_at timestamptz
);
create index if not exists purchased_hosting_tenant_idx on public.purchased_hosting (tenant_id);
create index if not exists purchased_hosting_client_idx on public.purchased_hosting (client_id);

alter table public.purchased_hosting enable row level security;

drop policy if exists "purchased hosting readable" on public.purchased_hosting;
create policy "purchased hosting readable" on public.purchased_hosting for select to authenticated using (public.can_manage_tenant(tenant_id));
-- rows are created by stripe-webhook (service role) and changed by assign_hosting() only (no direct write policies)

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
