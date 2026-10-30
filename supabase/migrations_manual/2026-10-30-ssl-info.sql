-- Run once in the Supabase SQL editor (existing project). schema.sql already contains this for fresh installs.
-- Stores what each SSL certificate includes (read from the 20i order-ssl page when the certificate is picked in Master Data).
alter table public.ssl_plan_prices add column if not exists features text[] not null default '{}';
alter table public.ssl_plan_prices add column if not exists summary text not null default '';

create or replace view public.ssl_prices with (security_invoker = true) as
select p.id, p.plan_name, p.class_code, p.months, p.cost, p.profit_percent,
       round(p.cost * (1 + p.profit_percent / 100), 2) as price, 'SGD'::text as currency, p.features, p.summary
from public.ssl_plan_prices p;
grant select on public.ssl_prices to authenticated, service_role;
