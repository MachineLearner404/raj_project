-- A staff member may register a customer when the owner enables that
-- capability, but customers themselves remain manager/owner editable.
-- Photo attachment is therefore a narrow, audited RPC rather than a broad
-- customer UPDATE policy for staff.

drop policy customer_photos_insert_own_shop on storage.objects;

create policy customer_photos_insert_own_shop
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'customer-photos'
    and (storage.foldername(name))[1] = public.current_shop_id()::text
    and public.current_user_can('register_customers')
  );

create or replace function public.set_customer_photo(
  p_customer_id uuid,
  p_photo_path text
)
returns public.customers
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shop_id uuid := public.current_shop_id();
  v_customer public.customers;
  v_expected_prefix text;
begin
  if not public.current_user_can('register_customers') then
    raise exception 'set_customer_photo: role % is not permitted to attach customer photos', public.current_role();
  end if;

  v_expected_prefix := v_shop_id::text || '/' || p_customer_id::text || '/';
  if p_photo_path is null or left(p_photo_path, char_length(v_expected_prefix)) <> v_expected_prefix then
    raise exception 'set_customer_photo: photo path must be inside the customer folder';
  end if;

  update public.customers
    set photo_path = p_photo_path
    where id = p_customer_id and shop_id = v_shop_id
    returning * into v_customer;

  if v_customer.id is null then
    raise exception 'set_customer_photo: customer % not found in your shop', p_customer_id;
  end if;

  return v_customer;
end;
$$;

revoke execute on function public.set_customer_photo(uuid, text) from public;
grant execute on function public.set_customer_photo(uuid, text) to authenticated;
