-- The interest accounting trail — append-only, same pattern as payments.
-- One payments row can produce zero, one, or two interest_events rows
-- (e.g. a payment that both settles interest due AND reduces principal).

create table public.interest_events (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id) on delete restrict,
  transaction_id uuid not null references public.transactions (id) on delete restrict,

  event_type text not null check (event_type in ('ACCRUAL', 'SETTLEMENT', 'WAIVER')),
  amount numeric(14, 2) not null check (amount >= 0),
  principal_balance_after numeric(14, 2) not null check (principal_balance_after >= 0),
  interest_due_after numeric(14, 2) not null check (interest_due_after >= 0),
  event_date date not null,
  -- Set when this event was produced by a payment (SETTLEMENT); null for
  -- a pure ACCRUAL event (interest becoming due with no payment yet) or a
  -- manual WAIVER.
  related_payment_id uuid references public.payments (id),

  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now()
);

create index interest_events_transaction_id_idx on public.interest_events (transaction_id);
create index interest_events_shop_date_idx on public.interest_events (shop_id, event_date);

comment on table public.interest_events is
  'Append-only interest accrual/settlement/waiver trail. Never updated or deleted by normal users — see RLS migration.';

create or replace function public.interest_events_set_shop_id()
returns trigger
language plpgsql
as $$
begin
  select t.shop_id into new.shop_id
    from public.transactions t
    where t.id = new.transaction_id;

  if new.shop_id is null then
    raise exception
      'interest_events_set_shop_id: transaction % does not exist', new.transaction_id;
  end if;

  return new;
end;
$$;

create trigger interest_events_set_shop_id_trigger
  before insert on public.interest_events
  for each row execute function public.interest_events_set_shop_id();
