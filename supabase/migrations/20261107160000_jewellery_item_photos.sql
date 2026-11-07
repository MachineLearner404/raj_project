-- Per-item jewellery photographs, uploaded from the New Jewellery Loan page.
-- Same shape as the customer-photos bucket (20251106121200 /
-- 20261107062736): a private bucket, a path convention the policies
-- trust, and a narrow security-definer RPC — not a broad UPDATE policy —
-- as the only way to attach a path to a row.
--
-- Path convention: "<shop_id>/<transaction_id>/<jewellery_item_id>.<ext>".
-- Attaching a photo is gated on the same 'create_loans' capability as
-- creating the loan itself, since an item photo only ever exists as part
-- of appraising jewellery for a pledge.

alter table public.jewellery_items
  add column if not exists photo_path text;

insert into storage.buckets (id, name, public)
values ('jewellery-photos', 'jewellery-photos', false)
on conflict (id) do nothing;

create policy jewellery_photos_select_own_shop
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'jewellery-photos'
    and (storage.foldername(name))[1] = public.current_shop_id()::text
  );

create policy jewellery_photos_insert_own_shop
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'jewellery-photos'
    and (storage.foldername(name))[1] = public.current_shop_id()::text
    and public.current_user_can('create_loans')
  );

create policy jewellery_photos_update_own_shop
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'jewellery-photos'
    and (storage.foldername(name))[1] = public.current_shop_id()::text
  )
  with check (
    bucket_id = 'jewellery-photos'
    and (storage.foldername(name))[1] = public.current_shop_id()::text
    and public.current_user_can('create_loans')
  );

create policy jewellery_photos_delete_own_shop
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'jewellery-photos'
    and (storage.foldername(name))[1] = public.current_shop_id()::text
    and public.current_role() in ('owner', 'manager')
  );

comment on policy jewellery_photos_select_own_shop on storage.objects is
  'Jewellery item photos bucket is private; path convention "<shop_id>/<transaction_id>/<item_id>.<file>" is enforced by comparing the first path segment to the caller''s shop.';

create function public.set_jewellery_item_photo(
  p_item_id uuid,
  p_photo_path text
)
returns public.jewellery_items
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shop_id uuid := public.current_shop_id();
  v_item public.jewellery_items;
  v_expected_prefix text;
begin
  if not public.current_user_can('create_loans') then
    raise exception 'set_jewellery_item_photo: role % is not permitted to attach jewellery photos', public.current_role();
  end if;

  select * into v_item from public.jewellery_items where id = p_item_id and shop_id = v_shop_id;
  if v_item.id is null then
    raise exception 'set_jewellery_item_photo: jewellery item % not found in your shop', p_item_id;
  end if;

  v_expected_prefix := v_shop_id::text || '/' || v_item.transaction_id::text || '/';
  if p_photo_path is null or left(p_photo_path, char_length(v_expected_prefix)) <> v_expected_prefix then
    raise exception 'set_jewellery_item_photo: photo path must be inside the item''s transaction folder';
  end if;

  update public.jewellery_items
    set photo_path = p_photo_path
    where id = p_item_id
    returning * into v_item;

  return v_item;
end;
$$;

revoke execute on function public.set_jewellery_item_photo(uuid, text) from public;
grant execute on function public.set_jewellery_item_photo(uuid, text) to authenticated;
