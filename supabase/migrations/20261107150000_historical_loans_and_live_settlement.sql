-- Historical pledges use the same append-only payment and interest ledger as
-- counter payments. The calculated settlement is intentionally a read model:
-- never persist a value which becomes stale tomorrow.
alter table public.transactions
  add column if not exists is_historical boolean not null default false;

create or replace function public.calculate_live_settlement(
  p_transaction_id uuid,
  p_as_of date default current_date
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v public.transactions; v_extra numeric(14,2) := 0; v_next date;
  v_period_interest numeric(14,2); v_yearly boolean;
  v_interest_paid numeric(14,2) := 0; v_principal_paid numeric(14,2) := 0;
  v_total_paid numeric(14,2) := 0; v_total_interest numeric(14,2) := 0;
begin
  if auth.uid() is null then raise exception 'calculate_live_settlement: authentication required'; end if;
  if p_as_of > current_date then raise exception 'calculate_live_settlement: future dates are not allowed'; end if;
  select * into v from public.transactions
    where id = p_transaction_id and shop_id = public.current_shop_id();
  if v.id is null then raise exception 'calculate_live_settlement: transaction not found'; end if;
  if p_as_of < v.issue_date then raise exception 'calculate_live_settlement: date precedes deposit date'; end if;

  select coalesce(sum(p.amount), 0), coalesce(sum(p.interest_amount), 0), coalesce(sum(p.principal_amount), 0)
    into v_total_paid, v_interest_paid, v_principal_paid
  from public.payments p
  where p.transaction_id = v.id
    and not exists (select 1 from public.payment_reversals r where r.original_payment_id = p.id);

  if v.status not in ('REDEEMED', 'CANCELLED') then
    if v.interest_type = 'FLAT' then
      if not exists (select 1 from public.interest_events e where e.transaction_id = v.id and e.event_type = 'ACCRUAL') then
        v_extra := case when v.flat_interest_basis_type = 'PERCENT_OF_ORIGINAL'
          then round(v.principal_amount * coalesce(v.flat_interest_basis, 0) / 100, 2)
          else coalesce(v.flat_interest_basis, v.principal_amount * v.interest_rate_percent_per_month / 100) end;
      end if;
    else
      v_yearly := v.interest_type = 'YEARLY';
      loop
        v_next := public.loan_anniversary(v.issue_date, v.interest_periods_settled + 1, v_yearly);
        exit when v_next > p_as_of;
        v_period_interest := round(v.outstanding_principal *
          (case when v_yearly then v.interest_rate_percent_per_month * 12 else v.interest_rate_percent_per_month end) / 100, 2);
        v_extra := v_extra + v_period_interest;
        v.interest_periods_settled := v.interest_periods_settled + 1;
      end loop;
    end if;
  end if;
  select coalesce(sum(e.amount) filter (where e.event_type = 'ACCRUAL'), 0) into v_total_interest
    from public.interest_events e where e.transaction_id = v.id;
  v_total_interest := v_total_interest + v_extra;
  return jsonb_build_object(
    'transaction_id', v.id, 'calculation_date', p_as_of,
    'original_principal', v.principal_amount,
    'previous_principal_repayments', v_principal_paid,
    'remaining_principal', v.outstanding_principal,
    'total_interest_accrued', v_total_interest,
    'previous_interest_paid', v_interest_paid,
    'outstanding_interest', v.accrued_interest + v_extra,
    'total_previous_payments', v_total_paid,
    'amount_payable_today', v.outstanding_principal + v.accrued_interest + v_extra,
    'redeemed', v.status = 'REDEEMED'
  );
end;
$$;
revoke execute on function public.calculate_live_settlement(uuid, date) from public;
grant execute on function public.calculate_live_settlement(uuid, date) to authenticated;

-- Tighten the pre-existing atomic poster: counter payments cannot be dated
-- before the pledge, in the future, or ahead of already posted payments.
create or replace function public.post_payment(
  p_transaction_id uuid, p_amount numeric, p_payment_method text,
  p_payment_date date, p_idempotency_key uuid, p_reference_number text default null,
  p_remarks text default null, p_confirm_jewellery_return boolean default false
) returns public.transactions language plpgsql security definer set search_path=public as $$
declare v public.transactions; e public.transactions; yearly boolean; period_interest numeric;
  interest_paid numeric; principal_paid numeric; pid uuid; v_next_anniversary date;
  v_receipt text; v_prefix text; v_seq bigint; v_will_redeem boolean; v_last_payment_date date;
begin
 if not public.current_user_can('record_payments') then raise exception 'post_payment: not permitted'; end if;
 if p_amount <= 0 or p_idempotency_key is null then raise exception 'post_payment: positive amount and idempotency key required'; end if;
 if p_payment_method not in ('CASH','UPI','BANK_TRANSFER','OTHER') then raise exception 'post_payment: invalid payment method'; end if;
 select * into v from public.transactions where id=p_transaction_id and shop_id=public.current_shop_id() for update;
 if v.id is null or v.status not in ('ACTIVE','PARTIALLY_PAID') then raise exception 'post_payment: active transaction not found'; end if;
 if exists(select 1 from public.payments where transaction_id=v.id and idempotency_key=p_idempotency_key) then return v; end if;
 if p_payment_date < v.issue_date then raise exception 'post_payment: payment date cannot precede deposit date'; end if;
 if p_payment_date > current_date then raise exception 'post_payment: future payment dates are not allowed'; end if;
 select max(payment_date) into v_last_payment_date from public.payments where transaction_id = v.id;
 if v_last_payment_date is not null and p_payment_date < v_last_payment_date then raise exception 'post_payment: payments must be posted in chronological order'; end if;
 yearly := v.interest_type='YEARLY';
 if v.interest_type='FLAT' then
   if not exists(select 1 from public.interest_events where transaction_id=v.id and event_type='ACCRUAL') then
     v.accrued_interest:=v.accrued_interest + case when v.flat_interest_basis_type='PERCENT_OF_ORIGINAL' then round(v.principal_amount*v.flat_interest_basis/100,2) else coalesce(v.flat_interest_basis,v.principal_amount*v.interest_rate_percent_per_month/100) end;
     insert into public.interest_events(transaction_id,event_type,amount,principal_balance_after,interest_due_after,event_date,created_by) values(v.id,'ACCRUAL',v.accrued_interest,v.outstanding_principal,v.accrued_interest,v.issue_date,auth.uid());
   end if;
 else loop
   v_next_anniversary:=public.loan_anniversary(v.issue_date,v.interest_periods_settled+1,yearly); exit when v_next_anniversary>p_payment_date;
   v.interest_periods_settled:=v.interest_periods_settled+1; v.interest_settled_through:=v_next_anniversary;
   period_interest:=round(v.outstanding_principal*(case when yearly then v.interest_rate_percent_per_month*12 else v.interest_rate_percent_per_month end)/100,2);
   v.accrued_interest:=v.accrued_interest+period_interest;
   insert into public.interest_events(transaction_id,event_type,amount,principal_balance_after,interest_due_after,event_date,created_by) values(v.id,'ACCRUAL',period_interest,v.outstanding_principal,v.accrued_interest,v.interest_settled_through,auth.uid());
 end loop; end if;
 interest_paid:=least(p_amount,v.accrued_interest); principal_paid:=p_amount-interest_paid;
 if principal_paid>v.outstanding_principal then raise exception 'post_payment: overpayment is not permitted'; end if;
 v_will_redeem := v.outstanding_principal-principal_paid=0 and v.accrued_interest-interest_paid=0;
 if v_will_redeem and not p_confirm_jewellery_return then raise exception 'post_payment: confirm jewellery return for final settlement'; end if;
 select receipt_number_prefix into v_prefix from public.app_settings where shop_id=v.shop_id;
 update public.shops set next_receipt_seq=next_receipt_seq+1 where id=v.shop_id returning next_receipt_seq-1 into v_seq;
 v_receipt:=v_prefix||'-'||lpad(v_seq::text,6,'0');
 insert into public.payments(transaction_id,amount,payment_type,payment_method,payment_date,received_by,notes,reference_number,receipt_number,interest_amount,principal_amount,idempotency_key)
 values(v.id,p_amount,case when principal_paid=0 then 'INTEREST' when v_will_redeem then 'FULL_CLOSURE' else 'PARTIAL_PRINCIPAL' end,p_payment_method,p_payment_date,auth.uid(),nullif(trim(p_remarks),''),nullif(trim(p_reference_number),''),v_receipt,interest_paid,principal_paid,p_idempotency_key) returning id into pid;
 v.accrued_interest:=v.accrued_interest-interest_paid; v.outstanding_principal:=v.outstanding_principal-principal_paid;
 update public.transactions set accrued_interest=v.accrued_interest,outstanding_principal=v.outstanding_principal,interest_settled_through=v.interest_settled_through,interest_periods_settled=v.interest_periods_settled,status=case when v_will_redeem then 'REDEEMED'::public.transaction_status when v.outstanding_principal<v.principal_amount then 'PARTIALLY_PAID'::public.transaction_status else 'ACTIVE'::public.transaction_status end,closure_type=case when v_will_redeem then 'REDEEMED' else null end,closed_at=case when v_will_redeem then now() else null end,jewellery_returned_at=case when v_will_redeem then p_payment_date else null end,jewellery_returned_by=case when v_will_redeem then auth.uid() else null end where id=v.id returning * into e;
 insert into public.interest_events(transaction_id,event_type,amount,principal_balance_after,interest_due_after,event_date,related_payment_id,created_by) values(v.id,'SETTLEMENT',interest_paid,e.outstanding_principal,e.accrued_interest,p_payment_date,pid,auth.uid());
 return e;
end; $$;
revoke execute on function public.post_payment(uuid,numeric,text,date,uuid,text,text,boolean) from public;
grant execute on function public.post_payment(uuid,numeric,text,date,uuid,text,text,boolean) to authenticated;

create function public.create_historical_jewellery_loan(
  p_customer_id uuid, p_principal_amount numeric, p_interest_type text, p_interest_rate numeric,
  p_flat_interest_basis numeric, p_deposit_date date, p_notes text, p_idempotency_key uuid,
  p_items jsonb, p_previous_payments jsonb default '[]'::jsonb,
  p_flat_interest_basis_type text default 'AMOUNT'
) returns public.transactions language plpgsql security definer set search_path = public as $$
declare v public.transactions; v_id uuid; v_payment jsonb; v_payment_date date; v_payment_key uuid; v_previous_date date; v_seen_keys uuid[] := '{}';
begin
  if not public.current_user_can('create_loans') then raise exception 'create_historical_jewellery_loan: not permitted'; end if;
  if p_deposit_date > current_date then raise exception 'create_historical_jewellery_loan: deposit date must be today or earlier'; end if;
  if jsonb_typeof(p_previous_payments) <> 'array' then raise exception 'create_historical_jewellery_loan: previous payments must be an array'; end if;
  select * into v from public.transactions where shop_id = public.current_shop_id() and idempotency_key = p_idempotency_key;
  if v.id is not null then return v; end if;
  v := public.create_jewellery_loan(p_customer_id,p_principal_amount,p_interest_type,p_interest_rate,p_flat_interest_basis,p_deposit_date,p_notes,p_idempotency_key,p_items,p_flat_interest_basis_type);
  v_id := v.id;
  update public.transactions set is_historical = true where id = v_id returning * into v;
  v_previous_date := p_deposit_date;
  for v_payment in select value from jsonb_array_elements(p_previous_payments) loop
    v_payment_date := (v_payment ->> 'payment_date')::date;
    v_payment_key := (v_payment ->> 'idempotency_key')::uuid;
    if v_payment_date is null or v_payment_key is null or coalesce((v_payment ->> 'amount')::numeric, 0) <= 0 then raise exception 'create_historical_jewellery_loan: each payment needs date, amount, and idempotency key'; end if;
    if v_payment_key = any(v_seen_keys) then raise exception 'create_historical_jewellery_loan: duplicate payment idempotency key'; end if;
    if v_payment_date < p_deposit_date or v_payment_date > current_date then raise exception 'create_historical_jewellery_loan: payment date is outside the permitted range'; end if;
    if v_payment_date < v_previous_date then raise exception 'create_historical_jewellery_loan: payments must be chronological'; end if;
    -- Replayed through the one authoritative poster, so historical payments obey
    -- exactly the counter rules: interest first, then the reducing principal.
    -- Return is pre-confirmed because a historical payment that clears the pledge
    -- is a redemption which already happened at the counter.
    perform public.post_payment(v_id, (v_payment ->> 'amount')::numeric, coalesce(v_payment ->> 'payment_method','CASH'), v_payment_date, v_payment_key, nullif(v_payment ->> 'reference_number',''), nullif(v_payment ->> 'remarks',''), true);
    v_previous_date := v_payment_date;
    v_seen_keys := array_append(v_seen_keys, v_payment_key);
  end loop;
  select * into v from public.transactions where id = v_id;
  return v;
end;
$$;
revoke execute on function public.create_historical_jewellery_loan(uuid,numeric,text,numeric,numeric,date,text,uuid,jsonb,jsonb,text) from public;
grant execute on function public.create_historical_jewellery_loan(uuid,numeric,text,numeric,numeric,date,text,uuid,jsonb,jsonb,text) to authenticated;

comment on function public.calculate_live_settlement(uuid, date) is 'Read-only settlement as of a date. It does not persist projected interest.';
