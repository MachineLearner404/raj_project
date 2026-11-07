-- ============================================================================
-- TEST-ONLY SCAFFOLDING. DO NOT RUN THIS AGAINST A REAL SUPABASE PROJECT.
--
-- A real Supabase project already provides the `auth` and `storage` schemas
-- (managed by GoTrue and the Storage API). This file hand-builds a minimal,
-- close-enough stand-in for both, purely so the actual migrations in
-- supabase/migrations/ — unmodified — can be applied to a plain local
-- Postgres instance and have their RLS policies exercised for real.
--
-- `auth.uid()` here reads the same `request.jwt.claims` GUC that Supabase's
-- real implementation reads, so `SET LOCAL request.jwt.claims = '{"sub":
-- "<uuid>"}'` works identically to how PostgREST sets it per-request in
-- production.
-- ============================================================================

create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text
);

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid;
$$;

create or replace function auth.jwt()
returns jsonb
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claims', true), '')::jsonb;
$$;

-- Supabase's real roles. CREATE ROLE is not transactional in Postgres, so
-- guard each with a catalog check instead of `if not exists` (not
-- supported for ROLE).
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end;
$$;

grant usage on schema public to anon, authenticated, service_role;
grant usage on schema auth to anon, authenticated, service_role;
alter default privileges in schema public grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public grant usage, select on sequences to authenticated;

-- Minimal storage.objects stand-in — just enough for the
-- customer-photos policies to be evaluated against real rows.
create schema if not exists storage;

create table if not exists storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false
);

create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text not null,
  owner uuid
);

create or replace function storage.foldername(name text)
returns text[]
language sql
immutable
as $$
  select (string_to_array(name, '/'))[1 : array_length(string_to_array(name, '/'), 1) - 1];
$$;

grant usage on schema storage to anon, authenticated, service_role;
grant select, insert, update, delete on storage.objects to authenticated;
grant select on storage.buckets to authenticated;

alter table storage.objects enable row level security;
