-- Reseller model: clients, purchased licenses, checkout. Run AFTER schema.sql, multitenant.sql, catalog.sql. Safe to re-run.
--
-- Roles
--   super admin     : public.app_admins          -> manages companies, users, software, masters; no company, never buys or adds clients
--   reseller admin  : tenant_members.role='admin'  -> manages software + clients, buys licenses, assigns them (with own markup)
--   reseller        : tenant_members.role='member' -> manages software + clients, assigns purchased licenses; cannot buy
-- Clients are private to the reseller company: not even a super admin sees other companies' clients.

-- 1. Every reseller (member) manages their own company's software, not only admins.
create or replace function public.can_manage_tenant(t uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.is_app_admin()
      or exists (select 1 from public.tenant_members where tenant_id = t and user_id = auth.uid())
$$;

-- reseller admin: may buy licenses for tenant t. A super admin belongs to no company and never buys.
create or replace function public.can_buy_for_tenant(t uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select not public.is_app_admin()
     and exists (select 1 from public.tenant_members where tenant_id = t and user_id = auth.uid() and role = 'admin')
$$;

-- 2. Clients of a reseller company
create table if not exists public.clients (
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
create index if not exists clients_tenant_idx on public.clients (tenant_id);

-- 3. Orders (no payment gateway yet: checkout completes immediately) and the licenses they create (one row per unit)
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.licenses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants on delete cascade,
  order_id uuid references public.orders on delete set null,
  product_id uuid not null references public.products on delete restrict,
  unit_price numeric(12,2) not null default 0,   -- catalogue price paid by the reseller
  currency text,
  purchased_at timestamptz not null default now(),
  client_id uuid references public.clients on delete set null,
  sell_price numeric(12,2),                       -- what the client pays (reseller markup included)
  assigned_at timestamptz
);
create index if not exists licenses_tenant_idx on public.licenses (tenant_id);
create index if not exists licenses_client_idx on public.licenses (client_id);

alter table public.clients enable row level security;
alter table public.orders enable row level security;
alter table public.licenses enable row level security;

-- clients: strictly members of the company (no super-admin bypass)
drop policy if exists "clients own company" on public.clients;
create policy "clients own company" on public.clients for all to authenticated
  using (public.is_member(tenant_id)) with check (public.is_member(tenant_id));

drop policy if exists "orders readable" on public.orders;
create policy "orders readable" on public.orders for select to authenticated using (public.can_manage_tenant(tenant_id));

drop policy if exists "licenses readable" on public.licenses;
create policy "licenses readable" on public.licenses for select to authenticated using (public.can_manage_tenant(tenant_id));
-- licenses are created by checkout() and changed by assign_license() only (no direct write policies)

-- 4. Checkout: turns the caller's cart into licenses for tenant p_tenant.
--    p_lines: one entry per license unit, in order: [{ "cart_item_id": uuid, "client_id": uuid|null, "sell_price": number|null }]
--    The n-th entry of a cart item applies to its n-th unit; units without an entry stay unassigned.
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
    select ci.id as cart_id, ci.quantity, p.id as product_id, coalesce(p.price, 0) as price, p.currency
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

      insert into public.licenses (tenant_id, order_id, product_id, unit_price, currency, client_id, sell_price, assigned_at)
      values (p_tenant, v_order, r.product_id, r.price, r.currency, v_client,
              case when v_client is null then null else coalesce(v_price, r.price) end,
              case when v_client is null then null else now() end);
    end loop;
  end loop;

  delete from public.cart_items where user_id = auth.uid();
  return v_order;
end $$;

-- 5. Assign (or unassign with p_client null) one license to a client at the reseller's own price.
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
