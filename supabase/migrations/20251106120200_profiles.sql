-- One row per staff user, 1:1 with auth.users, carrying the shop_id and
-- role that every RLS policy in this project is keyed off.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  shop_id uuid not null references public.shops (id) on delete restrict,
  full_name text not null check (char_length(trim(full_name)) > 0),
  role text not null check (role in ('owner', 'manager', 'staff')),
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index profiles_shop_id_idx on public.profiles (shop_id);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

comment on table public.profiles is
  'Staff accounts: 1:1 with auth.users, carries shop_id + role used by every RLS policy.';

-- ---------------------------------------------------------------------
-- RLS helper functions. SECURITY DEFINER + a pinned search_path so they
-- (a) can read public.profiles even though profiles itself has RLS
--     enabled (avoids the recursive "RLS policy needs a function that
--     needs RLS" chicken-and-egg problem), and
-- (b) can't be hijacked via a malicious search_path.
-- Both are STABLE (not VOLATILE) so Postgres can cache the result within
-- a single statement instead of re-querying per row.
-- ---------------------------------------------------------------------

create or replace function public.current_shop_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select shop_id from public.profiles where id = auth.uid();
$$;

create or replace function public.current_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

comment on function public.current_shop_id() is
  'The shop_id of the currently authenticated user, per their profiles row. Used by every RLS policy in this project.';
comment on function public.current_role() is
  'The role (owner|manager|staff) of the currently authenticated user. Used by RLS policies and RPC functions for authorization checks.';
