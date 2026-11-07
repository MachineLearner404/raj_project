-- Configurable staff capabilities. manager keeps its fixed capabilities
-- from Phase 2 (always can create loans, always can edit customers) —
-- only staff's abilities are owner-configurable, per the Phase 3 brief
-- ("staff can register customers, create loans and record payments
-- according to configured permissions"). Defaults preserve exactly the
-- Phase 2 behavior (staff could already register customers and record
-- payments, but not create loans), so this migration changes nothing
-- about current behavior until an owner actively changes a toggle.

alter table public.app_settings
  add column staff_can_register_customers boolean not null default true,
  add column staff_can_create_loans boolean not null default false,
  add column staff_can_record_payments boolean not null default true;

comment on column public.app_settings.staff_can_create_loans is
  'Owner-configurable. manager can always create loans regardless of this flag.';

-- ---------------------------------------------------------------------
-- Helper: does the CURRENT user have a given capability, accounting for
-- role (owner/manager always yes) and, for staff, the configurable
-- app_settings flag? Centralizes the "role OR (staff AND flag)" check so
-- it's identical everywhere it's used (RLS policy, RPC function).
-- ---------------------------------------------------------------------

create or replace function public.current_user_can(p_capability text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case public.current_role()
    when 'owner' then true
    when 'manager' then true -- manager's capabilities are fixed (Phase 2), not owner-configurable
    when 'staff' then (
      select case p_capability
        when 'register_customers' then s.staff_can_register_customers
        when 'create_loans' then s.staff_can_create_loans
        when 'record_payments' then s.staff_can_record_payments
        else false
      end
      from public.app_settings s
      where s.shop_id = public.current_shop_id()
    )
    else false
  end;
$$;

comment on function public.current_user_can(text) is
  'Capability check for the current user: owner/manager always true; staff gated by the matching app_settings.staff_can_* flag. Capabilities: register_customers | create_loans | record_payments.';

-- ---------------------------------------------------------------------
-- Replace the customers INSERT policy to use the new capability check
-- instead of a hardcoded role list.
-- ---------------------------------------------------------------------

drop policy customers_insert_same_shop on public.customers;

create policy customers_insert_same_shop on public.customers
  for insert to authenticated
  with check (
    shop_id = public.current_shop_id()
    and public.current_user_can('register_customers')
  );

-- ---------------------------------------------------------------------
-- Replace create_transaction()'s hardcoded role check with the
-- capability check (owner/manager unaffected; staff now permitted only
-- when staff_can_create_loans is true).
-- ---------------------------------------------------------------------

create or replace function public.create_transaction(
  p_customer_id uuid,
  p_principal_amount numeric,
  p_interest_rate_percent_per_month numeric,
  p_issue_date date,
  p_tenure_months integer,
  p_items jsonb
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
  if not public.current_user_can('create_loans') then
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

-- ---------------------------------------------------------------------
-- Same for record_payment(): was unconditionally owner/manager/staff,
-- now staff is gated by staff_can_record_payments (default true, so
-- behavior is unchanged unless an owner turns it off).
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
  if not public.current_user_can('record_payments') then
    raise exception 'record_payment: role % is not permitted to record payments', public.current_role();
  end if;

  if p_amount <= 0 then
    raise exception 'record_payment: amount must be positive';
  end if;

  if p_payment_type not in ('INTEREST', 'PARTIAL_PRINCIPAL', 'FULL_CLOSURE') then
    raise exception 'record_payment: invalid payment_type %', p_payment_type;
  end if;

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
    insert into public.interest_events (
      transaction_id, event_type, amount, principal_balance_after,
      interest_due_after, event_date, related_payment_id, created_by
    ) values (
      p_transaction_id, 'SETTLEMENT', p_amount, v_txn.outstanding_principal,
      0, p_payment_date, v_payment_id, auth.uid()
    );

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
