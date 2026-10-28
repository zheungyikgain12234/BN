-- VPS add-ons: cPanel licence, snapshot backup and extra disks, chosen on the VPS page and ordered from 20i right after
-- the server is created (20i addVpsAddon). Run once in the Supabase SQL editor (after vps.sql).
-- Only add-ons that have a price row are offered. Edit them in Master Data > VPS add-on prices.

create table if not exists public.vps_addon_prices (
  id uuid primary key default gen_random_uuid(),
  label text not null,                        -- shown to customers, e.g. cPanel Pro (Max 30 Sites)
  product_spec text not null,                 -- 20i productSpec: vps_addon-cpanelpro | vps_addon-backup | vps_addon-disk100GB ...
  months int not null check (months > 0),     -- billing period; the add-on renews separately from the server
  price numeric(12,2) not null check (price >= 0),  -- for the whole period
  currency text not null default 'SGD',
  unique (product_spec, months)
);

alter table public.vps_addon_prices enable row level security;
drop policy if exists "vps addon prices readable" on public.vps_addon_prices;
create policy "vps addon prices readable" on public.vps_addon_prices for select to authenticated using (true);
drop policy if exists "vps addon prices managed" on public.vps_addon_prices;
create policy "vps addon prices managed" on public.vps_addon_prices for all to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());

-- The add-ons picked for a server: a list of { spec, months } in the basket, and { spec, label, months, price } once
-- ordered (the price is re-read from vps_addon_prices at checkout).
alter table public.vps_cart_items add column if not exists addons jsonb not null default '[]';
alter table public.vps_order_items add column if not exists addons jsonb not null default '[]';
alter table public.purchased_vps add column if not exists addons jsonb not null default '[]';

-- Starter add-ons, with the monthly prices the panel shop shows (SGD). The backup price is not seeded: use
-- Master Data > VPS add-on prices > Pick from 20i to add it. Only starting values: set your own selling prices there.
insert into public.vps_addon_prices (label, product_spec, months, price, currency) values
  ('cPanel Admin (Max 5 Sites)',    'vps_addon-cpaneladmin',   1,  38.37, 'SGD'),
  ('cPanel Pro (Max 30 Sites)',     'vps_addon-cpanelpro',     1,  51.17, 'SGD'),
  ('cPanel Plus (Max 50 Sites)',    'vps_addon-cpanelplus',    1,  63.96, 'SGD'),
  ('cPanel Premier (Max 100 Sites)','vps_addon-cpanelpremier', 1,  76.75, 'SGD'),
  ('VPS 100GB Disk',                'vps_addon-disk100GB',     1,  12.79, 'SGD'),
  ('VPS 200GB Disk',                'vps_addon-disk200GB',     1,  25.59, 'SGD'),
  ('VPS 1000GB Disk',               'vps_addon-disk1000GB',    1, 127.95, 'SGD'),
  ('VPS 2000GB Disk',               'vps_addon-disk2000GB',    1, 255.89, 'SGD')
on conflict (product_spec, months) do nothing;
