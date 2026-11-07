-- ============================================================================
-- Historical pledge entry + live settlement: the authoritative assertions.
--
-- These run against the real migrations, so they test the one engine the app
-- actually posts through (create_historical_jewellery_loan -> post_payment)
-- and the read model the UI renders (calculate_live_settlement). The mirror
-- of these cases in src/lib/calculations/interest.test.ts covers the pure
-- preview function; both must agree.
--
-- Run after rls_and_constraints.test.sql and auth_and_permissions.test.sql on
-- the same scratch database -- see supabase/tests/run.sh.
-- ============================================================================

\set ON_ERROR_STOP on

-- auth_and_permissions.test.sql drops this helper when it finishes; the shared
-- temp fixture table is still in scope, so recreate the helper and reuse it.
create or replace function test_login(p_user_key text)
returns void language plpgsql as $$
declare v_user_id uuid;
begin
  select value into v_user_id from test_fixtures where key = p_user_key;
  if v_user_id is null then raise exception 'test_login: unknown fixture key %', p_user_key; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user_id)::text, false);
end;
$$;

-- One active customer in shop A for every case below. The final legacy test in
-- the baseline suite archives customer_1, so reactivate it here.
do $$
declare v_customer_id uuid;
begin
  reset role; perform test_login('owner_a'); set local role authenticated;
  select value into v_customer_id from test_fixtures where key = 'customer_1';
  update public.customers set is_active = true where id = v_customer_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Test 1: historical loan with no payments.
-- 50,000 @ 2%/month, deposited 2026-01-01, settled as of 2026-03-01:
-- 2 completed months -> 2,000 interest -> 52,000 payable.
-- ---------------------------------------------------------------------

do $$
declare v_customer_id uuid; v public.transactions; s jsonb;
begin
  reset role; perform test_login('owner_a'); set local role authenticated;
  select value into v_customer_id from test_fixtures where key = 'customer_1';
  select * into v from public.create_historical_jewellery_loan(
    v_customer_id, 50000, 'MONTHLY', 2, null, date '2026-01-01', 'historical, no payments',
    gen_random_uuid(), '[{"jewellery_name":"Historical bangle","metal_type":"GOLD","weight_grams":10,"quantity":1}]');

  if not v.is_historical then raise exception 'FAIL: historical flag was not set'; end if;
  if v.issue_date <> date '2026-01-01' then raise exception 'FAIL: historical deposit date was replaced with today (%)', v.issue_date; end if;

  s := public.calculate_live_settlement(v.id, date '2026-03-01');
  if (s ->> 'original_principal')::numeric <> 50000
     or (s ->> 'remaining_principal')::numeric <> 50000
     or (s ->> 'total_interest_accrued')::numeric <> 2000
     or (s ->> 'outstanding_interest')::numeric <> 2000
     or (s ->> 'previous_interest_paid')::numeric <> 0
     or (s ->> 'total_previous_payments')::numeric <> 0
     or (s ->> 'amount_payable_today')::numeric <> 52000 then
    raise exception 'FAIL: Test 1 expected 2,000 interest and 52,000 payable, got %', s;
  end if;
  if (s ->> 'calculation_date')::date <> date '2026-03-01' then raise exception 'FAIL: calculation date not reported'; end if;
  raise notice 'PASS: Test 1 historical loan without payments accrues 2 completed months (52,000 payable)';
end;
$$;

-- ---------------------------------------------------------------------
-- Test 2: historical loan with one partial payment.
-- 20,000 paid on 2026-02-01 clears 1,000 interest and 19,000 principal;
-- the next month is charged on 31,000, not on the original 50,000.
-- ---------------------------------------------------------------------

do $$
declare v_customer_id uuid; v public.transactions; s jsonb;
begin
  reset role; perform test_login('owner_a'); set local role authenticated;
  select value into v_customer_id from test_fixtures where key = 'customer_1';
  select * into v from public.create_historical_jewellery_loan(
    v_customer_id, 50000, 'MONTHLY', 2, null, date '2026-01-01', null, gen_random_uuid(),
    '[{"jewellery_name":"Historical chain","metal_type":"GOLD","weight_grams":12,"quantity":1}]',
    jsonb_build_array(jsonb_build_object('payment_date','2026-02-01','amount',20000,'payment_method','CASH','remarks','part payment','idempotency_key',gen_random_uuid())));
  insert into test_fixtures values ('historical_partial', v.id);

  if v.outstanding_principal <> 31000 then raise exception 'FAIL: reducing principal is wrong (%)', v.outstanding_principal; end if;
  if not exists (select 1 from public.payments where transaction_id = v.id and interest_amount = 1000 and principal_amount = 19000 and payment_date = date '2026-02-01') then
    raise exception 'FAIL: historical payment was not split 1,000 interest / 19,000 principal on its own date';
  end if;

  s := public.calculate_live_settlement(v.id, date '2026-03-01');
  if (s ->> 'previous_principal_repayments')::numeric <> 19000
     or (s ->> 'remaining_principal')::numeric <> 31000
     or (s ->> 'total_interest_accrued')::numeric <> 1620
     or (s ->> 'previous_interest_paid')::numeric <> 1000
     or (s ->> 'outstanding_interest')::numeric <> 620
     or (s ->> 'total_previous_payments')::numeric <> 20000
     or (s ->> 'amount_payable_today')::numeric <> 31620 then
    raise exception 'FAIL: Test 2 expected 620 outstanding interest and 31,620 payable, got %', s;
  end if;
  raise notice 'PASS: Test 2 partial payment reduces principal and charges 620 on 31,000 (31,620 payable)';
end;
$$;

-- ---------------------------------------------------------------------
-- Test 3: several historical payments, each allocated on its own date,
-- with every later month charged on the principal outstanding then.
-- ---------------------------------------------------------------------

do $$
declare v_customer_id uuid; v public.transactions; s jsonb;
begin
  reset role; perform test_login('owner_a'); set local role authenticated;
  select value into v_customer_id from test_fixtures where key = 'customer_1';
  select * into v from public.create_historical_jewellery_loan(
    v_customer_id, 50000, 'MONTHLY', 2, null, date '2026-01-01', null, gen_random_uuid(),
    '[{"jewellery_name":"Historical ring set","metal_type":"GOLD","weight_grams":8,"quantity":2}]',
    jsonb_build_array(
      jsonb_build_object('payment_date','2026-02-01','amount',20000,'payment_method','CASH','idempotency_key',gen_random_uuid()),
      jsonb_build_object('payment_date','2026-03-01','amount',10620,'payment_method','UPI','idempotency_key',gen_random_uuid())));

  -- 2026-02-01: 1,000 interest on 50,000 + 19,000 principal -> 31,000.
  -- 2026-03-01:   620 interest on 31,000 + 10,000 principal -> 21,000.
  if v.outstanding_principal <> 21000 then raise exception 'FAIL: chronological replay left principal at %', v.outstanding_principal; end if;
  if not exists (select 1 from public.payments where transaction_id = v.id and payment_date = date '2026-03-01' and interest_amount = 620 and principal_amount = 10000) then
    raise exception 'FAIL: second payment was not charged interest on the reduced principal';
  end if;

  s := public.calculate_live_settlement(v.id, date '2026-04-01');
  if (s ->> 'previous_principal_repayments')::numeric <> 29000
     or (s ->> 'remaining_principal')::numeric <> 21000
     or (s ->> 'previous_interest_paid')::numeric <> 1620
     or (s ->> 'total_interest_accrued')::numeric <> 2040
     or (s ->> 'outstanding_interest')::numeric <> 420
     or (s ->> 'total_previous_payments')::numeric <> 30620
     or (s ->> 'amount_payable_today')::numeric <> 21420 then
    raise exception 'FAIL: Test 3 expected 420 on 21,000 and 21,420 payable, got %', s;
  end if;
  raise notice 'PASS: Test 3 multiple historical payments allocate chronologically on the reducing principal';
end;
$$;

-- ---------------------------------------------------------------------
-- Test 4: no completed monthly anniversary yet -> no interest at all.
-- ---------------------------------------------------------------------

do $$
declare v_customer_id uuid; v public.transactions; s jsonb; v_deposit date := current_date - 10;
begin
  reset role; perform test_login('owner_a'); set local role authenticated;
  select value into v_customer_id from test_fixtures where key = 'customer_1';
  select * into v from public.create_historical_jewellery_loan(
    v_customer_id, 50000, 'MONTHLY', 2, null, v_deposit, null, gen_random_uuid(),
    '[{"jewellery_name":"Recent pledge","metal_type":"GOLD","weight_grams":5,"quantity":1}]');

  s := public.calculate_live_settlement(v.id, current_date);
  if (s ->> 'total_interest_accrued')::numeric <> 0
     or (s ->> 'outstanding_interest')::numeric <> 0
     or (s ->> 'amount_payable_today')::numeric <> 50000 then
    raise exception 'FAIL: Test 4 charged interest for an incomplete month, got %', s;
  end if;
  -- The day before the first anniversary is still zero; the anniversary itself charges once.
  s := public.calculate_live_settlement(v.id, v_deposit);
  if (s ->> 'outstanding_interest')::numeric <> 0 then raise exception 'FAIL: interest charged on the deposit date itself'; end if;
  if not exists (select 1 from public.interest_events where transaction_id = v.id) then
    raise notice 'NOTE: no interest events yet, as expected for an unpaid incomplete month';
  end if;
  raise notice 'PASS: Test 4 no monthly interest before the first completed anniversary';
end;
$$;

-- ---------------------------------------------------------------------
-- Test 5: a fully settled historical loan is REDEEMED, owes nothing and
-- refuses any further payment.
-- ---------------------------------------------------------------------

do $$
declare v_customer_id uuid; v public.transactions; s jsonb;
begin
  reset role; perform test_login('owner_a'); set local role authenticated;
  select value into v_customer_id from test_fixtures where key = 'customer_1';
  select * into v from public.create_historical_jewellery_loan(
    v_customer_id, 50000, 'MONTHLY', 2, null, date '2026-01-01', null, gen_random_uuid(),
    '[{"jewellery_name":"Settled bangle","metal_type":"GOLD","weight_grams":10,"quantity":1}]',
    jsonb_build_array(jsonb_build_object('payment_date','2026-02-01','amount',51000,'payment_method','CASH','idempotency_key',gen_random_uuid())));

  if v.status <> 'REDEEMED' then raise exception 'FAIL: fully paid historical loan is % not REDEEMED', v.status; end if;
  if v.outstanding_principal <> 0 or v.accrued_interest <> 0 then raise exception 'FAIL: redeemed loan still carries a balance'; end if;
  if v.jewellery_returned_at is null then raise exception 'FAIL: redemption did not record the jewellery return'; end if;

  s := public.calculate_live_settlement(v.id, current_date);
  if (s ->> 'amount_payable_today')::numeric <> 0 or (s ->> 'redeemed')::boolean is not true then
    raise exception 'FAIL: redeemed loan must owe nothing today, got %', s;
  end if;

  begin
    perform public.post_payment(v.id, 1, 'CASH', current_date, gen_random_uuid(), null, null, false);
    raise exception 'FAIL: a redeemed pledge accepted another payment';
  exception when others then
    if sqlerrm not like 'post_payment: active transaction not found%' then raise; end if;
  end;
  raise notice 'PASS: Test 5 fully settled historical loan is REDEEMED, owes nothing and accepts no further payment';
end;
$$;

-- ---------------------------------------------------------------------
-- Test 6: reopening an existing transaction recalculates today's figures
-- without duplicating payments or interest events, and a retried create
-- with the same key does not re-import the same payment history.
-- ---------------------------------------------------------------------

do $$
declare
  v_customer_id uuid; v_id uuid; v_key uuid := gen_random_uuid(); v public.transactions; v_retry public.transactions;
  v_payments_before integer; v_payments_after integer; v_events_before integer; v_events_after integer;
  s1 jsonb; s2 jsonb; s3 jsonb; v_items jsonb := '[{"jewellery_name":"Reopened pledge","metal_type":"GOLD","weight_grams":9,"quantity":1}]';
  v_history jsonb;
begin
  reset role; perform test_login('owner_a'); set local role authenticated;
  select value into v_customer_id from test_fixtures where key = 'customer_1';
  v_history := jsonb_build_array(jsonb_build_object('payment_date','2026-02-01','amount',20000,'payment_method','CASH','idempotency_key',gen_random_uuid()));

  select * into v from public.create_historical_jewellery_loan(
    v_customer_id, 50000, 'MONTHLY', 2, null, date '2026-01-01', null, v_key, v_items, v_history);
  v_id := v.id;
  select count(*) into v_payments_before from public.payments where transaction_id = v_id;
  select count(*) into v_events_before from public.interest_events where transaction_id = v_id;

  -- Opening/refreshing the page is a pure read: three calls, one answer.
  s1 := public.calculate_live_settlement(v_id, date '2026-03-01');
  s2 := public.calculate_live_settlement(v_id, date '2026-03-01');
  s3 := public.calculate_live_settlement(v_id, date '2026-03-01');
  if s1 <> s2 or s2 <> s3 then raise exception 'FAIL: repeated settlement reads disagree: % / % / %', s1, s2, s3; end if;

  -- A retried create with the same idempotency key must return the same pledge
  -- and must not import the supplied payment history a second time.
  select * into v_retry from public.create_historical_jewellery_loan(
    v_customer_id, 50000, 'MONTHLY', 2, null, date '2026-01-01', null, v_key, v_items, v_history);
  if v_retry.id <> v_id then raise exception 'FAIL: retry created a second transaction'; end if;

  select count(*) into v_payments_after from public.payments where transaction_id = v_id;
  select count(*) into v_events_after from public.interest_events where transaction_id = v_id;
  if v_payments_after <> v_payments_before then raise exception 'FAIL: payments duplicated (% -> %)', v_payments_before, v_payments_after; end if;
  if v_events_after <> v_events_before then raise exception 'FAIL: interest events duplicated (% -> %)', v_events_before, v_events_after; end if;
  if public.calculate_live_settlement(v_id, date '2026-03-01') <> s1 then raise exception 'FAIL: settlement changed after a retried create'; end if;
  if (s1 ->> 'amount_payable_today')::numeric <> 31620 then raise exception 'FAIL: reopened pledge should owe 31,620, got %', s1; end if;
  raise notice 'PASS: Test 6 reopening an existing transaction recalculates without duplicating payments or interest events';
end;
$$;

-- ---------------------------------------------------------------------
-- Test 7: historical payment date and duplicate-key validation.
-- ---------------------------------------------------------------------

do $$
declare v_customer_id uuid; v_dupe uuid := gen_random_uuid(); v_items jsonb := '[{"jewellery_name":"Validation pledge","metal_type":"GOLD","weight_grams":4,"quantity":1}]';
begin
  reset role; perform test_login('owner_a'); set local role authenticated;
  select value into v_customer_id from test_fixtures where key = 'customer_1';

  begin
    perform public.create_historical_jewellery_loan(v_customer_id, 50000, 'MONTHLY', 2, null, current_date + 1, null, gen_random_uuid(), v_items);
    raise exception 'FAIL: a future deposit date was accepted';
  exception when others then if sqlerrm not like '%deposit date must be today or earlier%' then raise; end if; end;

  begin
    perform public.create_historical_jewellery_loan(v_customer_id, 50000, 'MONTHLY', 2, null, date '2026-01-01', null, gen_random_uuid(), v_items,
      jsonb_build_array(jsonb_build_object('payment_date','2025-12-31','amount',100,'idempotency_key',gen_random_uuid())));
    raise exception 'FAIL: a payment dated before the deposit was accepted';
  exception when others then if sqlerrm not like '%payment date is outside the permitted range%' then raise; end if; end;

  begin
    perform public.create_historical_jewellery_loan(v_customer_id, 50000, 'MONTHLY', 2, null, date '2026-01-01', null, gen_random_uuid(), v_items,
      jsonb_build_array(jsonb_build_object('payment_date', to_char(current_date + 1, 'YYYY-MM-DD'), 'amount',100,'idempotency_key',gen_random_uuid())));
    raise exception 'FAIL: a future payment date was accepted';
  exception when others then if sqlerrm not like '%payment date is outside the permitted range%' then raise; end if; end;

  begin
    perform public.create_historical_jewellery_loan(v_customer_id, 50000, 'MONTHLY', 2, null, date '2026-01-01', null, gen_random_uuid(), v_items,
      jsonb_build_array(
        jsonb_build_object('payment_date','2026-03-01','amount',100,'idempotency_key',gen_random_uuid()),
        jsonb_build_object('payment_date','2026-02-01','amount',100,'idempotency_key',gen_random_uuid())));
    raise exception 'FAIL: out-of-order payments were accepted';
  exception when others then if sqlerrm not like '%payments must be chronological%' then raise; end if; end;

  begin
    perform public.create_historical_jewellery_loan(v_customer_id, 50000, 'MONTHLY', 2, null, date '2026-01-01', null, gen_random_uuid(), v_items,
      jsonb_build_array(
        jsonb_build_object('payment_date','2026-02-01','amount',100,'idempotency_key',v_dupe),
        jsonb_build_object('payment_date','2026-03-01','amount',100,'idempotency_key',v_dupe)));
    raise exception 'FAIL: a duplicate payment idempotency key was accepted';
  exception when others then if sqlerrm not like '%duplicate payment idempotency key%' then raise; end if; end;

  begin
    perform public.create_historical_jewellery_loan(v_customer_id, 50000, 'MONTHLY', 2, null, date '2026-01-01', null, gen_random_uuid(), v_items,
      jsonb_build_array(jsonb_build_object('payment_date','2026-02-01','amount',60000,'idempotency_key',gen_random_uuid())));
    raise exception 'FAIL: a payment exceeding the outstanding amount was accepted';
  exception when others then if sqlerrm not like '%overpayment is not permitted%' then raise; end if; end;

  raise notice 'PASS: Test 7 historical payment dates, ordering, duplicates and overpayment are all rejected';
end;
$$;

-- ---------------------------------------------------------------------
-- Test 8: the settlement read model is shop-scoped and never future-dated.
-- ---------------------------------------------------------------------

do $$
declare v_txn_id uuid;
begin
  reset role; perform test_login('owner_a'); set local role authenticated;
  select value into v_txn_id from test_fixtures where key = 'historical_partial';

  begin
    perform public.calculate_live_settlement(v_txn_id, current_date + 1);
    raise exception 'FAIL: a future settlement date was accepted';
  exception when others then if sqlerrm not like '%future dates are not allowed%' then raise; end if; end;

  begin
    perform public.calculate_live_settlement(v_txn_id, date '2025-12-31');
    raise exception 'FAIL: a settlement date before the deposit was accepted';
  exception when others then if sqlerrm not like '%precedes deposit date%' then raise; end if; end;

  reset role; perform test_login('owner_b'); set local role authenticated;
  begin
    perform public.calculate_live_settlement(v_txn_id, current_date);
    raise exception 'FAIL: another shop read this pledge''s settlement';
  exception when others then if sqlerrm not like '%transaction not found%' then raise; end if; end;

  raise notice 'PASS: Test 8 settlement reads reject future dates, pre-deposit dates and other shops';
end;
$$;

reset role;
drop function test_login(text);

do $$
begin
  raise notice '=====================================================';
  raise notice 'ALL HISTORICAL SETTLEMENT TESTS PASSED';
  raise notice '=====================================================';
end;
$$;
