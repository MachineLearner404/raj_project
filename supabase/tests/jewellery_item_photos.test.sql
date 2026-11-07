-- ============================================================================
-- Jewellery item photo upload: path convention, capability gating, and
-- shop isolation for both the storage RLS policies and the
-- set_jewellery_item_photo() RPC added by
-- 20261107160000_jewellery_item_photos.sql.
--
-- Run after historical_settlement.test.sql on the same scratch database --
-- see supabase/tests/run.sh.
-- ============================================================================

\set ON_ERROR_STOP on

create or replace function test_login(p_user_key text)
returns void language plpgsql as $$
declare v_user_id uuid;
begin
  select value into v_user_id from test_fixtures where key = p_user_key;
  if v_user_id is null then raise exception 'test_login: unknown fixture key %', p_user_key; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user_id)::text, false);
end;
$$;

do $$
declare
  v_customer_id uuid; v_shop_a uuid; v_shop_b uuid; v_txn public.transactions; v_item_id uuid;
  v_good_path text; v_wrong_shop_path text; v_wrong_txn_path text; v_result public.jewellery_items;
begin
  reset role; perform test_login('owner_a'); set local role authenticated;
  select value into v_customer_id from test_fixtures where key = 'customer_1';
  select value into v_shop_a from test_fixtures where key = 'shop_a';
  select value into v_shop_b from test_fixtures where key = 'shop_b';
  update public.customers set is_active = true where id = v_customer_id;

  select * into v_txn from public.create_jewellery_loan(
    v_customer_id, 50000, 'MONTHLY', 2, null, current_date, null, gen_random_uuid(),
    '[{"jewellery_name":"Photo test bangle","metal_type":"GOLD","weight_grams":10,"quantity":1}]');
  select id into v_item_id from public.jewellery_items where transaction_id = v_txn.id;
  insert into test_fixtures values ('photo_item', v_item_id);
  insert into test_fixtures values ('photo_txn', v_txn.id);

  v_good_path := v_shop_a::text || '/' || v_txn.id::text || '/' || v_item_id::text || '.jpg';
  v_wrong_shop_path := v_shop_b::text || '/' || v_txn.id::text || '/' || v_item_id::text || '.jpg';
  v_wrong_txn_path := v_shop_a::text || '/' || gen_random_uuid()::text || '/' || v_item_id::text || '.jpg';

  -- 1. The storage INSERT policy accepts an object under the caller's own shop folder.
  insert into storage.objects (bucket_id, name) values ('jewellery-photos', v_good_path);
  if not exists (select 1 from storage.objects where bucket_id = 'jewellery-photos' and name = v_good_path) then
    raise exception 'FAIL: a same-shop jewellery photo object was not accepted';
  end if;

  -- 2. ...but rejects an object whose first path segment names another shop.
  begin
    insert into storage.objects (bucket_id, name) values ('jewellery-photos', v_wrong_shop_path);
    raise exception 'FAIL: an object under another shop''s folder was accepted';
  exception when insufficient_privilege then null; end;

  -- 3. set_jewellery_item_photo() attaches a path inside the item's own transaction folder.
  select * into v_result from public.set_jewellery_item_photo(v_item_id, v_good_path);
  if v_result.photo_path <> v_good_path then raise exception 'FAIL: photo_path was not attached (%)', v_result.photo_path; end if;

  -- 4. ...and rejects a path for a different transaction, even if it names the right shop and item id.
  begin
    perform public.set_jewellery_item_photo(v_item_id, v_wrong_txn_path);
    raise exception 'FAIL: a path outside the item''s transaction folder was accepted';
  exception when others then if sqlerrm not like '%inside the item''s transaction folder%' then raise; end if; end;

  -- 5. Re-attaching under the real path (simulating a retaken photo) still succeeds and overwrites, not duplicates.
  select * into v_result from public.set_jewellery_item_photo(v_item_id, v_good_path);
  if v_result.photo_path <> v_good_path then raise exception 'FAIL: re-attaching the same path failed'; end if;

  raise notice 'PASS: jewellery photo path convention is enforced by storage RLS and by set_jewellery_item_photo()';
end;
$$;

-- ---------------------------------------------------------------------
-- Capability gating: a staff member without the create_loans capability
-- may not attach a jewellery photo, exactly like they may not create the
-- loan itself.
-- ---------------------------------------------------------------------

do $$
declare v_item_id uuid; v_shop_a uuid; v_txn_id uuid; v_path text;
begin
  reset role; perform test_login('owner_a'); set local role authenticated;
  select value into v_shop_a from test_fixtures where key = 'shop_a';
  update public.app_settings set staff_can_create_loans = false where shop_id = v_shop_a;

  reset role; perform test_login('staff_a'); set local role authenticated;
  select value into v_item_id from test_fixtures where key = 'photo_item';
  select value into v_txn_id from test_fixtures where key = 'photo_txn';
  v_path := v_shop_a::text || '/' || v_txn_id::text || '/' || v_item_id::text || '.jpg';

  begin
    perform public.set_jewellery_item_photo(v_item_id, v_path);
    raise exception 'FAIL: staff without staff_can_create_loans attached a jewellery photo';
  exception when others then if sqlerrm not like '%is not permitted to attach jewellery photos%' then raise; end if; end;

  begin
    insert into storage.objects (bucket_id, name) values ('jewellery-photos', v_path || '.staff-attempt');
    raise exception 'FAIL: storage INSERT policy admitted staff without staff_can_create_loans';
  exception when insufficient_privilege then null; end;

  raise notice 'PASS: jewellery photo attachment is gated on the create_loans capability, same as loan creation';
end;
$$;

-- ---------------------------------------------------------------------
-- Shop isolation: another shop cannot read, attach to, or delete a photo
-- that belongs to shop A's item.
-- ---------------------------------------------------------------------

do $$
declare v_item_id uuid; v_shop_a uuid; v_txn_id uuid; v_path text; v_visible integer;
begin
  reset role; perform test_login('owner_a'); set local role authenticated;
  select value into v_shop_a from test_fixtures where key = 'shop_a';
  update public.app_settings set staff_can_create_loans = true where shop_id = v_shop_a;
  select value into v_item_id from test_fixtures where key = 'photo_item';
  select value into v_txn_id from test_fixtures where key = 'photo_txn';
  v_path := v_shop_a::text || '/' || v_txn_id::text || '/' || v_item_id::text || '.jpg';

  reset role; perform test_login('owner_b'); set local role authenticated;

  begin
    perform public.set_jewellery_item_photo(v_item_id, v_path);
    raise exception 'FAIL: another shop''s owner attached a photo to shop A''s item';
  exception when others then if sqlerrm not like '%not found in your shop%' then raise; end if; end;

  select count(*) into v_visible from storage.objects where bucket_id = 'jewellery-photos' and name = v_path;
  if v_visible <> 0 then raise exception 'FAIL: shop B could see shop A''s jewellery photo object (storage SELECT policy)'; end if;

  -- The DELETE policy's USING clause filters by shop, so this matches 0 rows
  -- under RLS rather than erroring -- confirm the row is still there as owner A.
  delete from storage.objects where bucket_id = 'jewellery-photos' and name = v_path;
  reset role; perform test_login('owner_a'); set local role authenticated;
  if not exists (select 1 from storage.objects where bucket_id = 'jewellery-photos' and name = v_path) then
    raise exception 'FAIL: shop B deleted shop A''s jewellery photo object';
  end if;

  raise notice 'PASS: jewellery photo rows and the item they describe are isolated by shop';
end;
$$;

reset role;
drop function test_login(text);

do $$
begin
  raise notice '=====================================================';
  raise notice 'ALL JEWELLERY ITEM PHOTO TESTS PASSED';
  raise notice '=====================================================';
end;
$$;
