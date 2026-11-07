-- Money-moving RPC functions. Per docs/01-architecture.md: these are the
-- ONLY way transactions/payments/interest_events are ever written — the
-- RLS migration grants NO direct INSERT/UPDATE policy on those three
-- tables to normal users, so a client bypassing these functions cannot
-- write to them at all, only read.
--
-- Each function is SECURITY DEFINER (runs as the table owner, bypassing
-- RLS) and therefore does its OWN authorization check internally — never
-- assume RLS is still protecting you inside a SECURITY DEFINER body.
--
-- Scope note: record_payment() here is the Phase 2 version — it records
-- what was received and safely updates balances/status under a row lock,
-- but does NOT yet compute what interest *should* be due (that's the
-- completed-month/reducing-principal algorithm in
-- docs/04-interest-calculation.md, already implemented and unit-tested
-- client-side in src/lib/calculations/interest.ts). Porting that exact
-- algorithm into this function, so the two stay in lockstep per
-- docs/09-error-handling-validation-backup.md, is explicitly Phase 3
-- scope — marked below with TODO(Phase 3).

create or replace function public.create_transaction(
  p_customer_id uuid,
  p_principal_amount numeric,
  p_interest_rate_percent_per_month numeric,
  p_issue_date date,
  p_tenure_months integer,
  p_items jsonb -- array of {category, description, gross_weight_grams, net_weight_grams, stone_weight_grams, purity_karat, gold_rate_used_per_gram, estimated_value, condition_notes}
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
begin
  if public.current_role() not in ('owner', 'manager') then
    raise exception 'create_transaction: role % is not permitted to create loans', public.current_role();
  end if;

  if not exists (
    select 1 from public.customers
    where id = p_customer_id and shop_id = v_shop_id
  ) then
    raise exception 'create_transaction: customer % not found in your shop', p_customer_id;
  end if;

  if jsonb_array_length(p_items) < 1 then
    raise exception 'create_transaction: at least one jewellery item is required';
  end if;

  insert into public.transactions (
    shop_id, customer_id, principal_amount, interest_rate_percent_per_month,
    outstanding_principal, interest_settled_through, issue_date, tenure_months,
    due_date, created_by
  ) values (
    v_shop_id, p_customer_id, p_principal_amount, p_interest_rate_percent_per_month,
    p_principal_amount, p_issue_date, p_issue_date, p_tenure_months,
    p_issue_date + make_interval(months => p_tenure_months), auth.uid()
  )
  returning * into v_transaction;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    insert into public.jewellery_items (
      transaction_id, category, description, gross_weight_grams, net_weight_grams,
      stone_weight_grams, purity_karat, gold_rate_used_per_gram, estimated_value,
      condition_notes
    ) values (
      v_transaction.id,
      v_item ->> 'category',
      v_item ->> 'description',
      (v_item ->> 'gross_weight_grams')::numeric,
      (v_item ->> 'net_weight_grams')::numeric,
      coalesce((v_item ->> 'stone_weight_grams')::numeric, 0),
      (v_item ->> 'purity_karat')::smallint,
      (v_item ->> 'gold_rate_used_per_gram')::numeric,
      (v_item ->> 'estimated_value')::numeric,
      v_item ->> 'condition_notes'
    );
  end loop;

  return v_transaction;
end;
$$;

comment on function public.create_transaction(uuid, numeric, numeric, date, integer, jsonb) is
  'Creates a transaction and its jewellery_items atomically. owner/manager only.';

-- ---------------------------------------------------------------------

create or replace function public.record_payment(
  p_transaction_id uuid,
  p_amount numeric,
  p_payment_type text,
  p_payment_method text,
  p_payment_date date
)
returns public.transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shop_id uuid := public.current_shop_id();
  v_txn public.transactions;
  v_payment_id uuid;
begin
  if public.current_role() not in ('owner', 'manager', 'staff') then
    raise exception 'record_payment: role % is not permitted to record payments', public.current_role();
  end if;

  if p_amount <= 0 then
    raise exception 'record_payment: amount must be positive';
  end if;

  if p_payment_type not in ('INTEREST', 'PARTIAL_PRINCIPAL', 'FULL_CLOSURE') then
    raise exception 'record_payment: invalid payment_type %', p_payment_type;
  end if;

  -- Row lock: this is what makes two devices recording a payment on the
  -- same transaction within the same second safe (the second call blocks
  -- until the first commits, then sees the already-updated balance) —
  -- see docs/09-error-handling-validation-backup.md's concurrency section.
  select * into v_txn
    from public.transactions
    where id = p_transaction_id and shop_id = v_shop_id
    for update;

  if v_txn.id is null then
    raise exception 'record_payment: transaction % not found in your shop', p_transaction_id;
  end if;

  if v_txn.status not in ('ACTIVE', 'PARTIALLY_PAID') then
    raise exception 'record_payment: transaction % is % and cannot take payments',
      p_transaction_id, v_txn.status;
  end if;

  insert into public.payments (
    transaction_id, amount, payment_type, payment_method, payment_date, received_by
  ) values (
    p_transaction_id, p_amount, p_payment_type, p_payment_method, p_payment_date, auth.uid()
  )
  returning id into v_payment_id;

  if p_payment_type = 'INTEREST' then
    -- TODO(Phase 3): compute actual interest due via the ported
    -- completed-month algorithm instead of assuming the payment clears
    -- it; interest_due_after is a placeholder (0) until then.
    insert into public.interest_events (
      transaction_id, event_type, amount, principal_balance_after,
      interest_due_after, event_date, related_payment_id, created_by
    ) values (
      p_transaction_id, 'SETTLEMENT', p_amount, v_txn.outstanding_principal,
      0, p_payment_date, v_payment_id, auth.uid()
    );
    -- No principal or status change for an interest-only payment.

  elsif p_payment_type = 'PARTIAL_PRINCIPAL' then
    if p_amount >= v_txn.outstanding_principal then
      raise exception
        'record_payment: amount % is >= outstanding principal % — use FULL_CLOSURE instead',
        p_amount, v_txn.outstanding_principal;
    end if;

    update public.transactions
      set outstanding_principal = outstanding_principal - p_amount,
          status = 'PARTIALLY_PAID'
      where id = p_transaction_id
      returning * into v_txn;

  elsif p_payment_type = 'FULL_CLOSURE' then
    if p_amount != v_txn.outstanding_principal then
      raise exception
        'record_payment: full closure amount % must equal outstanding principal % exactly',
        p_amount, v_txn.outstanding_principal;
    end if;

    update public.transactions
      set outstanding_principal = 0,
          status = 'REDEEMED',
          closure_type = 'REDEEMED',
          closed_at = now()
      where id = p_transaction_id
      returning * into v_txn;
  end if;

  return v_txn;
end;
$$;

comment on function public.record_payment(uuid, numeric, text, text, date) is
  'Records a payment and safely updates balance/status under a row lock. Phase 2: does not yet compute interest due — see TODO(Phase 3) inside.';

-- ---------------------------------------------------------------------

create or replace function public.cancel_transaction(
  p_transaction_id uuid,
  p_reason text
)
returns public.transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shop_id uuid := public.current_shop_id();
  v_txn public.transactions;
begin
  if public.current_role() <> 'owner' then
    raise exception 'cancel_transaction: role % is not permitted to cancel a transaction', public.current_role();
  end if;

  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'cancel_transaction: a reason is required';
  end if;

  select * into v_txn
    from public.transactions
    where id = p_transaction_id and shop_id = v_shop_id
    for update;

  if v_txn.id is null then
    raise exception 'cancel_transaction: transaction % not found in your shop', p_transaction_id;
  end if;

  update public.transactions
    set status = 'CANCELLED',
        closure_type = 'CANCELLED',
        closed_at = now(),
        notes = trim(both E'\n' from coalesce(notes || E'\n', '') || 'Cancelled: ' || p_reason)
    where id = p_transaction_id
    returning * into v_txn;

  return v_txn;
end;
$$;

comment on function public.cancel_transaction(uuid, text) is
  'Voids a transaction with a mandatory reason. owner only.';

-- ---------------------------------------------------------------------
-- Explicit, narrow execute grants. Postgres grants EXECUTE on new
-- functions to PUBLIC by default — relying on that default for
-- SECURITY DEFINER functions is a common real-world misconfiguration, so
-- it is revoked and re-granted explicitly here.
-- ---------------------------------------------------------------------

revoke execute on function public.create_transaction(uuid, numeric, numeric, date, integer, jsonb) from public;
revoke execute on function public.record_payment(uuid, numeric, text, text, date) from public;
revoke execute on function public.cancel_transaction(uuid, text) from public;

grant execute on function public.create_transaction(uuid, numeric, numeric, date, integer, jsonb) to authenticated;
grant execute on function public.record_payment(uuid, numeric, text, text, date) to authenticated;
grant execute on function public.cancel_transaction(uuid, text) to authenticated;
