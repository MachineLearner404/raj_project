-- A native enum gives us strong typing end-to-end (Postgres -> generated
-- TS types) at the cost of ALTER TYPE ... ADD VALUE being a little more
-- ceremonial than a text+CHECK if a new status is ever needed — an
-- acceptable trade for a closed, deliberately small status set.
create type public.transaction_status as enum (
  'ACTIVE',
  'PARTIALLY_PAID',
  'REDEEMED',
  'CANCELLED'
);

comment on type public.transaction_status is
  'ACTIVE: disbursed, nothing repaid yet. PARTIALLY_PAID: some principal repaid. '
  'REDEEMED: fully repaid, jewellery released. CANCELLED: voided, never disbursed-in-effect. '
  '"Overdue" is NOT a stored status — it is derived (due date vs. interest_events) by the '
  'reporting layer, per docs/02-database-schema-erd.md Workflow 7.';

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id) on delete restrict,
  -- Assigned by transactions_assign_code below; never chosen by the client.
  pledge_code text not null,
  customer_id uuid not null references public.customers (id) on delete restrict,

  principal_amount numeric(14, 2) not null check (principal_amount > 0),
  interest_rate_percent_per_month numeric(5, 2) not null
    check (interest_rate_percent_per_month > 0),
  -- Reducing balance (Option B — docs/04-interest-calculation.md). Starts
  -- equal to principal_amount; only ever moves via record_payment().
  outstanding_principal numeric(14, 2) not null check (outstanding_principal >= 0),
  -- Last month-boundary interest has been fully settled through. Starts
  -- at issue_date (nothing owed yet).
  interest_settled_through date not null,

  issue_date date not null,
  tenure_months integer not null check (tenure_months > 0),
  due_date date not null check (due_date >= issue_date),

  status public.transaction_status not null default 'ACTIVE',
  closure_type text check (closure_type in ('REDEEMED', 'CANCELLED')),
  closed_at timestamptz,

  notes text,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint transactions_shop_code_unique unique (shop_id, pledge_code),
  constraint transactions_balance_sane check (outstanding_principal <= principal_amount),
  -- closed_at is set if and only if the transaction is in a terminal state.
  constraint transactions_closed_at_matches_status check (
    (status in ('REDEEMED', 'CANCELLED')) = (closed_at is not null)
  ),
  constraint transactions_closure_type_matches_status check (
    (status = 'REDEEMED' and closure_type = 'REDEEMED')
    or (status = 'CANCELLED' and closure_type = 'CANCELLED')
    or (status in ('ACTIVE', 'PARTIALLY_PAID') and closure_type is null)
  )
);

create index transactions_shop_id_idx on public.transactions (shop_id);
create index transactions_customer_id_idx on public.transactions (customer_id);
create index transactions_shop_status_idx on public.transactions (shop_id, status);
create index transactions_due_date_idx on public.transactions (shop_id, due_date)
  where status in ('ACTIVE', 'PARTIALLY_PAID');

create trigger transactions_set_updated_at
  before update on public.transactions
  for each row execute function public.set_updated_at();

comment on table public.transactions is
  'A jewellery pledge/loan. "transaction" per the agreed Phase 2 naming; this is what docs/0x call a "loan".';

-- ---------------------------------------------------------------------
-- pledge_code assignment — same per-shop-locking pattern as
-- customers_assign_code (see customers.sql).
-- ---------------------------------------------------------------------

-- SECURITY DEFINER for the same reason as customers_assign_code() (see
-- that function's comment) — harmless here since the only current caller
-- (create_transaction()) is already SECURITY DEFINER, but keeps this
-- function correct independently if that ever changes.
create or replace function public.transactions_assign_code()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seq integer;
begin
  if new.pledge_code is not null then
    return new;
  end if;

  update public.shops
    set next_pledge_seq = next_pledge_seq + 1
    where id = new.shop_id
    returning next_pledge_seq - 1 into v_seq;

  if v_seq is null then
    raise exception 'transactions_assign_code: shop % does not exist', new.shop_id;
  end if;

  new.pledge_code := 'JL-' || extract(year from coalesce(new.issue_date, current_date))::text
    || '-' || lpad(v_seq::text, 5, '0');
  return new;
end;
$$;

create trigger transactions_assign_code_trigger
  before insert on public.transactions
  for each row execute function public.transactions_assign_code();

-- ---------------------------------------------------------------------
-- Controlled status transitions. Enforced at the database level so this
-- holds even for a direct UPDATE, not just through record_payment().
-- Allowed: ACTIVE -> {PARTIALLY_PAID, REDEEMED, CANCELLED}
--          PARTIALLY_PAID -> {REDEEMED, CANCELLED}
-- REDEEMED and CANCELLED are terminal — no transitions out.
-- ---------------------------------------------------------------------

create or replace function public.transactions_enforce_status_transition()
returns trigger
language plpgsql
as $$
begin
  if old.status = new.status then
    return new;
  end if;

  if old.status = 'ACTIVE'
     and new.status in ('PARTIALLY_PAID', 'REDEEMED', 'CANCELLED') then
    return new;
  elsif old.status = 'PARTIALLY_PAID'
     and new.status in ('REDEEMED', 'CANCELLED') then
    return new;
  else
    raise exception
      'Invalid transaction status transition: % -> % (transaction %)',
      old.status, new.status, old.id;
  end if;
end;
$$;

create trigger transactions_status_transition_trigger
  before update of status on public.transactions
  for each row execute function public.transactions_enforce_status_transition();
