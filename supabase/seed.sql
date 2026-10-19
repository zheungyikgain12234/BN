-- Sample data: companies, masters (categories, pricing models, currencies, tags), software, screenshots and comments.
-- Run in the Supabase SQL editor AFTER schema.sql, multitenant.sql and catalog.sql. Safe to re-run (never duplicates).
-- Every value the app shows comes from these tables; nothing is hardcoded in the Flutter code.

-- 1. Companies (the company screen, registration dropdown and admin Companies page read these)
insert into public.tenants (name, code, domain, plan, seats_active) values
  ('Gain City Digital Innovation Pte Ltd', 'TEN-94820-SG', 'gaincity.com.sg', 'enterprise', 142),
  ('Northwind Traders',                     'TEN-20417-US', 'northwind.example', 'business',   58),
  ('Contoso Retail Group',                  'TEN-77310-UK', 'contoso.example',   'starter',    12)
on conflict do nothing;

-- 2. Masters
-- Categories (store filter chips). `icon` is a Material icon name resolved by the app.
insert into public.software_categories (name, icon, sort_order) values
  ('Productivity',   'work_outline',          10),
  ('AI & Automation','psychology_outlined',   20),
  ('Security',       'shield_outlined',       30),
  ('Finance & ERP',  'receipt_long_outlined', 40),
  ('Developer Tools','code',                  50),
  ('Marketing',      'campaign_outlined',     60),
  ('Collaboration',  'groups_outlined',       70),
  ('Analytics',      'insights',              80)
on conflict do nothing;

insert into public.pricing_models (name, sort_order) values
  ('Per user', 10), ('Per seat', 20), ('Per device', 30), ('Per store', 40),
  ('Per workspace', 50), ('Flat fee', 60), ('Usage based', 70)
on conflict do nothing;

insert into public.currencies (code, name, sort_order) values
  ('USD', 'US Dollar', 10), ('SGD', 'Singapore Dollar', 20), ('GBP', 'Pound Sterling', 30),
  ('EUR', 'Euro', 40), ('AUD', 'Australian Dollar', 50), ('MYR', 'Malaysian Ringgit', 60)
on conflict do nothing;

insert into public.software_tags (name) values
  ('Office'), ('Email'), ('Teams'), ('EDR'), ('Antivirus'), ('Compliance'), ('AI'), ('Search'), ('Documents'),
  ('ERP'), ('GST'), ('Invoicing'), ('Mobile'), ('Dispatch'), ('Inventory'), ('BI'), ('Dashboards'), ('Reporting'),
  ('Social'), ('Attribution'), ('CI'), ('CD'), ('Automation'), ('POS'), ('Retail'), ('Rota'), ('HR'), ('Payroll')
on conflict do nothing;

-- 3. Software. A null company means the app is shared with every company.
insert into public.products
  (tenant_id, category_id, name, description, about, version, sku, pricing_model, price, currency, tags, sort_order)
select t.id, c.id, v.name, v.description, v.about, v.version, v.sku, v.pricing_model, v.price, v.currency,
       string_to_array(v.tags, ','), v.sort_order
from (values
  -- company, category, name, short description, about, version, sku, pricing model, price, currency, tags, order
  (null, 'Productivity', 'Microsoft 365 Business Premium',
   'Office apps, Teams, email and advanced security for growing teams.',
   'Microsoft 365 Business Premium combines Word, Excel, PowerPoint, Outlook and Teams with device management, threat protection and data-loss prevention in one subscription. Ideal for organisations up to 300 users that need productivity and security together.',
   '2024.3', 'M365-BP-001', 'Per user', 22.00, 'USD', 'Office,Email,Teams', 10),
  (null, 'Security', 'Defender Endpoint Protect',
   'Next-generation endpoint protection with automated investigation.',
   'Cloud-delivered antivirus, endpoint detection and response and attack-surface reduction for Windows, macOS, Linux and mobile devices, managed from a single console.',
   '5.8', 'SEC-DEF-014', 'Per device', 5.20, 'USD', 'EDR,Antivirus,Compliance', 20),
  ('Gain City Digital Innovation Pte Ltd', 'AI & Automation', 'Gain City AI Co-Pilot',
   'An AI assistant that answers questions from your own documents.',
   'Connects to SharePoint, OneDrive and your file servers, then lets staff ask natural-language questions with cited answers. Role-aware, so people only see what they are allowed to see.',
   '3.2.1', 'GC-AI-100', 'Per seat', 18.00, 'SGD', 'AI,Search,Documents', 30),
  ('Gain City Digital Innovation Pte Ltd', 'Finance & ERP', 'Gain City ERP Connector',
   'Sync invoices and GST reports between your ERP and the tax authority.',
   'Instant sync with Singapore IRAS invoice formats and live GST breakdown columns in the transactions ledger. Supports SAP Business One, Oracle NetSuite and Microsoft Dynamics 365.',
   '3.1.0', 'GC-ERP-310', 'Flat fee', 249.00, 'SGD', 'ERP,GST,Invoicing', 40),
  ('Gain City Digital Innovation Pte Ltd', 'Collaboration', 'Field Service Hub',
   'Dispatch technicians, track jobs and collect customer sign-off on mobile.',
   'Scheduling, route planning, parts inventory and e-signature in one mobile-first app, with live status for the back office.',
   '2.4.0', 'GC-FSM-240', 'Per seat', 29.00, 'SGD', 'Mobile,Dispatch,Inventory', 50),
  ('Northwind Traders', 'Analytics', 'Northwind Insight Studio',
   'Self-service dashboards for sales, stock and supplier performance.',
   'Drag-and-drop dashboards over your trading data with scheduled email reports, drill-down and row-level security by region.',
   '6.0', 'NW-ANL-600', 'Per seat', 35.00, 'USD', 'BI,Dashboards,Reporting', 10),
  ('Northwind Traders', 'Marketing', 'Campaign Pilot',
   'Plan, schedule and measure email and social campaigns.',
   'A single calendar for email, social and paid campaigns with audience segments, A/B testing and attribution reports.',
   '4.3', 'NW-MKT-430', 'Per workspace', 99.00, 'USD', 'Email,Social,Attribution', 20),
  ('Northwind Traders', 'Developer Tools', 'Pipeline Runner',
   'Hosted CI/CD with build caching and approval gates.',
   'Run builds and deployments on managed runners with secrets management, environment approvals and audit logs.',
   '1.9', 'NW-DEV-190', 'Usage based', 0.01, 'USD', 'CI,CD,Automation', 30),
  ('Contoso Retail Group', 'Finance & ERP', 'Retail POS Cloud',
   'Point of sale with live stock levels across every store.',
   'Cloud POS for tills and tablets with offline mode, loyalty, returns and end-of-day reconciliation by store.',
   '8.2', 'CT-POS-820', 'Per store', 79.00, 'GBP', 'POS,Retail,Inventory', 10),
  ('Contoso Retail Group', 'Productivity', 'Shift Planner',
   'Staff rota, swaps and time-off requests in one app.',
   'Build rotas from demand forecasts, let staff swap shifts and request leave, and export hours straight to payroll.',
   '2.1', 'CT-HR-210', 'Per seat', 4.50, 'GBP', 'Rota,HR,Payroll', 20)
) as v(company, category, name, description, about, version, sku, pricing_model, price, currency, tags, sort_order)
left join public.tenants t on lower(t.name) = lower(v.company)
join public.software_categories c on lower(c.name) = lower(v.category)
where not exists (
  select 1 from public.products p
  where lower(p.name) = lower(v.name) and p.tenant_id is not distinct from t.id
);

-- 4. Screenshots: three per app that has none yet
insert into public.product_screenshots (product_id, title, caption, image_url, sort_order)
select p.id, s.title, s.caption,
       'https://picsum.photos/seed/' || regexp_replace(lower(p.name), '[^a-z0-9]+', '-', 'g') || '-' || s.n || '/960/600',
       s.n
from public.products p
cross join (values
  (1, 'Overview',  'The main dashboard at a glance.'),
  (2, 'Reports',   'Built-in reports you can export and schedule.'),
  (3, 'Settings',  'Roles, integrations and notifications.')
) as s(n, title, caption)
where not exists (select 1 from public.product_screenshots x where x.product_id = p.id);

-- 5. One starter comment per app (needs at least one registered user; skipped otherwise)
insert into public.product_comments (product_id, user_id, body)
select p.id, (select id from public.profiles order by id limit 1),
       'We have been using this for a few weeks. Setup was quick and the team picked it up without training.'
from public.products p
where exists (select 1 from public.profiles)
  and not exists (select 1 from public.product_comments c where c.product_id = p.id);

-- 6. Optional: make a registered user a company admin (can add software for their company)
-- update public.tenant_members set role = 'admin'
-- where user_id = (select id from auth.users where email = 'admin@company.example');
