-- Append-only by construction: no updated_at column, and (see the RLS
-- migration) no UPDATE/DELETE policy is ever granted to normal users —
-- only the record_payment() SECURITY DEFINER function may insert here.

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  -- Denormalized from transactions.shop_id — see jewellery_items.sql's
  -- comment on the same pattern.
  shop_id uuid not null references public.shops (id) on delete restrict,
  transaction_id uuid not null references public.transactions (id) on delete restrict,

  amount numeric(14, 2) not null check (amount > 0),
  payment_type text not null
    check (payment_type in ('INTEREST', 'PARTIAL_PRINCIPAL', 'FULL_CLOSURE')),
  payment_method text not null
    check (payment_method in ('CASH', 'UPI', 'BANK_TRANSFER')),
  payment_date date not null,
  receipt_number text,
  received_by uuid not null references public.profiles (id),
  notes text,
  created_at timestamptz not null default now()
);

create index payments_transaction_id_idx on public.payments (transaction_id);
create index payments_shop_date_idx on public.payments (shop_id, payment_date);

comment on table public.payments is
  'Append-only record of money received at the counter. Never updated or deleted by normal users — see RLS migration.';

create or replace function public.payments_set_shop_id()
returns trigger
language plpgsql
as $$
begin
  select t.shop_id into new.shop_id
    from public.transactions t
    where t.id = new.transaction_id;

  if new.shop_id is null then
    raise exception 'payments_set_shop_id: transaction % does not exist', new.transaction_id;
  end if;

  return new;
end;
$$;

create trigger payments_set_shop_id_trigger
  before insert on public.payments
  for each row execute function public.payments_set_shop_id();
