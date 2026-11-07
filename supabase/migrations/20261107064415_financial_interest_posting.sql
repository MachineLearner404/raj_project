alter table public.transactions add column accrued_interest numeric(14,2) not null default 0 check (accrued_interest >= 0), add column interest_periods_settled integer not null default 0 check (interest_periods_settled >= 0);
alter table public.payments add column interest_amount numeric(14,2) not null default 0 check (interest_amount >= 0), add column principal_amount numeric(14,2) not null default 0 check (principal_amount >= 0), add column idempotency_key uuid;
create unique index payments_transaction_idempotency_unique on public.payments(transaction_id,idempotency_key) where idempotency_key is not null;

-- Always calculate from the deposit date. This preserves a Jan-31 schedule as
-- Feb-28/29, Mar-31, Apr-30 rather than letting the February clamp drift it.
create or replace function public.loan_anniversary(p_deposit_date date, p_periods integer, p_yearly boolean default false)
returns date language sql immutable strict set search_path=public as $$
  select (date_trunc('month', p_deposit_date +
    case when p_yearly then make_interval(years => p_periods) else make_interval(months => p_periods) end)::date
    + least(extract(day from p_deposit_date)::integer,
      extract(day from (date_trunc('month', p_deposit_date +
        case when p_yearly then make_interval(years => p_periods) else make_interval(months => p_periods) end)
        + interval '1 month - 1 day'))::integer) - 1);
$$;

create or replace function public.post_payment(p_transaction_id uuid,p_amount numeric,p_payment_method text,p_payment_date date,p_idempotency_key uuid)
returns public.transactions language plpgsql security definer set search_path=public as $$
declare v public.transactions; e public.transactions; yearly boolean; period_interest numeric; interest_paid numeric; principal_paid numeric; pid uuid; v_next_anniversary date;
begin
 if not public.current_user_can('record_payments') then raise exception 'post_payment: not permitted'; end if;
 if p_amount<=0 or p_idempotency_key is null then raise exception 'post_payment: positive amount and idempotency key required'; end if;
 select * into v from public.transactions where id=p_transaction_id and shop_id=public.current_shop_id() for update;
 if v.id is null or v.status not in ('ACTIVE','PARTIALLY_PAID') then raise exception 'post_payment: active transaction not found'; end if;
 if exists(select 1 from public.payments where transaction_id=v.id and idempotency_key=p_idempotency_key) then return v; end if;
 yearly := v.interest_type='YEARLY';
 if v.interest_type='FLAT' then
   if not exists(select 1 from public.interest_events where transaction_id=v.id and event_type='ACCRUAL') then
     v.accrued_interest:=v.accrued_interest + case when v.flat_interest_basis_type = 'PERCENT_OF_ORIGINAL'
       then round(v.principal_amount * v.flat_interest_basis / 100, 2)
       else coalesce(v.flat_interest_basis, v.principal_amount*v.interest_rate_percent_per_month/100) end;
     insert into public.interest_events(transaction_id,event_type,amount,principal_balance_after,interest_due_after,event_date,created_by) values(v.id,'ACCRUAL',v.accrued_interest,v.outstanding_principal,v.accrued_interest,p_payment_date,auth.uid());
   end if;
 else
   loop
     v_next_anniversary := public.loan_anniversary(v.issue_date, v.interest_periods_settled + 1, yearly);
     exit when v_next_anniversary > p_payment_date;
     v.interest_periods_settled := v.interest_periods_settled + 1;
     v.interest_settled_through := v_next_anniversary;
     period_interest:=round(v.outstanding_principal * (case when yearly then v.interest_rate_percent_per_month*12 else v.interest_rate_percent_per_month end)/100,2);
     v.accrued_interest:=v.accrued_interest+period_interest;
     insert into public.interest_events(transaction_id,event_type,amount,principal_balance_after,interest_due_after,event_date,created_by) values(v.id,'ACCRUAL',period_interest,v.outstanding_principal,v.accrued_interest,v.interest_settled_through,auth.uid());
   end loop;
 end if;
 interest_paid:=least(p_amount,v.accrued_interest); principal_paid:=p_amount-interest_paid;
 if principal_paid>v.outstanding_principal then raise exception 'post_payment: overpayment is not permitted'; end if;
 insert into public.payments(transaction_id,amount,payment_type,payment_method,payment_date,received_by,interest_amount,principal_amount,idempotency_key) values(v.id,p_amount,case when principal_paid=0 then 'INTEREST' when principal_paid=v.outstanding_principal then 'FULL_CLOSURE' else 'PARTIAL_PRINCIPAL' end,p_payment_method,p_payment_date,auth.uid(),interest_paid,principal_paid,p_idempotency_key) returning id into pid;
 v.accrued_interest:=v.accrued_interest-interest_paid; v.outstanding_principal:=v.outstanding_principal-principal_paid;
 update public.transactions set accrued_interest=v.accrued_interest,outstanding_principal=v.outstanding_principal,interest_settled_through=v.interest_settled_through,interest_periods_settled=v.interest_periods_settled,status=case when v.outstanding_principal=0 and v.accrued_interest=0 then 'REDEEMED'::public.transaction_status when v.outstanding_principal<v.principal_amount then 'PARTIALLY_PAID'::public.transaction_status else 'ACTIVE'::public.transaction_status end,closure_type=case when v.outstanding_principal=0 and v.accrued_interest=0 then 'REDEEMED' else null end,closed_at=case when v.outstanding_principal=0 and v.accrued_interest=0 then now() else null end where id=v.id returning * into e;
 insert into public.interest_events(transaction_id,event_type,amount,principal_balance_after,interest_due_after,event_date,related_payment_id,created_by) values(v.id,'SETTLEMENT',interest_paid,e.outstanding_principal,e.accrued_interest,p_payment_date,pid,auth.uid());
 return e;
end; $$;
revoke execute on function public.post_payment(uuid,numeric,text,date,uuid) from public;
grant execute on function public.post_payment(uuid,numeric,text,date,uuid) to authenticated;
