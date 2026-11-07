-- First-run shop setup fields, plus the one bootstrap path that lets a
-- brand-new authenticated user (no profile yet) create their own shop
-- and become its owner — self-service signup, without a service-role
-- step. See supabase/README.md's "Known gap: shop/first-owner bootstrap"
-- from Phase 2, which this migration closes.

alter table public.shops
  add column onboarding_completed_at timestamptz;

alter table public.app_settings
  add column timezone text not null default 'Asia/Kolkata',
  add column date_format text not null default 'DD/MM/YYYY'
    check (date_format in ('DD/MM/YYYY', 'MM/DD/YYYY', 'YYYY-MM-DD')),
  add column receipt_number_prefix text not null default 'RCPT'
    check (receipt_number_prefix ~ '^[A-Za-z0-9-]{1,10}$'),
  add column receipt_terms text;

comment on column public.shops.onboarding_completed_at is
  'Set once the first-run setup wizard (shop profile + app_settings) is completed. NULL means the frontend should show the onboarding flow.';

-- ---------------------------------------------------------------------
-- bootstrap_shop_owner(): the ONLY way a shop is ever created by a
-- normal (non-service-role) user. SECURITY DEFINER so it can insert
-- into shops/profiles/app_settings despite the caller having no rows
-- there yet — but it is NOT a free-for-all: a caller who already has a
-- profile (anywhere) is rejected, so an existing staff member cannot
-- spin up extra shops for themselves, and this can only ever be called
-- once per auth user.
-- ---------------------------------------------------------------------

create or replace function public.bootstrap_shop_owner(p_shop_name text)
returns public.shops
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shop public.shops;
begin
  if auth.uid() is null then
    raise exception 'bootstrap_shop_owner: must be called by an authenticated user';
  end if;

  if exists (select 1 from public.profiles where id = auth.uid()) then
    raise exception 'bootstrap_shop_owner: this account already belongs to a shop';
  end if;

  if p_shop_name is null or char_length(trim(p_shop_name)) = 0 then
    raise exception 'bootstrap_shop_owner: shop name is required';
  end if;

  insert into public.shops (name) values (trim(p_shop_name))
  returning * into v_shop;

  insert into public.profiles (id, shop_id, full_name, role)
  values (
    auth.uid(),
    v_shop.id,
    coalesce(nullif(trim((auth.jwt() -> 'user_metadata' ->> 'full_name')), ''), 'Shop Owner'),
    'owner'
  );

  insert into public.app_settings (shop_id) values (v_shop.id);

  return v_shop;
end;
$$;

comment on function public.bootstrap_shop_owner(text) is
  'Self-service shop signup: creates a shop + its first owner profile + default app_settings, atomically. Callable once per auth user — rejects anyone who already has a profile.';

revoke execute on function public.bootstrap_shop_owner(text) from public;
grant execute on function public.bootstrap_shop_owner(text) to authenticated;

-- ---------------------------------------------------------------------
-- Finalizes onboarding. Owner-only (same as any other shops/app_settings
-- write); separated into its own function purely so the frontend has one
-- clear "I'm done with setup" call instead of guessing which UPDATE to
-- fire last.
-- ---------------------------------------------------------------------

create or replace function public.complete_onboarding()
returns public.shops
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shop_id uuid := public.current_shop_id();
  v_shop public.shops;
begin
  if public.current_role() <> 'owner' then
    raise exception 'complete_onboarding: role % is not permitted to complete onboarding', public.current_role();
  end if;

  update public.shops
    set onboarding_completed_at = now()
    where id = v_shop_id
    returning * into v_shop;

  return v_shop;
end;
$$;

comment on function public.complete_onboarding() is
  'Marks the shop''s first-run setup wizard as done. owner only.';

revoke execute on function public.complete_onboarding() from public;
grant execute on function public.complete_onboarding() to authenticated;
