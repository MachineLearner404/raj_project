-- One shop-scoped aggregation avoids multiplying payments by jewellery items.
create or replace function public.dashboard_summary(p_from date default null, p_to date default null)
returns jsonb language sql security invoker set search_path=public as $$
  select jsonb_build_object(
    'customers', (select count(*) from customers c where c.shop_id=current_shop_id()),
    'active', (select count(*) from transactions t where t.shop_id=current_shop_id() and t.status='ACTIVE'),
    'partially_paid', (select count(*) from transactions t where t.shop_id=current_shop_id() and t.status='PARTIALLY_PAID'),
    'redeemed', (select count(*) from transactions t where t.shop_id=current_shop_id() and t.status='REDEEMED'),
    'pledged_weight', coalesce((select sum(i.net_weight_grams*i.quantity) from jewellery_items i join transactions t on t.id=i.transaction_id where t.shop_id=current_shop_id() and t.status in ('ACTIVE','PARTIALLY_PAID')),0),
    'disbursed', coalesce((select sum(t.principal_amount) from transactions t where t.shop_id=current_shop_id() and (p_from is null or t.issue_date>=p_from) and (p_to is null or t.issue_date<=p_to)),0),
    'payments', coalesce((select sum(p.amount) from payments p where p.shop_id=current_shop_id() and (p_from is null or p.payment_date>=p_from) and (p_to is null or p.payment_date<=p_to)),0),
    'outstanding', coalesce((select sum(t.outstanding_principal+t.accrued_interest) from transactions t where t.shop_id=current_shop_id() and t.status in ('ACTIVE','PARTIALLY_PAID')),0),
    'recent_transactions', coalesce((select jsonb_agg(x) from (select jsonb_build_object('id',t.id,'pledge_code',t.pledge_code,'issue_date',t.issue_date,'principal',t.principal_amount,'status',t.status,'customer',c.full_name) x from transactions t join customers c on c.id=t.customer_id where t.shop_id=current_shop_id() order by t.created_at desc limit 5) q),'[]'::jsonb),
    'recent_payments', coalesce((select jsonb_agg(x) from (select jsonb_build_object('id',p.id,'amount',p.amount,'date',p.payment_date,'method',p.payment_method,'pledge_code',t.pledge_code,'customer',c.full_name) x from payments p join transactions t on t.id=p.transaction_id join customers c on c.id=t.customer_id where p.shop_id=current_shop_id() order by p.payment_date desc,p.created_at desc limit 5) q),'[]'::jsonb),
    'months', coalesce((select jsonb_agg(x order by x->>'month') from (select jsonb_build_object('month',m.month_key,'disbursed',coalesce((select sum(t.principal_amount) from transactions t where t.shop_id=current_shop_id() and to_char(t.issue_date,'YYYY-MM')=m.month_key),0),'collections',coalesce((select sum(p.amount) from payments p where p.shop_id=current_shop_id() and to_char(p.payment_date,'YYYY-MM')=m.month_key),0)) x from (select to_char(d,'YYYY-MM') as month_key from generate_series(date_trunc('month',coalesce(p_from,current_date-interval '5 months')),date_trunc('month',coalesce(p_to,current_date)),interval '1 month') d) m) q),'[]'::jsonb)
  );
$$;
revoke execute on function public.dashboard_summary(date,date) from public;
grant execute on function public.dashboard_summary(date,date) to authenticated;
