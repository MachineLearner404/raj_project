-- Clients generated from the raw PostgREST type include customer_code even
-- though it is assigned by this trigger. Treat empty/whitespace placeholders
-- as absent so they receive the same atomic, per-shop sequence as an omitted
-- field. Non-empty caller-provided codes retain the original behaviour.

create or replace function public.customers_assign_code()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seq integer;
begin
  new.customer_code := nullif(trim(new.customer_code), '');

  if new.customer_code is not null then
    return new;
  end if;

  update public.shops
    set next_customer_seq = next_customer_seq + 1
    where id = new.shop_id
    returning next_customer_seq - 1 into v_seq;

  if v_seq is null then
    raise exception 'customers_assign_code: shop % does not exist', new.shop_id;
  end if;

  new.customer_code := 'C-' || lpad(v_seq::text, 5, '0');
  return new;
end;
$$;
