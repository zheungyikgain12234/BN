-- Domain selling prices (what the reseller charges per extension and duration) and the domain basket.
-- Run once in the Supabase SQL editor. Only extensions that have a price row appear in Domain Search (API).

create table if not exists public.domain_tld_prices (
  id uuid primary key default gen_random_uuid(),
  tld text not null,                          -- without the dot, lowercase: com, co.uk
  years int not null check (years > 0),
  price numeric(12,2) not null check (price >= 0),
  currency text not null default 'SGD',
  unique (tld, years)
);

create table if not exists public.domain_cart_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  domain text not null,
  years int not null check (years > 0),
  price numeric(12,2) not null,               -- price for the whole duration, as shown when added
  currency text not null default 'SGD',
  created_at timestamptz not null default now(),
  unique (user_id, domain)
);

alter table public.domain_tld_prices enable row level security;
alter table public.domain_cart_items enable row level security;

drop policy if exists "domain prices readable" on public.domain_tld_prices;
create policy "domain prices readable" on public.domain_tld_prices for select to authenticated using (true);
drop policy if exists "domain prices managed" on public.domain_tld_prices;
create policy "domain prices managed" on public.domain_tld_prices for all to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());

drop policy if exists "own domain cart" on public.domain_cart_items;
create policy "own domain cart" on public.domain_cart_items for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and not public.is_app_admin()); -- super admins never buy

-- Starter prices (SGD, per whole duration; the panel quotes in SGD). Edit them in Master Data > Domain prices.
insert into public.domain_tld_prices (tld, years, price) values
  ('com', 1, 21.74), ('com', 2, 43.48),
  ('net', 1, 24.00), ('org', 1, 22.00),
  ('co.uk', 1, 14.06), ('uk', 1, 14.06), ('org.uk', 1, 14.06)
on conflict (tld, years) do nothing;
