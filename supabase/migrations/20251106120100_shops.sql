-- Tenant root. Every business table is scoped to a shop_id that traces
-- back here. One row per shop; a shop is provisioned by an admin/onboarding
-- process (service-role key, run outside normal app RLS), not by end users.

create table public.shops (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) > 0),
  address text,
  gstin text,
  phone text,
  -- Per-shop sequence counters, used by the customer_code / pledge_code
  -- assignment triggers (see customers.sql / transactions.sql). Mutated
  -- via `UPDATE ... RETURNING` inside those triggers, which takes a row
  -- lock on the shop row for the duration of the transaction — this is
  -- what makes code assignment safe under concurrent writes from two
  -- devices (see docs/01-architecture.md's concurrency design).
  next_customer_seq integer not null default 1 check (next_customer_seq > 0),
  next_pledge_seq integer not null default 1 check (next_pledge_seq > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger shops_set_updated_at
  before update on public.shops
  for each row execute function public.set_updated_at();

comment on table public.shops is
  'Tenant root. One row per jewellery shop; every business table carries a shop_id back to this table.';
