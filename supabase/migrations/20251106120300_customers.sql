create table public.customers (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id) on delete restrict,
  -- Assigned by the customers_assign_code trigger below; never chosen by
  -- the client. Human-readable, scoped per shop (not globally unique).
  customer_code text not null,
  full_name text not null check (char_length(trim(full_name)) > 0),
  -- `mobile` is what was entered (may include spaces, +91, dashes).
  -- `mobile_normalized` is the search/lookup form: digits-only, last 10.
  -- Deliberately NOT unique — see customers_mobile_normalized_idx comment
  -- below for why a phone number is not treated as an identity key here.
  mobile text not null,
  mobile_normalized text not null,
  alternate_mobile text,
  address text not null check (char_length(trim(address)) > 0),
  id_proof_type text not null
    check (id_proof_type in ('AADHAAR', 'PAN', 'VOTER_ID', 'DRIVING_LICENCE')),
  id_proof_number text not null check (char_length(trim(id_proof_number)) > 0),
  -- Object key inside the private `customer-photos` Storage bucket, e.g.
  -- "<shop_id>/<customer_id>/id-proof.jpg". Nullable: a photo is optional.
  photo_path text,
  notes text,
  is_active boolean not null default true,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint customers_shop_code_unique unique (shop_id, customer_code),
  constraint customers_mobile_normalized_format
    check (mobile_normalized ~ '^[6-9][0-9]{9}$')
);

create index customers_shop_id_idx on public.customers (shop_id);

-- Search index for "does this phone number already have a customer record"
-- lookups (Workflow 1's duplicate-phone warning) and for the Customer
-- Records search bar. NOT a unique index: a household can legitimately
-- share one number, and typos/reassigned SIMs happen — per
-- docs/08-security-threat-checklist.md and docs/03-business-workflows.md,
-- a duplicate phone is a prompt to check, not a hard rejection.
create index customers_mobile_normalized_idx
  on public.customers (shop_id, mobile_normalized);

create index customers_full_name_search_idx
  on public.customers using gin (to_tsvector('simple', full_name));

create trigger customers_set_updated_at
  before update on public.customers
  for each row execute function public.set_updated_at();

comment on table public.customers is
  'Shop customers. mobile_normalized is for search only, never a uniqueness/identity key.';
comment on column public.customers.mobile_normalized is
  'Digits-only, last 10 digits of mobile — for search/lookup. Deliberately not unique.';

-- ---------------------------------------------------------------------
-- Mobile normalization: enforced server-side so correctness never
-- depends on the client doing it right (defense in depth, matching
-- docs/09-error-handling-validation-backup.md's two-layer validation
-- rule).
-- ---------------------------------------------------------------------

create or replace function public.normalize_mobile_number(raw text)
returns text
language sql
immutable
as $$
  select right(regexp_replace(coalesce(raw, ''), '\D', '', 'g'), 10);
$$;

comment on function public.normalize_mobile_number(text) is
  'Strips everything but digits and keeps the last 10 — e.g. "+91 98230-11223" -> "9823011223".';

create or replace function public.customers_normalize_mobile()
returns trigger
language plpgsql
as $$
begin
  new.mobile_normalized := public.normalize_mobile_number(new.mobile);
  return new;
end;
$$;

create trigger customers_normalize_mobile_trigger
  before insert or update of mobile on public.customers
  for each row execute function public.customers_normalize_mobile();

-- ---------------------------------------------------------------------
-- customer_code assignment: a per-shop sequential human-readable code
-- (C-00001, C-00002, ...), assigned server-side so two devices creating
-- customers for the same shop at the same moment can never collide.
-- The `UPDATE ... RETURNING` takes a row lock on the shop, serializing
-- concurrent inserts for that shop (see shops.sql's comment).
-- ---------------------------------------------------------------------

-- SECURITY DEFINER: this must update shops.next_customer_seq regardless
-- of the inserting user's own role — shops is owner-only for direct
-- UPDATEs (see RLS migration), which would otherwise make this silently
-- fail (0 rows matched, no error) for a manager/staff inserting a
-- customer. Caught by supabase/tests/rls_and_constraints.test.sql.
create or replace function public.customers_assign_code()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seq integer;
begin
  if new.customer_code is not null then
    return new;
  end if;

  update public.shops
    set next_customer_seq = next_customer_seq + 1
    where id = new.shop_id
    returning next_customer_seq - 1 into v_seq;

  if v_seq is null then
    raise exception 'customers_assign_code: shop % does not exist', new.shop_id;
  end if;

  new.customer_code := 'C-' || lpad(v_seq::text, 5, '0');
  return new;
end;
$$;

create trigger customers_assign_code_trigger
  before insert on public.customers
  for each row execute function public.customers_assign_code();
