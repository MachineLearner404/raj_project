-- Phase 13: retain an immutable reversal record rather than editing or
-- deleting financial rows. Only the most recent payment on a non-terminal
-- pledge may be reversed, which prevents historical balance rewrites.

create table public.payment_reversals (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete restrict,
  original_payment_id uuid not null unique references public.payments(id) on delete restrict,
  transaction_id uuid not null references public.transactions(id) on delete restrict,
  reason text not null check (char_length(trim(reason)) between 5 and 500),
  reversed_by uuid not null references public.profiles(id),
  reversed_at timestamptz not null default now(),
  idempotency_key uuid not null unique
);
create index payment_reversals_shop_reversed_at_idx on public.payment_reversals(shop_id, reversed_at desc);
create index payment_reversals_transaction_id_idx on public.payment_reversals(transaction_id);
alter table public.payment_reversals enable row level security;
create policy payment_reversals_select_owner_or_manager on public.payment_reversals for select to authenticated
  using (shop_id = public.current_shop_id() and public.current_role() in ('owner','manager'));

create trigger payments_audit_trigger after insert on public.payments for each row execute function public.write_audit_log();
create trigger payment_reversals_audit_trigger after insert on public.payment_reversals for each row execute function public.write_audit_log();

-- A reversal can return a pledge to ACTIVE when it undoes its only payment.
-- Direct client updates remain denied by RLS; this transition is reachable
-- only through reverse_payment(), which records an append-only reversal first.
create or replace function public.transactions_enforce_status_transition()
returns trigger language plpgsql set search_path = public as $$
begin
  if old.status = new.status then return new; end if;
  if old.status = 'ACTIVE' and new.status in ('PARTIALLY_PAID','REDEEMED','CANCELLED') then return new; end if;
  if old.status = 'PARTIALLY_PAID' and new.status in ('REDEEMED','CANCELLED') then return new; end if;
  if old.status = 'PARTIALLY_PAID' and new.status = 'ACTIVE'
     and exists (select 1 from public.payment_reversals r where r.transaction_id = old.id) then return new; end if;
  raise exception 'Invalid transaction status transition: % -> % (transaction %)', old.status, new.status, old.id;
end;
$$;

create function public.reverse_payment(p_payment_id uuid, p_reason text, p_idempotency_key uuid)
returns public.transactions language plpgsql security definer set search_path = public as $$
declare v_payment public.payments; v_transaction public.transactions; v_result public.transactions;
begin
  if auth.uid() is null or public.current_role() <> 'owner' then raise exception 'reverse_payment: owner permission required'; end if;
  if p_idempotency_key is null or char_length(trim(coalesce(p_reason,''))) < 5 then raise exception 'reverse_payment: a reason of at least 5 characters and an idempotency key are required'; end if;
  select p.* into v_payment from public.payments p join public.transactions t on t.id=p.transaction_id
    where p.id=p_payment_id and p.shop_id=public.current_shop_id() for update of p, t;
  if v_payment.id is null then raise exception 'reverse_payment: payment not found in active shop'; end if;
  select * into v_transaction from public.transactions where id=v_payment.transaction_id for update;
  if exists (select 1 from public.payment_reversals where original_payment_id=v_payment.id) then return v_transaction; end if;
  if exists (select 1 from public.payment_reversals where idempotency_key=p_idempotency_key) then return v_transaction; end if;
  if v_transaction.status in ('REDEEMED','CANCELLED') then raise exception 'reverse_payment: redeemed or cancelled pledges require a separate corrective workflow'; end if;
  if exists (select 1 from public.payments p where p.transaction_id=v_payment.transaction_id and (p.payment_date,p.created_at) > (v_payment.payment_date,v_payment.created_at)) then raise exception 'reverse_payment: only the most recent payment may be reversed'; end if;
  insert into public.payment_reversals(shop_id,original_payment_id,transaction_id,reason,reversed_by,idempotency_key)
    values(v_payment.shop_id,v_payment.id,v_payment.transaction_id,trim(p_reason),auth.uid(),p_idempotency_key);
  update public.transactions set
    outstanding_principal = outstanding_principal + v_payment.principal_amount,
    accrued_interest = accrued_interest + v_payment.interest_amount,
    status = case when outstanding_principal + v_payment.principal_amount = principal_amount then 'ACTIVE'::public.transaction_status else 'PARTIALLY_PAID'::public.transaction_status end
    where id=v_transaction.id returning * into v_result;
  insert into public.interest_events(transaction_id,event_type,amount,principal_balance_after,interest_due_after,event_date,related_payment_id,created_by)
    values(v_transaction.id,'WAIVER',v_payment.interest_amount,v_result.outstanding_principal,v_result.accrued_interest,current_date,v_payment.id,auth.uid());
  return v_result;
end;
$$;

-- Do not allow PUBLIC/anon to inherit execution through the default PUBLIC
-- grant.  Trigger-only helpers stay private; browser-callable RPCs are
-- intentionally granted only to authenticated users.
revoke execute on all functions in schema public from public;
grant execute on function public.current_shop_id() to authenticated;
grant execute on function public.current_role() to authenticated;
grant execute on function public.current_user_can(text) to authenticated;
grant execute on function public.set_updated_at() to authenticated;
grant execute on function public.normalize_mobile_number(text) to authenticated;
grant execute on function public.customers_normalize_mobile() to authenticated;
grant execute on function public.customers_assign_code() to authenticated;
grant execute on function public.transactions_assign_code() to authenticated;
grant execute on function public.transactions_enforce_status_transition() to authenticated;
grant execute on function public.jewellery_items_set_shop_id() to authenticated;
grant execute on function public.payments_set_shop_id() to authenticated;
grant execute on function public.interest_events_set_shop_id() to authenticated;
grant execute on function public.bootstrap_shop_owner(text) to authenticated;
grant execute on function public.complete_onboarding() to authenticated;
grant execute on function public.set_pin(text) to authenticated;
grant execute on function public.clear_pin() to authenticated;
grant execute on function public.pin_is_configured() to authenticated;
grant execute on function public.verify_pin(text) to authenticated;
grant execute on function public.set_customer_photo(uuid,text) to authenticated;
grant execute on function public.create_transaction(uuid,numeric,numeric,date,integer,jsonb) to authenticated;
grant execute on function public.record_payment(uuid,numeric,text,text,date) to authenticated;
grant execute on function public.cancel_transaction(uuid,text) to authenticated;
grant execute on function public.create_jewellery_loan(uuid,numeric,text,numeric,numeric,date,text,uuid,jsonb,text) to authenticated;
grant execute on function public.post_payment(uuid,numeric,text,date,uuid,text,text,boolean) to authenticated;
grant execute on function public.dashboard_summary(date,date) to authenticated;
grant execute on function public.switch_active_shop(uuid) to authenticated;
grant execute on function public.reverse_payment(uuid,text,uuid) to authenticated;
