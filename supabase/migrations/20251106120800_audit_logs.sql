-- Generic edit trail for sensitive-but-mutable tables (customers,
-- transactions metadata, profiles, app_settings). payments and
-- interest_events don't need this — they're already an immutable trail
-- by construction (append-only, see those migrations).

create table public.audit_logs (
  id bigint generated always as identity primary key,
  shop_id uuid not null references public.shops (id) on delete restrict,
  table_name text not null,
  record_id uuid not null,
  action text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  changed_by uuid references public.profiles (id),
  changed_at timestamptz not null default now(),
  old_values jsonb,
  new_values jsonb
);

create index audit_logs_shop_changed_idx on public.audit_logs (shop_id, changed_at desc);
create index audit_logs_record_idx on public.audit_logs (table_name, record_id);

comment on table public.audit_logs is
  'Append-only edit trail. No UPDATE/DELETE policy is ever granted to normal users — see RLS migration.';

-- SECURITY DEFINER: a staff-role user has no direct INSERT grant on
-- audit_logs under RLS, but this trigger must still be able to write one
-- whenever they edit a customer/transaction row it's attached to.
create or replace function public.write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shop_id uuid;
  v_record_id uuid;
begin
  v_shop_id := coalesce(new.shop_id, old.shop_id);
  v_record_id := coalesce(new.id, old.id);

  insert into public.audit_logs (
    shop_id, table_name, record_id, action, changed_by, old_values, new_values
  ) values (
    v_shop_id,
    TG_TABLE_NAME,
    v_record_id,
    TG_OP,
    auth.uid(),
    case when TG_OP in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
    case when TG_OP in ('INSERT', 'UPDATE') then to_jsonb(new) else null end
  );

  return coalesce(new, old);
end;
$$;

comment on function public.write_audit_log() is
  'Generic AFTER trigger: writes one audit_logs row per INSERT/UPDATE/DELETE on the table it is attached to.';

create trigger customers_audit_trigger
  after insert or update or delete on public.customers
  for each row execute function public.write_audit_log();

create trigger transactions_audit_trigger
  after insert or update or delete on public.transactions
  for each row execute function public.write_audit_log();

create trigger profiles_audit_trigger
  after insert or update or delete on public.profiles
  for each row execute function public.write_audit_log();
