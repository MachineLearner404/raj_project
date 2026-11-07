-- ============================================================================
-- Phase 3: real, executed assertions for shop bootstrap/onboarding,
-- configurable staff permissions, and the PIN unlock mechanism's rate
-- limiting. Run after supabase/tests/rls_and_constraints.test.sql on the
-- same scratch database — see supabase/tests/run.sh.
-- ============================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- Helper (same pattern as rls_and_constraints.test.sql).
-- ---------------------------------------------------------------------

create or replace function test_login(p_user_key text)
returns void language plpgsql as $$
declare
  v_user_id uuid;
begin
  select value into v_user_id from test_fixtures where key = p_user_key;
  if v_user_id is null then
    raise exception 'test_login: unknown fixture key %', p_user_key;
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user_id)::text, false);
end;
$$;

-- ---------------------------------------------------------------------
-- 1. bootstrap_shop_owner(): a fresh auth user with no profile can
--    create their own shop and becomes its owner.
-- ---------------------------------------------------------------------

do $$
declare
  v_new_user uuid := gen_random_uuid();
  v_shop public.shops;
begin
  insert into auth.users (id) values (v_new_user);
  insert into test_fixtures values ('bootstrap_user', v_new_user);

  perform set_config('request.jwt.claims', json_build_object('sub', v_new_user)::text, false);
  set local role authenticated;

  select * into v_shop from public.bootstrap_shop_owner('Bootstrap Test Shop');

  if v_shop.id is null or v_shop.name <> 'Bootstrap Test Shop' then
    raise exception 'FAIL: bootstrap_shop_owner did not return the expected shop';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = v_new_user and shop_id = v_shop.id and role = 'owner'
  ) then
    raise exception 'FAIL: bootstrap_shop_owner did not create an owner profile';
  end if;

  if not exists (select 1 from public.app_settings where shop_id = v_shop.id) then
    raise exception 'FAIL: bootstrap_shop_owner did not create app_settings';
  end if;

  insert into test_fixtures values ('bootstrap_shop', v_shop.id);
  raise notice 'PASS: bootstrap_shop_owner() creates shop + owner profile + app_settings atomically';
end;
$$;

-- ---------------------------------------------------------------------
-- 2. A member can own a second shop without losing their original one.
-- ---------------------------------------------------------------------

do $$
declare v_second_shop public.shops;
begin
  reset role;
  perform test_login('owner_b');
  set local role authenticated;

  select * into v_second_shop from public.bootstrap_shop_owner('Second Shop Attempt');
  if not exists (select 1 from public.shop_memberships where user_id = (select value from test_fixtures where key='owner_b') and shop_id = v_second_shop.id and role='owner') then
    raise exception 'FAIL: second shop owner membership was not created';
  end if;
  raise notice 'PASS: an existing user can own a second shop via membership';
end;
$$;

-- ---------------------------------------------------------------------
-- 2b. Switching is server-authorized: a user may select only an active
-- membership, and the selected shop becomes the RLS scope.
-- ---------------------------------------------------------------------

do $$
declare v_shop_b uuid; v_second_shop uuid;
begin
  reset role;
  perform test_login('owner_b');
  set local role authenticated;
  select shop_id into v_second_shop from public.shop_memberships where user_id=(select value from test_fixtures where key='owner_b') and role='owner' order by created_at desc limit 1;
  perform public.switch_active_shop(v_second_shop);
  if public.current_shop_id() <> v_second_shop or public.current_role() <> 'owner' then
    raise exception 'FAIL: authorized shop switch did not update the server-side scope';
  end if;
  select value into v_shop_b from test_fixtures where key='shop_b';
  perform public.switch_active_shop(v_shop_b);
  if public.current_shop_id() <> v_shop_b then raise exception 'FAIL: switch back to original shop failed'; end if;
  raise notice 'PASS: active-shop switching is membership-authorized and changes server-side scope';
end;
$$;

do $$
declare v_shop_b uuid;
begin
  reset role;
  perform test_login('staff_a');
  set local role authenticated;
  select value into v_shop_b from test_fixtures where key='shop_b';
  begin
    perform public.switch_active_shop(v_shop_b);
    raise exception 'FAIL: staff switched to an unauthorized shop';
  exception when others then
    if sqlerrm like 'switch_active_shop: you are not an active member%' then
      raise notice 'PASS: switch_active_shop rejects a shop without membership';
    else raise; end if;
  end;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. complete_onboarding(): owner-only, sets onboarding_completed_at.
-- ---------------------------------------------------------------------

do $$
declare
  v_shop_id uuid;
  v_result public.shops;
begin
  reset role;
  perform test_login('bootstrap_user');
  set local role authenticated;

  select value into v_shop_id from test_fixtures where key = 'bootstrap_shop';

  select * into v_result from public.complete_onboarding();

  if v_result.onboarding_completed_at is null then
    raise exception 'FAIL: complete_onboarding() did not set onboarding_completed_at';
  end if;
  raise notice 'PASS: complete_onboarding() sets onboarding_completed_at for the owner''s shop';
end;
$$;

do $$
begin
  reset role;
  perform test_login('staff_a');
  set local role authenticated;

  begin
    perform public.complete_onboarding();
    raise exception 'FAIL: staff should not be able to complete onboarding';
  exception
    when others then
      if sqlerrm like 'complete_onboarding: role staff is not permitted%' then
        raise notice 'PASS: complete_onboarding() correctly rejects staff: %', sqlerrm;
      else
        raise;
      end if;
  end;
end;
$$;

-- ---------------------------------------------------------------------
-- 12. Payment reversals are owner-only, append-only, idempotent, and
-- restore the payment allocations without deleting the original receipt.
-- ---------------------------------------------------------------------

do $$
declare v_customer public.customers; v_txn public.transactions; v_payment public.payments; v_after public.transactions;
begin
  reset role;
  perform test_login('owner_a');
  set local role authenticated;
  insert into public.customers(shop_id,full_name,mobile,address,id_proof_type,id_proof_number,created_by)
    values((select value from test_fixtures where key='shop_a'),'Reversal Test','9876543201','Pune','PAN','REVERSAL-1',(select value from test_fixtures where key='owner_a')) returning * into v_customer;
  select * into v_txn from public.create_jewellery_loan(v_customer.id,10000,'MONTHLY',2,null,current_date,'reversal test',gen_random_uuid(),
    '[{"jewellery_name":"Ring","metal_type":"Gold","weight_grams":2,"quantity":1}]'::jsonb);
  perform public.post_payment(v_txn.id,5000,'CASH',current_date,gen_random_uuid(),null,'test',false);
  select * into v_payment from public.payments where transaction_id=v_txn.id order by created_at desc limit 1;
  select * into v_after from public.reverse_payment(v_payment.id,'Counter entry correction',gen_random_uuid());
  if v_after.outstanding_principal <> 10000 or not exists(select 1 from public.payment_reversals where original_payment_id=v_payment.id) then
    raise exception 'FAIL: reversal did not restore the principal or retain the reversal row';
  end if;
  if not exists(select 1 from public.payments where id=v_payment.id) or not exists(select 1 from public.audit_logs where table_name='payment_reversals' and record_id=(select id from public.payment_reversals where original_payment_id=v_payment.id)) then
    raise exception 'FAIL: reversal erased history or missed its audit event';
  end if;
  raise notice 'PASS: owner payment reversal is append-only and restores balance';
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Configurable staff permission: create_loans is OFF by default —
--    staff cannot create a transaction until the owner turns it on.
-- ---------------------------------------------------------------------

do $$
declare
  v_customer_id uuid;
begin
  reset role;
  perform test_login('staff_a');
  set local role authenticated;

  select value into v_customer_id from test_fixtures where key = 'customer_1';

  begin
    perform public.create_transaction(
      v_customer_id, 20000, 1.5, current_date, 12,
      '[{"category":"COIN","description":"Gold coin","gross_weight_grams":10,"net_weight_grams":10,"purity_karat":22,"gold_rate_used_per_gram":6450,"estimated_value":60000}]'::jsonb
    );
    raise exception 'FAIL: staff should not be able to create a loan while staff_can_create_loans is false';
  exception
    when others then
      if sqlerrm like 'create_transaction: role staff is not permitted%' then
        raise notice 'PASS: create_transaction() still denies staff while the flag is off';
      else
        raise;
      end if;
  end;
end;
$$;

do $$
declare
  v_shop_a uuid;
  v_customer_id uuid;
  v_txn public.transactions;
begin
  -- Owner turns the flag on.
  reset role;
  perform test_login('owner_a');
  set local role authenticated;

  select value into v_shop_a from test_fixtures where key = 'shop_a';
  update public.app_settings set staff_can_create_loans = true where shop_id = v_shop_a;

  if not found then
    raise exception 'FAIL: owner could not update staff_can_create_loans';
  end if;
  raise notice 'PASS: owner can toggle staff_can_create_loans on via the normal app_settings UPDATE policy';

  -- Now staff can create one.
  reset role;
  perform test_login('staff_a');
  set local role authenticated;

  select value into v_customer_id from test_fixtures where key = 'customer_1';

  select * into v_txn from public.create_transaction(
    v_customer_id, 20000, 1.5, current_date, 12,
    '[{"category":"COIN","description":"Gold coin","gross_weight_grams":10,"net_weight_grams":10,"purity_karat":22,"gold_rate_used_per_gram":6450,"estimated_value":60000}]'::jsonb
  );

  if v_txn.id is null then
    raise exception 'FAIL: staff should be able to create a loan once staff_can_create_loans is true';
  end if;
  raise notice 'PASS: create_transaction() admits staff once the owner enables staff_can_create_loans (%)', v_txn.pledge_code;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. A manager is never affected by the staff_can_create_loans flag —
--    confirm manager can still create loans even with the flag off.
-- ---------------------------------------------------------------------

do $$
declare
  v_shop_a uuid;
  v_customer_id uuid;
  v_txn public.transactions;
begin
  reset role;
  perform test_login('owner_a');
  set local role authenticated;
  select value into v_shop_a from test_fixtures where key = 'shop_a';
  update public.app_settings set staff_can_create_loans = false where shop_id = v_shop_a;

  reset role;
  perform test_login('manager_a');
  set local role authenticated;
  select value into v_customer_id from test_fixtures where key = 'customer_1';

  select * into v_txn from public.create_transaction(
    v_customer_id, 15000, 1.5, current_date, 12,
    '[{"category":"EARRINGS","description":"Gold earrings","gross_weight_grams":4,"net_weight_grams":4,"purity_karat":22,"gold_rate_used_per_gram":6450,"estimated_value":24000}]'::jsonb
  );

  if v_txn.id is null then
    raise exception 'FAIL: manager should always be able to create loans regardless of the staff flag';
  end if;
  raise notice 'PASS: manager is unaffected by staff_can_create_loans (always permitted)';
end;
$$;

-- ---------------------------------------------------------------------
-- 6. PIN unlock: set, verify success, verify failure, and rate limiting
--    (5 wrong attempts locks out for 15 minutes; a 6th attempt — even
--    with the correct PIN — is rejected while locked).
-- ---------------------------------------------------------------------

do $$
begin
  reset role;
  perform test_login('staff_a');
  set local role authenticated;

  perform public.set_pin('1234');
  raise notice 'PASS: set_pin() accepts a valid 4-digit PIN';

  begin
    perform public.set_pin('12');
    raise exception 'FAIL: a 2-digit PIN should be rejected';
  exception
    when others then
      if sqlerrm like 'set_pin: PIN must be%' then
        raise notice 'PASS: set_pin() rejects a too-short PIN';
      else
        raise;
      end if;
  end;

  if public.verify_pin('1234') <> true then
    raise exception 'FAIL: verify_pin() should accept the correct PIN';
  end if;
  raise notice 'PASS: verify_pin() accepts the correct PIN and resets attempt state';

  if public.verify_pin('0000') <> false then
    raise exception 'FAIL: verify_pin() should reject an incorrect PIN';
  end if;
  raise notice 'PASS: verify_pin() rejects an incorrect PIN (returns false, not an error)';
end;
$$;

do $$
declare
  v_result boolean;
  v_attempt int;
begin
  -- 4 more wrong attempts (5 total including the one above) should trip
  -- the lockout on the 5th.
  for v_attempt in 1..4 loop
    v_result := public.verify_pin('9999');
    if v_result <> false then
      raise exception 'FAIL: attempt % should have been rejected (wrong PIN)', v_attempt;
    end if;
  end loop;

  begin
    perform public.verify_pin('1234'); -- correct PIN, but should now be locked out
    raise exception 'FAIL: verify_pin() should refuse even the correct PIN once locked out';
  exception
    when others then
      if sqlerrm like 'verify_pin: too many incorrect attempts%' then
        raise notice 'PASS: verify_pin() enforces a 15-minute lockout after 5 consecutive wrong attempts, rejecting even the correct PIN: %', sqlerrm;
      else
        raise;
      end if;
  end;
end;
$$;

do $$
begin
  if public.pin_is_configured() <> true then
    raise exception 'FAIL: pin_is_configured() should report true for staff_a';
  end if;
  raise notice 'PASS: pin_is_configured() reports true without exposing the hash or attempt state';

  perform public.clear_pin();

  if public.pin_is_configured() <> false then
    raise exception 'FAIL: pin_is_configured() should report false after clear_pin()';
  end if;
  raise notice 'PASS: clear_pin() removes the PIN';
end;
$$;

-- ---------------------------------------------------------------------
-- 7. pin_credentials has no SELECT policy at all — a direct query
--    returns nothing even for the owning user, confirming access is
--    only possible through the functions above.
-- ---------------------------------------------------------------------

do $$
declare
  v_visible int;
begin
  reset role;
  perform test_login('staff_a');
  set local role authenticated;
  -- staff_a still has a row here from section 6 (clear_pin only removes
  -- the row via its own SECURITY DEFINER path; re-set one to prove the
  -- point against a row that definitely exists).
  perform public.set_pin('5678');

  select count(*) into v_visible from public.pin_credentials;
  if v_visible <> 0 then
    raise exception 'FAIL: pin_credentials should not be directly selectable, saw % row(s)', v_visible;
  end if;
  raise notice 'PASS: pin_credentials has zero direct SELECT access even for the owning user (function-only access)';
end;
$$;

-- ---------------------------------------------------------------------
-- 8. Shop isolation still holds for the new onboarding fields: owner_b
--    cannot see or change shop A's app_settings timezone/receipt prefix.
-- ---------------------------------------------------------------------

do $$
declare
  v_shop_a uuid;
  v_visible int;
  v_rows_affected int;
begin
  reset role;
  perform test_login('owner_b');
  set local role authenticated;

  select value into v_shop_a from test_fixtures where key = 'shop_a';

  select count(*) into v_visible from public.app_settings where shop_id = v_shop_a;
  if v_visible <> 0 then
    raise exception 'FAIL: owner_b should not see shop A''s app_settings, saw % row(s)', v_visible;
  end if;

  update public.app_settings set receipt_number_prefix = 'HACK' where shop_id = v_shop_a;
  get diagnostics v_rows_affected = row_count;
  if v_rows_affected <> 0 then
    raise exception 'FAIL: owner_b should not be able to modify shop A''s app_settings';
  end if;

  raise notice 'PASS: shop isolation holds for the new onboarding/app_settings fields (0 visible, 0 modifiable)';
end;
$$;

-- ---------------------------------------------------------------------
-- 9. Customer-photo attachment is capability-gated and path-scoped. The
-- narrow RPC lets permitted staff attach a photo without granting them a
-- broad customer UPDATE policy; the normal audit trigger records it.
-- ---------------------------------------------------------------------

do $$
declare
  v_shop_id uuid;
  v_customer_id uuid;
  v_customer public.customers;
begin
  reset role;
  perform test_login('staff_a');
  set local role authenticated;
  select value into v_shop_id from test_fixtures where key = 'shop_a';
  select value into v_customer_id from test_fixtures where key = 'customer_1';

  select * into v_customer from public.set_customer_photo(
    v_customer_id, v_shop_id::text || '/' || v_customer_id::text || '/profile.jpg'
  );
  if v_customer.photo_path is null then
    raise exception 'FAIL: permitted staff could not attach a customer photo';
  end if;
  raise notice 'PASS: permitted staff attaches a customer photo through the narrow audited RPC';

  begin
    perform public.set_customer_photo(v_customer_id, v_shop_id::text || '/wrong-customer/profile.jpg');
    raise exception 'FAIL: customer photo path outside the customer folder should be rejected';
  exception when others then
    if sqlerrm like 'set_customer_photo: photo path must be%' then
      raise notice 'PASS: customer photo RPC rejects a mismatched customer folder';
    else raise; end if;
  end;
end;
$$;

-- ---------------------------------------------------------------------
-- 10. Atomic, idempotent loan creation: two items attach in one commit;
-- retries return the original pledge, while invalid payloads leave no row.
-- ---------------------------------------------------------------------

do $$
declare
  v_customer_id uuid;
  v_first public.transactions;
  v_retry public.transactions;
  v_second public.transactions;
  v_before int;
  v_after int;
  v_key uuid := gen_random_uuid();
begin
  reset role;
  perform test_login('owner_a');
  set local role authenticated;
  select value into v_customer_id from test_fixtures where key = 'customer_1';
  select * into v_first from public.create_jewellery_loan(v_customer_id, 25000, 'MONTHLY', 1.5, null, current_date, 'test', v_key,
    '[{"jewellery_name":"Ring","metal_type":"GOLD","weight_grams":5,"quantity":1},{"jewellery_name":"Chain","metal_type":"GOLD","weight_grams":8,"quantity":1}]'::jsonb);
  if (select count(*) from public.jewellery_items where transaction_id = v_first.id) <> 2 then raise exception 'FAIL: loan items were not atomically created'; end if;
  select * into v_retry from public.create_jewellery_loan(v_customer_id, 25000, 'MONTHLY', 1.5, null, current_date, 'test', v_key,
    '[{"jewellery_name":"Ring","metal_type":"GOLD","weight_grams":5,"quantity":1}]'::jsonb);
  if v_retry.id <> v_first.id then raise exception 'FAIL: idempotent retry created a second pledge'; end if;
  select * into v_second from public.create_jewellery_loan(v_customer_id, 10000, 'YEARLY', 12, null, current_date, null, gen_random_uuid(),
    '[{"jewellery_name":"Coin","metal_type":"GOLD","weight_grams":2,"quantity":2}]'::jsonb);
  if v_second.pledge_code = v_first.pledge_code then raise exception 'FAIL: separate pledges need unique codes'; end if;
  select count(*) into v_before from public.transactions;
  begin
    perform public.create_jewellery_loan(v_customer_id, 10000, 'MONTHLY', 1, null, current_date, null, gen_random_uuid(), '[]'::jsonb);
    raise exception 'FAIL: empty item list should be rejected';
  exception when others then
    if sqlerrm not like 'create_jewellery_loan: at least one item is required%' then raise; end if;
  end;
  select count(*) into v_after from public.transactions;
  if v_before <> v_after then raise exception 'FAIL: rejected creation left a partial transaction'; end if;
  raise notice 'PASS: multi-item, multi-pledge, idempotent and rollback loan creation works';
end;
$$;

-- ---------------------------------------------------------------------
-- 11. Finance posting is server-authoritative: anniversary accrual, payment
-- allocation, idempotency and event history remain consistent.
-- ---------------------------------------------------------------------

do $$
declare
  v_customer_id uuid;
  v_loan public.transactions;
  v_result public.transactions;
  v_retry public.transactions;
  v_key uuid := '11111111-1111-1111-1111-111111111111';
  v_payment_count integer;
begin
  reset role;
  perform test_login('owner_a');
  set local role authenticated;
  select value into v_customer_id from test_fixtures where key = 'customer_1';
  select * into v_loan from public.create_jewellery_loan(v_customer_id, 50000, 'MONTHLY', 2, null, date '2025-01-31', 'finance test', gen_random_uuid(),
    '[{"jewellery_name":"Finance ring","metal_type":"GOLD","weight_grams":5,"quantity":1}]'::jsonb);
  select * into v_result from public.post_payment(v_loan.id, 20000, 'CASH', date '2025-02-28', v_key);
  if v_result.outstanding_principal <> 31000 or v_result.accrued_interest <> 0 or v_result.interest_periods_settled <> 1 then
    raise exception 'FAIL: 50k at 2%% monthly payment must allocate 1k interest then 19k principal';
  end if;
  if not exists (select 1 from public.interest_events where transaction_id = v_loan.id and event_type = 'ACCRUAL' and amount = 1000)
     or not exists (select 1 from public.interest_events where transaction_id = v_loan.id and event_type = 'SETTLEMENT' and amount = 1000) then
    raise exception 'FAIL: accrual and settlement events must be persisted';
  end if;
  select * into v_retry from public.post_payment(v_loan.id, 20000, 'CASH', date '2025-02-28', v_key);
  select count(*) into v_payment_count from public.payments where transaction_id = v_loan.id;
  if v_retry.outstanding_principal <> 31000 or v_payment_count <> 1 then
    raise exception 'FAIL: idempotency replay double-posted a payment';
  end if;
  begin
    perform public.post_payment(v_loan.id, 999999, 'CASH', date '2025-03-31', gen_random_uuid());
    raise exception 'FAIL: overpayment must be rejected';
  exception when others then
    if sqlerrm not like 'post_payment: overpayment is not permitted%' then raise; end if;
  end;
  raise notice 'PASS: financial accrual, allocation, idempotency and audit events work';
end;
$$;

-- ---------------------------------------------------------------------
-- 12. Phase 7: a payment is isolated to its selected pledge, retries do not
-- post twice, and redemption requires an explicit jewellery-return consent.
-- ---------------------------------------------------------------------

do $$
declare
  v_customer_id uuid; v_one public.transactions; v_two public.transactions; v_after public.transactions;
  v_before_count integer; v_after_count integer; v_key uuid := '22222222-2222-2222-2222-222222222222';
begin
  reset role; perform test_login('owner_a'); set local role authenticated;
  select value into v_customer_id from test_fixtures where key = 'customer_1';
  -- Customer is archived by the final legacy test; reactivate only for this independent fixture.
  update public.customers set is_active = true where id = v_customer_id;
  select * into v_one from public.create_jewellery_loan(v_customer_id,50000,'MONTHLY',2,null,date '2025-01-01',null,gen_random_uuid(),'[{"jewellery_name":"Pledge one","metal_type":"GOLD","weight_grams":1,"quantity":1}]');
  select * into v_two from public.create_jewellery_loan(v_customer_id,50000,'MONTHLY',2,null,date '2025-01-01',null,gen_random_uuid(),'[{"jewellery_name":"Pledge two","metal_type":"GOLD","weight_grams":1,"quantity":1}]');
  select count(*) into v_before_count from public.payments where transaction_id=v_one.id;
  select * into v_after from public.post_payment(v_one.id,2000,'UPI',date '2025-02-01',v_key,'UPI-1','first instalment',false);
  if v_after.outstanding_principal <> 49000 or v_after.accrued_interest <> 0 then raise exception 'FAIL: payment allocation on selected pledge is wrong'; end if;
  if (select outstanding_principal from public.transactions where id=v_two.id) <> 50000 then raise exception 'FAIL: payment mixed balances between pledges'; end if;
  perform public.post_payment(v_one.id,2000,'UPI',date '2025-02-01',v_key,'UPI-1','network retry',false);
  select count(*) into v_after_count from public.payments where transaction_id=v_one.id;
  if v_after_count <> v_before_count + 1 then raise exception 'FAIL: retry double-posted selected pledge'; end if;
  begin
    perform public.post_payment(v_one.id,49000,'CASH',date '2025-02-01',gen_random_uuid(),null,null,false);
    raise exception 'FAIL: redemption must require return confirmation';
  exception when others then if sqlerrm not like 'post_payment: confirm jewellery return%' then raise; end if; end;
  select * into v_after from public.post_payment(v_one.id,49000,'CASH',date '2025-02-01',gen_random_uuid(),null,'final settlement',true);
  if v_after.status <> 'REDEEMED' or v_after.jewellery_returned_at is null or v_after.jewellery_returned_by is null then raise exception 'FAIL: confirmed final settlement did not record jewellery return'; end if;
  if not exists(select 1 from public.payments where transaction_id=v_one.id and receipt_number is not null and interest_amount=0 and principal_amount=49000) then raise exception 'FAIL: final receipt/allocation missing'; end if;
  raise notice 'PASS: Phase 7 isolated pledge payments, retry, allocation and redemption confirmation work';
end;
$$;

-- ---------------------------------------------------------------------
-- 13. Customer archiving is a retained-row UPDATE, not a hard delete.
-- ---------------------------------------------------------------------

do $$
declare
  v_customer_id uuid;
  v_active boolean;
begin
  reset role;
  perform test_login('owner_a');
  set local role authenticated;
  select value into v_customer_id from test_fixtures where key = 'customer_1';
  update public.customers set is_active = false where id = v_customer_id;
  select is_active into v_active from public.customers where id = v_customer_id;
  if v_active is distinct from false then
    raise exception 'FAIL: customer archive must retain the row with is_active=false';
  end if;
  raise notice 'PASS: customer archive retains the row and marks it inactive';
end;
$$;

-- ---------------------------------------------------------------------
reset role;
drop function test_login(text);

do $$
begin
  raise notice '=====================================================';
  raise notice 'ALL PHASE 3 TESTS PASSED';
  raise notice '=====================================================';
end;
$$;
