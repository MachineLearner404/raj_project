-- Secondary "unlock the idle-lock screen" PIN. This is explicitly NOT an
-- authentication mechanism — it never grants a session, never bypasses
-- Supabase Auth, and only matters while a real, already-authenticated
-- Supabase session is live (see docs note in the frontend idle-lock
-- component). Its only job is to let someone resume an unlocked device
-- without retyping their full password every time, with real rate
-- limiting enforced in the database, not the client.
--
-- The pin_credentials table has NO SELECT policy for anyone, including
-- the owning user — not even the hash is readable from the client. All
-- interaction goes through the functions below.

create table public.pin_credentials (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  pin_hash text not null,
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.pin_credentials enable row level security;
-- Deliberately no policies at all: RLS default-deny covers every
-- command for every role except the table owner (i.e. only the
-- SECURITY DEFINER functions below can touch this table).

create trigger pin_credentials_set_updated_at
  before update on public.pin_credentials
  for each row execute function public.set_updated_at();

comment on table public.pin_credentials is
  'Hashed secondary-unlock PINs. No RLS policy grants any access — reachable only through set_pin()/verify_pin()/clear_pin()/pin_is_configured().';

-- Tunable only here, server-side — never passed in from the client,
-- which is exactly what "no weak client-only gate" rules out.
-- 5 attempts, then a 15 minute lockout.

create or replace function public.set_pin(p_new_pin text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'set_pin: must be called by an authenticated user';
  end if;

  if p_new_pin is null or p_new_pin !~ '^[0-9]{4,6}$' then
    raise exception 'set_pin: PIN must be 4 to 6 digits';
  end if;

  insert into public.pin_credentials (profile_id, pin_hash)
  values (auth.uid(), crypt(p_new_pin, gen_salt('bf')))
  on conflict (profile_id) do update
    set pin_hash = excluded.pin_hash,
        failed_attempts = 0,
        locked_until = null;
end;
$$;

comment on function public.set_pin(text) is
  'Sets/replaces the caller''s own unlock PIN. Requires an existing authenticated session — never usable to create account access, only to configure a convenience unlock for a session that already exists. Hashed with bcrypt (pgcrypto); never stored in plaintext.';

create or replace function public.clear_pin()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'clear_pin: must be called by an authenticated user';
  end if;

  delete from public.pin_credentials where profile_id = auth.uid();
end;
$$;

comment on function public.clear_pin() is
  'Removes the caller''s own unlock PIN, if any.';

create or replace function public.pin_is_configured()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.pin_credentials where profile_id = auth.uid());
$$;

comment on function public.pin_is_configured() is
  'Whether the caller has a PIN set — safe to expose to the client (no hash, no attempt state).';

create or replace function public.verify_pin(p_candidate_pin text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cred public.pin_credentials;
  v_ok boolean;
begin
  if auth.uid() is null then
    raise exception 'verify_pin: must be called by an authenticated user';
  end if;

  select * into v_cred from public.pin_credentials where profile_id = auth.uid() for update;

  if v_cred.profile_id is null then
    raise exception 'verify_pin: no PIN is configured for this account';
  end if;

  if v_cred.locked_until is not null and v_cred.locked_until > now() then
    raise exception
      'verify_pin: too many incorrect attempts — try again after %', v_cred.locked_until;
  end if;

  v_ok := (v_cred.pin_hash = crypt(coalesce(p_candidate_pin, ''), v_cred.pin_hash));

  if v_ok then
    update public.pin_credentials
      set failed_attempts = 0, locked_until = null
      where profile_id = auth.uid();
  else
    update public.pin_credentials
      set failed_attempts = failed_attempts + 1,
          locked_until = case
            when failed_attempts + 1 >= 5 then now() + interval '15 minutes'
            else locked_until
          end
      where profile_id = auth.uid();
  end if;

  return v_ok;
end;
$$;

comment on function public.verify_pin(text) is
  'Checks a PIN against the caller''s own stored hash, with server-enforced rate limiting: locks out for 15 minutes after 5 consecutive wrong attempts. Only ever returns true/false or raises — a wrong attempt never reveals whether a PIN exists for someone else, since it only ever checks auth.uid()''s own row.';

revoke execute on function public.set_pin(text) from public;
revoke execute on function public.clear_pin() from public;
revoke execute on function public.pin_is_configured() from public;
revoke execute on function public.verify_pin(text) from public;

grant execute on function public.set_pin(text) to authenticated;
grant execute on function public.clear_pin() to authenticated;
grant execute on function public.pin_is_configured() to authenticated;
grant execute on function public.verify_pin(text) to authenticated;
