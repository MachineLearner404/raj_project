-- ============================================================================
-- Real, executed assertions against the actual migrations in
-- supabase/migrations/ — run on a scratch local Postgres database with
-- supabase/tests/_local_pg_stub.sql applied first (see
-- supabase/tests/README.md for the exact commands).
--
-- Each test either prints "PASS: ..." or raises an exception that aborts
-- the whole script (the runner script uses `psql -v ON_ERROR_STOP=1`), so
-- a clean run with only PASS lines and a final summary is the evidence.
-- ============================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- Fixtures: two shops, each with an owner/manager/staff profile, so
-- cross-shop isolation has something real to fail against.
-- ---------------------------------------------------------------------

do $$
declare
  v_shop_a uuid;
  v_shop_b uuid;
  v_owner_a uuid := gen_random_uuid();
  v_manager_a uuid := gen_random_uuid();
  v_staff_a uuid := gen_random_uuid();
  v_owner_b uuid := gen_random_uuid();
begin
  insert into public.shops (name) values ('Test Shop A') returning id into v_shop_a;
  insert into public.shops (name) values ('Test Shop B') returning id into v_shop_b;

  insert into auth.users (id) values (v_owner_a), (v_manager_a), (v_staff_a), (v_owner_b);

  insert into public.profiles (id, shop_id, full_name, role) values
    (v_owner_a, v_shop_a, 'Owner A', 'owner'),
    (v_manager_a, v_shop_a, 'Manager A', 'manager'),
    (v_staff_a, v_shop_a, 'Staff A', 'staff'),
    (v_owner_b, v_shop_b, 'Owner B', 'owner');

  insert into public.app_settings (shop_id) values (v_shop_a), (v_shop_b);

  -- Stash ids in a temp table so later DO blocks (separate scopes) can
  -- find them by name instead of re-declaring literals everywhere.
  create temp table test_fixtures (key text primary key, value uuid);
  insert into test_fixtures values
    ('shop_a', v_shop_a), ('shop_b', v_shop_b),
    ('owner_a', v_owner_a), ('manager_a', v_manager_a),
    ('staff_a', v_staff_a), ('owner_b', v_owner_b);

  -- SET ROLE authenticated (used throughout this script) fully drops
  -- superuser privileges for the rest of the session, not just RLS — so
  -- the test role needs an explicit grant on this scratch table. This is
  -- test bookkeeping, not a business table, so a broad grant is fine.
  execute 'grant all on test_fixtures to authenticated';
end;
$$;

-- Helper: become a given user for the rest of the current session (used
-- between top-level statements, not inside a DO block, since SET ROLE
-- inside a DO block doesn't escape it).
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
-- 1. Shop-scoped SELECT isolation: Owner A cannot see Shop B's data.
-- ---------------------------------------------------------------------

select test_login('owner_a');
set role authenticated;

do $$
declare
  v_shop_a uuid; v_shop_b uuid;
  v_visible_shops int;
begin
  select value into v_shop_a from test_fixtures where key = 'shop_a';
  select value into v_shop_b from test_fixtures where key = 'shop_b';
  select count(*) into v_visible_shops from public.shops;
  if v_visible_shops <> 1 then
    raise exception 'FAIL: owner_a should see exactly 1 shop (their own), saw %', v_visible_shops;
  end if;
  raise notice 'PASS: shops RLS — owner_a sees only their own shop (1 row)';
end;
$$;

-- ---------------------------------------------------------------------
-- 2. customers: staff can insert, cannot update.
-- ---------------------------------------------------------------------

reset role;
select test_login('staff_a');
set role authenticated;

do $$
declare
  v_shop_a uuid;
  v_customer_id uuid;
  v_rows_affected int;
begin
  select value into v_shop_a from test_fixtures where key = 'shop_a';

  insert into public.customers (
    shop_id, full_name, mobile, address, id_proof_type, id_proof_number, created_by
  ) values (
    v_shop_a, 'Demo Customer One', '+91 98230-11223', 'Demo address, Pune',
    'AADHAAR', '123456789012', (select value from test_fixtures where key = 'staff_a')
  ) returning id into v_customer_id;

  insert into test_fixtures values ('customer_1', v_customer_id);

  raise notice 'PASS: customers INSERT — staff can create a customer';

  -- Note: an UPDATE whose target row is excluded by the policy's USING
  -- clause does not raise an error — it just matches zero rows. That is
  -- the correct, documented Postgres RLS behavior (distinct from INSERT,
  -- where a WITH CHECK failure on the attempted new row DOES raise
  -- 42501 immediately, as tested in sections 6 and 13 below).
  update public.customers set full_name = 'Edited By Staff' where id = v_customer_id;
  get diagnostics v_rows_affected = row_count;

  if v_rows_affected <> 0 then
    raise exception 'FAIL: staff should not be able to update a customer, but % row(s) were updated', v_rows_affected;
  end if;
  raise notice 'PASS: customers UPDATE — staff''s update matched 0 rows (correctly excluded by RLS)';
end;
$$;

-- ---------------------------------------------------------------------
-- 3. mobile_normalized is computed server-side, regardless of input
--    formatting, and is NOT a unique constraint (two customers may
--    share a number).
-- ---------------------------------------------------------------------

do $$
declare
  v_normalized text;
  v_shop_a uuid;
  v_second_customer uuid;
begin
  select mobile_normalized into v_normalized
    from public.customers where id = (select value from test_fixtures where key = 'customer_1');

  if v_normalized <> '9823011223' then
    raise exception 'FAIL: expected mobile_normalized=9823011223, got %', v_normalized;
  end if;
  raise notice 'PASS: mobile normalization — "+91 98230-11223" -> "9823011223"';

  select value into v_shop_a from test_fixtures where key = 'shop_a';
  insert into public.customers (
    shop_id, full_name, mobile, address, id_proof_type, id_proof_number, created_by
  ) values (
    v_shop_a, 'Demo Customer Two (same number)', '9823011223', 'Same household, Pune',
    'PAN', 'ABCDE1234F', (select value from test_fixtures where key = 'staff_a')
  ) returning id into v_second_customer;

  raise notice 'PASS: mobile is NOT a unique constraint — a second customer with the same number was accepted';
end;
$$;

-- ---------------------------------------------------------------------
-- 4. customer_code is unique per shop and auto-assigned sequentially.
-- ---------------------------------------------------------------------

do $$
declare
  v_code_1 text; v_code_2 text;
begin
  select customer_code into v_code_1
    from public.customers where id = (select value from test_fixtures where key = 'customer_1');
  select customer_code into v_code_2
    from public.customers
    where full_name = 'Demo Customer Two (same number)';

  if v_code_1 = v_code_2 then
    raise exception 'FAIL: customer_code was not assigned uniquely (% = %)', v_code_1, v_code_2;
  end if;
  raise notice 'PASS: customer_code auto-assigned and unique: % , %', v_code_1, v_code_2;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. Cross-shop isolation on customers: Owner B cannot see Shop A's
--    customers, even by guessing an id.
-- ---------------------------------------------------------------------

reset role;
select test_login('owner_b');
set role authenticated;

do $$
declare
  v_visible int;
begin
  select count(*) into v_visible from public.customers
    where id = (select value from test_fixtures where key = 'customer_1');
  if v_visible <> 0 then
    raise exception 'FAIL: owner_b should not see shop A''s customer, saw % row(s)', v_visible;
  end if;
  raise notice 'PASS: customers RLS — owner_b cannot see shop A''s customer at all (0 rows, not even a permission error)';
end;
$$;

-- ---------------------------------------------------------------------
-- 6. transactions/jewellery_items/payments/interest_events cannot be
--    written directly by an authenticated user — only through the RPC
--    functions. Confirmed by attempting a direct INSERT.
-- ---------------------------------------------------------------------

reset role;
select test_login('manager_a');
set role authenticated;

do $$
declare
  v_shop_a uuid;
  v_customer_id uuid;
begin
  select value into v_shop_a from test_fixtures where key = 'shop_a';
  select value into v_customer_id from test_fixtures where key = 'customer_1';

  begin
    insert into public.transactions (
      shop_id, customer_id, principal_amount, interest_rate_percent_per_month,
      outstanding_principal, interest_settled_through, issue_date, tenure_months,
      due_date, created_by
    ) values (
      v_shop_a, v_customer_id, 100000, 1.5, 100000, current_date, current_date, 12,
      current_date + interval '1 year', (select value from test_fixtures where key = 'manager_a')
    );
    raise exception 'FAIL: direct INSERT into transactions should be blocked (no INSERT policy exists)';
  exception
    when sqlstate '42501' then
      raise notice 'PASS: transactions direct INSERT is blocked — only create_transaction() may write here';
  end;
end;
$$;

-- ---------------------------------------------------------------------
-- 7. create_transaction() RPC: manager can create a transaction with
--    items atomically; staff cannot (role check inside the function).
-- ---------------------------------------------------------------------

do $$
declare
  v_customer_id uuid;
  v_txn public.transactions;
  v_item_count int;
begin
  select value into v_customer_id from test_fixtures where key = 'customer_1';

  select * into v_txn from public.create_transaction(
    v_customer_id, 100000, 1.5, current_date, 12,
    '[{"category":"NECKLACE","description":"22K gold necklace","gross_weight_grams":40,"net_weight_grams":38,"stone_weight_grams":2,"purity_karat":22,"gold_rate_used_per_gram":6450,"estimated_value":245000}]'::jsonb
  );

  if v_txn.status <> 'ACTIVE' or v_txn.outstanding_principal <> 100000 then
    raise exception 'FAIL: create_transaction did not return the expected initial state';
  end if;

  select count(*) into v_item_count from public.jewellery_items where transaction_id = v_txn.id;
  if v_item_count <> 1 then
    raise exception 'FAIL: expected 1 jewellery item attached, found %', v_item_count;
  end if;

  insert into test_fixtures values ('txn_1', v_txn.id);
  raise notice 'PASS: create_transaction() — manager created a transaction (%) with its item atomically', v_txn.pledge_code;
end;
$$;

reset role;
select test_login('staff_a');
set role authenticated;

do $$
declare
  v_customer_id uuid;
begin
  select value into v_customer_id from test_fixtures where key = 'customer_1';
  begin
    perform public.create_transaction(
      v_customer_id, 50000, 1.5, current_date, 12,
      '[{"category":"RING","description":"Gold ring","gross_weight_grams":5,"net_weight_grams":5,"purity_karat":22,"gold_rate_used_per_gram":6450,"estimated_value":30000}]'::jsonb
    );
    raise exception 'FAIL: staff should not be permitted to create a transaction';
  exception
    when others then
      if sqlerrm like 'create_transaction: role staff is not permitted%' then
        raise notice 'PASS: create_transaction() correctly rejects staff: %', sqlerrm;
      else
        raise;
      end if;
  end;
end;
$$;

-- ---------------------------------------------------------------------
-- 8. record_payment(): staff CAN record payments. Partial payment
--    moves ACTIVE -> PARTIALLY_PAID and reduces outstanding_principal.
-- ---------------------------------------------------------------------

do $$
declare
  v_txn_id uuid;
  v_result public.transactions;
begin
  select value into v_txn_id from test_fixtures where key = 'txn_1';

  select * into v_result from public.record_payment(
    v_txn_id, 40000, 'PARTIAL_PRINCIPAL', 'CASH', current_date
  );

  if v_result.status <> 'PARTIALLY_PAID' or v_result.outstanding_principal <> 60000 then
    raise exception 'FAIL: expected PARTIALLY_PAID / 60000 outstanding, got % / %',
      v_result.status, v_result.outstanding_principal;
  end if;
  raise notice 'PASS: record_payment() — partial principal payment reduced balance to % and set status %',
    v_result.outstanding_principal, v_result.status;
end;
$$;

-- ---------------------------------------------------------------------
-- 9. record_payment(): FULL_CLOSURE must match outstanding principal
--    exactly, then transitions to REDEEMED.
-- ---------------------------------------------------------------------

do $$
declare
  v_txn_id uuid;
  v_result public.transactions;
begin
  select value into v_txn_id from test_fixtures where key = 'txn_1';

  begin
    perform public.record_payment(v_txn_id, 12345, 'FULL_CLOSURE', 'CASH', current_date);
    raise exception 'FAIL: full closure with the wrong amount should be rejected';
  exception
    when others then
      if sqlerrm like 'record_payment: full closure amount%' then
        raise notice 'PASS: record_payment() rejects a FULL_CLOSURE amount that does not match outstanding principal';
      else
        raise;
      end if;
  end;

  select * into v_result from public.record_payment(
    v_txn_id, 60000, 'FULL_CLOSURE', 'CASH', current_date
  );

  if v_result.status <> 'REDEEMED' or v_result.outstanding_principal <> 0 then
    raise exception 'FAIL: expected REDEEMED / 0 outstanding after full closure, got % / %',
      v_result.status, v_result.outstanding_principal;
  end if;
  raise notice 'PASS: record_payment() — full closure zeroed the balance and set status REDEEMED';
end;
$$;

-- ---------------------------------------------------------------------
-- 10. Controlled status transitions: REDEEMED is terminal, even via a
--     direct UPDATE (not just through record_payment()).
-- ---------------------------------------------------------------------

reset role; -- table owner, to isolate this test from the transactions RLS deny (we want to test the trigger, not RLS)

do $$
declare
  v_txn_id uuid;
begin
  select value into v_txn_id from test_fixtures where key = 'txn_1';
  begin
    update public.transactions set status = 'ACTIVE' where id = v_txn_id;
    raise exception 'FAIL: REDEEMED -> ACTIVE should be rejected by the status-transition trigger';
  exception
    when others then
      if sqlerrm like 'Invalid transaction status transition%' then
        raise notice 'PASS: status-transition trigger blocks REDEEMED -> ACTIVE: %', sqlerrm;
      else
        raise;
      end if;
  end;
end;
$$;

-- ---------------------------------------------------------------------
-- 11. Append-only enforcement: an authenticated user cannot UPDATE or
--     DELETE a payments row (no policy grants it).
-- ---------------------------------------------------------------------

select test_login('manager_a');
set role authenticated;

do $$
declare
  v_payment_id uuid;
  v_rows_affected int;
begin
  select id into v_payment_id from public.payments limit 1;

  -- No UPDATE/DELETE policy exists on payments at all, so (same as
  -- section 2) these match zero rows rather than raising an error.
  update public.payments set amount = 1 where id = v_payment_id;
  get diagnostics v_rows_affected = row_count;
  if v_rows_affected <> 0 then
    raise exception 'FAIL: payments should be append-only, but UPDATE affected % row(s)', v_rows_affected;
  end if;
  raise notice 'PASS: payments UPDATE matches 0 rows for authenticated users (append-only)';

  delete from public.payments where id = v_payment_id;
  get diagnostics v_rows_affected = row_count;
  if v_rows_affected <> 0 then
    raise exception 'FAIL: payments should be append-only, but DELETE affected % row(s)', v_rows_affected;
  end if;
  raise notice 'PASS: payments DELETE matches 0 rows for authenticated users (append-only)';

  -- Confirm the row genuinely still exists (wasn't actually deleted).
  if not exists (select 1 from public.payments where id = v_payment_id) then
    raise exception 'FAIL: the payments row is gone — DELETE was not actually blocked';
  end if;
  raise notice 'PASS: payments row still exists after the blocked DELETE attempt';
end;
$$;

-- ---------------------------------------------------------------------
-- 12. audit_logs: edits to customers are captured automatically, and
--     staff cannot read the audit trail (owner/manager only).
-- ---------------------------------------------------------------------

do $$
declare
  v_customer_id uuid;
  v_audit_count int;
begin
  select value into v_customer_id from test_fixtures where key = 'customer_1';
  update public.customers set notes = 'Updated by manager for audit test' where id = v_customer_id;

  select count(*) into v_audit_count
    from public.audit_logs
    where table_name = 'customers' and record_id = v_customer_id;

  if v_audit_count < 1 then
    raise exception 'FAIL: expected at least 1 audit_logs row for this customer, found %', v_audit_count;
  end if;
  raise notice 'PASS: audit_logs — % row(s) captured automatically for customer edits', v_audit_count;
end;
$$;

reset role;
select test_login('staff_a');
set role authenticated;

do $$
declare
  v_visible int;
begin
  select count(*) into v_visible from public.audit_logs;
  if v_visible <> 0 then
    raise exception 'FAIL: staff should not be able to read audit_logs, saw % row(s)', v_visible;
  end if;
  raise notice 'PASS: audit_logs RLS — staff sees 0 rows (owner/manager only)';
end;
$$;

-- ---------------------------------------------------------------------
-- 13. Storage: customer-photos bucket policies are shop-scoped.
-- ---------------------------------------------------------------------

reset role;
select test_login('staff_a');
set role authenticated;

do $$
declare
  v_shop_a uuid; v_shop_b uuid;
begin
  select value into v_shop_a from test_fixtures where key = 'shop_a';
  select value into v_shop_b from test_fixtures where key = 'shop_b';

  insert into storage.objects (bucket_id, name)
    values ('customer-photos', v_shop_a::text || '/some-customer/id-proof.jpg');
  raise notice 'PASS: storage.objects INSERT — staff can upload under their own shop''s folder';

  begin
    insert into storage.objects (bucket_id, name)
      values ('customer-photos', v_shop_b::text || '/some-customer/id-proof.jpg');
    raise exception 'FAIL: uploading under a different shop''s folder should be blocked';
  exception
    when sqlstate '42501' then
      raise notice 'PASS: storage.objects INSERT is blocked for another shop''s folder path';
  end;
end;
$$;

do $$
declare
  v_visible int;
begin
  select count(*) into v_visible from storage.objects where bucket_id = 'customer-photos';
  if v_visible <> 1 then
    raise exception 'FAIL: expected to see exactly 1 object (own shop''s), saw %', v_visible;
  end if;
  raise notice 'PASS: storage.objects SELECT — only own-shop objects are visible (% row)', v_visible;
end;
$$;

reset role;

-- ---------------------------------------------------------------------
drop function test_login(text);

do $$
begin
  raise notice '=====================================================';
  raise notice 'ALL TESTS PASSED';
  raise notice '=====================================================';
end;
$$;
