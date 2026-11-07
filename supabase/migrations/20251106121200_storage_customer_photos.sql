-- Private Storage bucket for customer photos (ID proof scans, portraits).
-- Objects must be uploaded at the path "<shop_id>/<customer_id>/<file>"
-- — the policies below trust that convention and enforce it via the
-- first path segment, using Storage's storage.foldername() helper.

insert into storage.buckets (id, name, public)
values ('customer-photos', 'customer-photos', false)
on conflict (id) do nothing;

create policy customer_photos_select_own_shop
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'customer-photos'
    and (storage.foldername(name))[1] = public.current_shop_id()::text
  );

create policy customer_photos_insert_own_shop
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'customer-photos'
    and (storage.foldername(name))[1] = public.current_shop_id()::text
    and public.current_role() in ('owner', 'manager', 'staff')
  );

create policy customer_photos_update_own_shop
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'customer-photos'
    and (storage.foldername(name))[1] = public.current_shop_id()::text
  )
  with check (
    bucket_id = 'customer-photos'
    and (storage.foldername(name))[1] = public.current_shop_id()::text
    and public.current_role() in ('owner', 'manager', 'staff')
  );

create policy customer_photos_delete_own_shop
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'customer-photos'
    and (storage.foldername(name))[1] = public.current_shop_id()::text
    and public.current_role() in ('owner', 'manager')
  );

comment on policy customer_photos_select_own_shop on storage.objects is
  'Customer photos bucket is private; path convention "<shop_id>/<customer_id>/<file>" is enforced by comparing the first path segment to the caller''s shop.';
