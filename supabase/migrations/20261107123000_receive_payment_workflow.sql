-- Payment records remain append-only. Extra counter fields are supplied only
-- by the server-side posting RPC, never trusted from a browser form.
alter table public.payments
  drop constraint payments_payment_method_check,
  add constraint payments_payment_method_check check (payment_method in ('CASH', 'UPI', 'BANK_TRANSFER', 'OTHER')),
  add column reference_number text;

alter table public.transactions
  add column jewellery_returned_at date,
  add column jewellery_returned_by uuid references public.profiles(id),
  add constraint transactions_return_details_paired check (
    (jewellery_returned_at is null) = (jewellery_returned_by is null)
  );

alter table public.shops add column next_receipt_seq bigint not null default 1;

drop function public.post_payment(uuid,numeric,text,date,uuid);
create function public.post_payment(
  p_transaction_id uuid, p_amount numeric, p_payment_method text,
  p_payment_date date, p_idempotency_key uuid, p_reference_number text default null,
  p_remarks text default null, p_confirm_jewellery_return boolean default false
) returns public.transactions language plpgsql security definer set search_path=public as $$
declare v public.transactions; e public.transactions; yearly boolean; period_interest numeric;
  interest_paid numeric; principal_paid numeric; pid uuid; v_next_anniversary date;
  v_receipt text; v_prefix text; v_seq bigint; v_will_redeem boolean;
begin
 if not public.current_user_can('record_payments') then raise exception 'post_payment: not permitted'; end if;
 if p_amount <= 0 or p_idempotency_key is null then raise exception 'post_payment: positive amount and idempotency key required'; end if;
 if p_payment_method not in ('CASH','UPI','BANK_TRANSFER','OTHER') then raise exception 'post_payment: invalid payment method'; end if;
 select * into v from public.transactions where id=p_transaction_id and shop_id=public.current_shop_id() for update;
 if v.id is null or v.status not in ('ACTIVE','PARTIALLY_PAID') then raise exception 'post_payment: active transaction not found'; end if;
 if exists(select 1 from public.payments where transaction_id=v.id and idempotency_key=p_idempotency_key) then return v; end if;
 yearly := v.interest_type='YEARLY';
 if v.interest_type='FLAT' then
   if not exists(select 1 from public.interest_events where transaction_id=v.id and event_type='ACCRUAL') then
     v.accrued_interest:=v.accrued_interest + case when v.flat_interest_basis_type='PERCENT_OF_ORIGINAL' then round(v.principal_amount*v.flat_interest_basis/100,2) else coalesce(v.flat_interest_basis,v.principal_amount*v.interest_rate_percent_per_month/100) end;
     insert into public.interest_events(transaction_id,event_type,amount,principal_balance_after,interest_due_after,event_date,created_by) values(v.id,'ACCRUAL',v.accrued_interest,v.outstanding_principal,v.accrued_interest,p_payment_date,auth.uid());
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
