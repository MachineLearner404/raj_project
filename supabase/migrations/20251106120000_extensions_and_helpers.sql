-- Extensions and shared helper functions used by every later migration.
-- Safe to run on a real Supabase project: pgcrypto is already enabled there,
-- and `auth`/`storage` schemas already exist (managed by Supabase) — this
-- migration does not touch them.

create extension if not exists "pgcrypto";

-- Generic "touch updated_at on every UPDATE" trigger, reused by every table
-- that has an updated_at column.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function public.set_updated_at() is
  'BEFORE UPDATE trigger: stamps updated_at = now() on every row update.';
