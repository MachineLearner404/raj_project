-- Frozen loan terms and a caller-generated idempotency key make a review
-- screen safe to submit exactly once, even if the browser retries.
alter table public.transactions
  add column interest_type text not null default 'MONTHLY'
    check (interest_type in ('MONTHLY', 'YEARLY', 'FLAT')),
  add column flat_interest_basis numeric(14, 2),
  add column flat_interest_basis_type text not null default 'AMOUNT'
    check (flat_interest_basis_type in ('AMOUNT', 'PERCENT_OF_ORIGINAL')),
  add column idempotency_key uuid;

create unique index transactions_shop_idempotency_key_unique
  on public.transactions (shop_id, idempotency_key)
  where idempotency_key is not null;

alter table public.jewellery_items
  add column jewellery_name text,
  add column metal_type text not null default 'GOLD',
  add column quantity integer not null default 1 check (quantity > 0);

create or replace function public.create_jewellery_loan(
  p_customer_id uuid,
  p_principal_amount numeric,
  p_interest_type text,
  p_interest_rate numeric,
  p_flat_interest_basis numeric,
  p_deposit_date date,
  p_notes text,
  p_idempotency_key uuid,
  p_items jsonb,
  p_flat_interest_basis_type text default 'AMOUNT'
)
returns public.transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shop_id uuid := public.current_shop_id();
  v_transaction public.transactions;
  v_item jsonb;
  v_weight numeric;
  v_quantity integer;
begin
  if not public.current_user_can('create_loans') then
    raise exception 'create_jewellery_loan: role % is not permitted to create loans', public.current_role();
  end if;
  if p_idempotency_key is null then raise exception 'create_jewellery_loan: idempotency key is required'; end if;
  select * into v_transaction from public.transactions
    where shop_id = v_shop_id and idempotency_key = p_idempotency_key;
  if v_transaction.id is not null then return v_transaction; end if;
  if p_principal_amount <= 0 or p_interest_rate <= 0 then raise exception 'create_jewellery_loan: principal and rate must be positive'; end if;
  if p_interest_type not in ('MONTHLY', 'YEARLY', 'FLAT') then raise exception 'create_jewellery_loan: invalid interest type'; end if;
  if p_interest_type = 'FLAT' and (coalesce(p_flat_interest_basis, 0) <= 0 or p_flat_interest_basis_type not in ('AMOUNT', 'PERCENT_OF_ORIGINAL')) then raise exception 'create_jewellery_loan: valid positive flat interest basis is required'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'create_jewellery_loan: at least one item is required'; end if;
  if not exists (select 1 from public.customers where id = p_customer_id and shop_id = v_shop_id and is_active) then raise exception 'create_jewellery_loan: active customer not found in your shop'; end if;

  insert into public.transactions (shop_id, customer_id, principal_amount, interest_rate_percent_per_month, outstanding_principal, interest_settled_through, issue_date, tenure_months, due_date, notes, created_by, interest_type, flat_interest_basis, flat_interest_basis_type, idempotency_key)
  values (v_shop_id, p_customer_id, p_principal_amount,
    case when p_interest_type = 'YEARLY' then p_interest_rate / 12 else p_interest_rate end,
    p_principal_amount, p_deposit_date, p_deposit_date, 12, p_deposit_date + interval '12 months', nullif(trim(p_notes), ''), auth.uid(), p_interest_type,
    case when p_interest_type = 'FLAT' then p_flat_interest_basis else null end,
    case when p_interest_type = 'FLAT' then p_flat_interest_basis_type else 'AMOUNT' end, p_idempotency_key)
  returning * into v_transaction;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_weight := (v_item ->> 'weight_grams')::numeric;
    v_quantity := coalesce((v_item ->> 'quantity')::integer, 1);
    if v_weight <= 0 or v_quantity <= 0 or coalesce(nullif(trim(v_item ->> 'jewellery_name'), ''), '') = '' then
      raise exception 'create_jewellery_loan: item name, weight and quantity must be positive';
    end if;
    insert into public.jewellery_items (transaction_id, category, description, gross_weight_grams, net_weight_grams, purity_karat, gold_rate_used_per_gram, estimated_value, condition_notes, jewellery_name, metal_type, quantity)
    values (v_transaction.id, 'OTHER', v_item ->> 'jewellery_name', v_weight, v_weight, 22, 1, greatest(v_weight * v_quantity, 0.01), nullif(trim(v_item ->> 'notes'), ''), v_item ->> 'jewellery_name', coalesce(nullif(trim(v_item ->> 'metal_type'), ''), 'GOLD'), v_quantity);
  end loop;
  return v_transaction;
exception when unique_violation then
  select * into v_transaction from public.transactions where shop_id = v_shop_id and idempotency_key = p_idempotency_key;
  if v_transaction.id is not null then return v_transaction; end if;
  raise;
end;
$$;

revoke execute on function public.create_jewellery_loan(uuid, numeric, text, numeric, numeric, date, text, uuid, jsonb, text) from public;
grant execute on function public.create_jewellery_loan(uuid, numeric, text, numeric, numeric, date, text, uuid, jsonb, text) to authenticated;
