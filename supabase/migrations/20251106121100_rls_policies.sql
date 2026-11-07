-- Row Level Security. Every table is shop-scoped: a row is visible/
-- writable only to an authenticated user whose profiles.shop_id matches
-- the row's shop_id, per docs/08-security-threat-checklist.md's
-- "RLS is the real boundary, not client-side checks" rule.
--
-- transactions, jewellery_items, payments, interest_events deliberately
-- get NO direct INSERT/UPDATE policy for authenticated users — those
-- tables are written only through the SECURITY DEFINER functions in
-- 20251106121000_rpc_functions.sql, which bypass RLS as the table owner.
-- There is also no DELETE policy anywhere in this project: nothing is
-- hard-deleted; customers/profiles use is_active, transactions use
-- status.

alter table public.shops enable row level security;
alter table public.profiles enable row level security;
alter table public.customers enable row level security;
alter table public.transactions enable row level security;
alter table public.jewellery_items enable row level security;
alter table public.payments enable row level security;
alter table public.interest_events enable row level security;
alter table public.audit_logs enable row level security;
alter table public.app_settings enable row level security;

-- ---------------------------------------------------------------------
-- shops: read your own shop; only the owner can update it. Row creation
-- happens during shop onboarding (service-role key, outside app RLS) —
-- no INSERT policy for normal users.
-- ---------------------------------------------------------------------

create policy shops_select_own on public.shops
  for select to authenticated
  using (id = public.current_shop_id());

create policy shops_update_owner_only on public.shops
  for update to authenticated
  using (id = public.current_shop_id() and public.current_role() = 'owner')
  with check (id = public.current_shop_id() and public.current_role() = 'owner');

-- ---------------------------------------------------------------------
-- profiles: see your shop's colleagues; only an owner can add/edit
-- profiles (invite staff, change roles, deactivate).
-- ---------------------------------------------------------------------

create policy profiles_select_same_shop on public.profiles
  for select to authenticated
  using (shop_id = public.current_shop_id());

create policy profiles_insert_owner_only on public.profiles
  for insert to authenticated
  with check (shop_id = public.current_shop_id() and public.current_role() = 'owner');

create policy profiles_update_owner_only on public.profiles
  for update to authenticated
  using (shop_id = public.current_shop_id() and public.current_role() = 'owner')
  with check (shop_id = public.current_shop_id() and public.current_role() = 'owner');

-- ---------------------------------------------------------------------
-- customers: any shop member can read/create; only manager/owner can
-- edit (resolves the "who may edit a customer record" open question
-- from docs/03-business-workflows.md Workflow 1 — confirm if you want
-- staff to also have edit rights).
-- ---------------------------------------------------------------------

create policy customers_select_same_shop on public.customers
  for select to authenticated
  using (shop_id = public.current_shop_id());

create policy customers_insert_same_shop on public.customers
  for insert to authenticated
  with check (
    shop_id = public.current_shop_id()
    and public.current_role() in ('owner', 'manager', 'staff')
  );

create policy customers_update_manager_or_owner on public.customers
  for update to authenticated
  using (shop_id = public.current_shop_id() and public.current_role() in ('owner', 'manager'))
  with check (shop_id = public.current_shop_id() and public.current_role() in ('owner', 'manager'));

-- ---------------------------------------------------------------------
-- transactions / jewellery_items / payments / interest_events:
-- READ ONLY for authenticated users. All writes go through
-- create_transaction() / record_payment() / cancel_transaction().
-- ---------------------------------------------------------------------

create policy transactions_select_same_shop on public.transactions
  for select to authenticated
  using (shop_id = public.current_shop_id());

create policy jewellery_items_select_same_shop on public.jewellery_items
  for select to authenticated
  using (shop_id = public.current_shop_id());

create policy payments_select_same_shop on public.payments
  for select to authenticated
  using (shop_id = public.current_shop_id());

create policy interest_events_select_same_shop on public.interest_events
  for select to authenticated
  using (shop_id = public.current_shop_id());

-- ---------------------------------------------------------------------
-- audit_logs: read-only for owner/manager (staff don't need to see the
-- edit trail); never writable by normal users (write_audit_log() is
-- SECURITY DEFINER and bypasses this).
-- ---------------------------------------------------------------------

create policy audit_logs_select_owner_or_manager on public.audit_logs
  for select to authenticated
  using (shop_id = public.current_shop_id() and public.current_role() in ('owner', 'manager'));

-- ---------------------------------------------------------------------
-- app_settings: any shop member can read (loan forms need the defaults);
-- only the owner can change business rules.
-- ---------------------------------------------------------------------

create policy app_settings_select_same_shop on public.app_settings
  for select to authenticated
  using (shop_id = public.current_shop_id());

create policy app_settings_update_owner_only on public.app_settings
  for update to authenticated
  using (shop_id = public.current_shop_id() and public.current_role() = 'owner')
  with check (shop_id = public.current_shop_id() and public.current_role() = 'owner');

create policy app_settings_insert_owner_only on public.app_settings
  for insert to authenticated
  with check (shop_id = public.current_shop_id() and public.current_role() = 'owner');
