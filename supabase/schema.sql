-- BizNest Hub schema. Run in the Supabase SQL editor.

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  full_name text,
  job_title text,
  avatar_url text
);

create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text,
  domain text,
  plan text default 'enterprise',
  seats_active int default 0
);

create table public.tenant_members (
  tenant_id uuid references public.tenants on delete cascade,
  user_id uuid references auth.users on delete cascade,
  role text default 'member',
  primary key (tenant_id, user_id)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text,
  description text,
  about text,
  pricing_model text,
  price_label text,
  seat_price text,
  rating numeric default 0,
  rating_count int default 0,
  image_url text,
  publisher text,
  publisher_code text,
  sku text,
  version text,
  billing_cycle text,
  min_commitment text,
  cloud_targets text,
  multi_tenant boolean default false,
  tags text[] default '{}',
  sort_order int default 0
);

create table public.product_screenshots (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products on delete cascade,
  title text, caption text, image_url text not null,
  sort_order int default 0
);

create table public.product_comments (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products on delete cascade,
  user_id uuid references public.profiles on delete cascade default auth.uid(),
  body text not null,
  badge text,
  attachment_name text, attachment_url text, attachment_type text,
  endorsements int default 0,
  replies int default 0,
  created_at timestamptz default now()
);

-- Auto-create a profile on sign-up.
create function public.handle_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name, avatar_url)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email), new.raw_user_meta_data->>'avatar_url');
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Row level security
alter table public.profiles enable row level security;
alter table public.tenants enable row level security;
alter table public.tenant_members enable row level security;
alter table public.products enable row level security;
alter table public.product_screenshots enable row level security;
alter table public.product_comments enable row level security;

create policy "profiles readable" on public.profiles for select to authenticated using (true);
create policy "own profile update" on public.profiles for update to authenticated using (id = auth.uid());
create policy "own memberships" on public.tenant_members for select to authenticated using (user_id = auth.uid());
create policy "member tenants" on public.tenants for select to authenticated
  using (exists (select 1 from public.tenant_members m where m.tenant_id = id and m.user_id = auth.uid()));
create policy "catalog readable" on public.products for select to authenticated using (true);
create policy "screenshots readable" on public.product_screenshots for select to authenticated using (true);
create policy "comments readable" on public.product_comments for select to authenticated using (true);
create policy "post own comment" on public.product_comments for insert to authenticated with check (user_id = auth.uid());
create policy "delete own comment" on public.product_comments for delete to authenticated using (user_id = auth.uid());

-- Seed a tenant for testing (then insert a tenant_members row for your user):
-- insert into tenants (name, code, domain, seats_active) values ('Gain City Digital Innovation Pte Ltd','TEN-94820-SG','gaincity.com.sg',142);
