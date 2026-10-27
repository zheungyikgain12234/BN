-- Purchased domains: the domain version of public.licenses.
-- A reseller admin buys domains (domain-checkout + Stripe); when the payment is confirmed, stripe-webhook adds one row
-- here per domain, at the price the reseller paid (unit_price). The reseller then assigns each domain to a client at
-- their own selling price (assign_domain), so the difference is their profit.
-- Run once in the Supabase SQL editor (after reseller.sql and domain_orders.sql).

-- Which company bought it (set by domain-checkout).
alter table public.domain_orders add column if not exists tenant_id uuid references public.tenants on delete set null;

create table if not exists public.purchased_domains (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  order_item_id uuid unique references public.domain_order_items on delete set null,
  domain text not null,
  years int not null check (years > 0),
  unit_price numeric(12,2) not null,           -- price the reseller paid us (Master Data price at checkout)
  currency text not null,
  -- test_registered: paid, registration only simulated | registered: really registered at 20i | failed: see note
  status text not null check (status in ('test_registered', 'registered', 'failed')),
  note text,
  purchased_at timestamptz not null default now(),
  client_id uuid references public.clients on delete set null,
  sell_price numeric(12,2),                    -- what the client pays (reseller markup included)
  assigned_at timestamptz
);
create index if not exists purchased_domains_tenant_idx on public.purchased_domains (tenant_id);
create index if not exists purchased_domains_client_idx on public.purchased_domains (client_id);

alter table public.purchased_domains enable row level security;

drop policy if exists "purchased domains readable" on public.purchased_domains;
create policy "purchased domains readable" on public.purchased_domains for select to authenticated using (public.can_manage_tenant(tenant_id));
-- rows are created by stripe-webhook (service role) and changed by assign_domain() only (no direct write policies)

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
