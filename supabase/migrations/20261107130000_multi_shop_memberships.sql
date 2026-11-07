-- A person may hold a distinct role in more than one shop.  `profiles`
-- remains the 1:1 person record; authorization is derived exclusively from
-- the active membership below, never from browser state or JWT metadata.

alter table public.profiles add column active_shop_id uuid references public.shops(id);
update public.profiles set active_shop_id = shop_id where active_shop_id is null;

create or replace function public.profiles_default_active_shop()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.active_shop_id is null then new.active_shop_id := new.shop_id; end if;
  return new;
end;
$$;
create trigger profiles_default_active_shop_trigger before insert on public.profiles for each row execute function public.profiles_default_active_shop();

alter table public.profiles alter column active_shop_id set not null;

create table public.shop_memberships (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('owner', 'manager', 'staff')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, user_id)
);
create index shop_memberships_user_active_idx on public.shop_memberships(user_id, is_active);
create index shop_memberships_shop_active_idx on public.shop_memberships(shop_id, is_active);
create trigger shop_memberships_set_updated_at before update on public.shop_memberships for each row execute function public.set_updated_at();

-- Backward-compatible provisioning: existing staff creation still inserts a
-- profile, and the membership row is created in the same transaction.
create or replace function public.profiles_create_default_membership()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.shop_memberships(shop_id, user_id, role, is_active)
  values (new.shop_id, new.id, new.role, new.is_active)
  on conflict (shop_id, user_id) do nothing;
  return new;
end;
$$;
create trigger profiles_create_default_membership_trigger after insert on public.profiles for each row execute function public.profiles_create_default_membership();

insert into public.shop_memberships (shop_id, user_id, role, is_active, created_at, updated_at)
select shop_id, id, role, is_active, created_at, updated_at from public.profiles
on conflict (shop_id, user_id) do nothing;

-- The old `profiles.shop_id` and `profiles.role` remain a legacy/default
-- record during the migration.  All new authorization reads membership.
create or replace function public.current_shop_id()
returns uuid language sql stable security definer set search_path = public as $$
  select p.active_shop_id from public.profiles p where p.id = auth.uid();
$$;

create or replace function public.current_role()
returns text language sql stable security definer set search_path = public as $$
  select m.role from public.shop_memberships m
  where m.user_id = auth.uid() and m.shop_id = public.current_shop_id() and m.is_active;
$$;

create or replace function public.switch_active_shop(p_shop_id uuid)
returns public.shops language plpgsql security definer set search_path = public as $$
declare v_shop public.shops;
begin
  if auth.uid() is null then raise exception 'switch_active_shop: authentication required'; end if;
  if not exists (select 1 from public.shop_memberships m where m.user_id = auth.uid() and m.shop_id = p_shop_id and m.is_active) then
    raise exception 'switch_active_shop: you are not an active member of this shop';
  end if;
  update public.profiles set active_shop_id = p_shop_id where id = auth.uid();
  select * into v_shop from public.shops where id = p_shop_id;
  return v_shop;
end;
$$;

alter table public.shop_memberships enable row level security;
create policy memberships_select_own on public.shop_memberships for select to authenticated using (user_id = (select auth.uid()));
create policy memberships_manage_owner on public.shop_memberships for all to authenticated
  using (shop_id = public.current_shop_id() and public.current_role() = 'owner')
  with check (shop_id = public.current_shop_id() and public.current_role() = 'owner');

drop policy shops_select_own on public.shops;
create policy shops_select_membership on public.shops for select to authenticated
  using (exists (select 1 from public.shop_memberships m where m.shop_id = shops.id and m.user_id = (select auth.uid()) and m.is_active));

drop policy profiles_select_same_shop on public.profiles;
create policy profiles_select_self_or_active_shop on public.profiles for select to authenticated
  using (id = (select auth.uid()) or exists (select 1 from public.shop_memberships m where m.user_id = profiles.id and m.shop_id = public.current_shop_id() and m.is_active));

-- An existing user may now bootstrap an additional shop. A newly-created
-- shop becomes their active shop only after this atomic operation succeeds.
create or replace function public.bootstrap_shop_owner(p_shop_name text)
returns public.shops language plpgsql security definer set search_path = public as $$
declare v_shop public.shops; v_name text := trim(p_shop_name);
begin
  if auth.uid() is null then raise exception 'bootstrap_shop_owner: authentication required'; end if;
  if v_name is null or char_length(v_name) = 0 then raise exception 'bootstrap_shop_owner: shop name is required'; end if;
  insert into public.shops(name) values(v_name) returning * into v_shop;
  if not exists (select 1 from public.profiles where id = auth.uid()) then
    insert into public.profiles(id, shop_id, active_shop_id, full_name, role)
    values(auth.uid(), v_shop.id, v_shop.id, coalesce(nullif(auth.jwt()->>'email',''), 'Owner'), 'owner');
  end if;
  insert into public.shop_memberships(shop_id, user_id, role) values(v_shop.id, auth.uid(), 'owner')
  on conflict (shop_id, user_id) do update set role = 'owner', is_active = true;
  update public.profiles set active_shop_id = v_shop.id where id = auth.uid();
  insert into public.app_settings(shop_id, updated_by) values(v_shop.id, auth.uid());
  return v_shop;
end;
$$;

revoke execute on function public.switch_active_shop(uuid) from public;
grant execute on function public.switch_active_shop(uuid) to authenticated;
revoke execute on function public.bootstrap_shop_owner(text) from public;
grant execute on function public.bootstrap_shop_owner(text) to authenticated;

comment on table public.shop_memberships is 'Authoritative per-shop authorization. A user can have memberships in many shops; active_shop_id selects exactly one for RLS-scoped work.';
