-- One row per shop. Separate from `shops` (which is identity/profile)
-- so business-rule configuration has its own lifecycle and audit trail.

create table public.app_settings (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null unique references public.shops (id) on delete cascade,

  default_interest_rate_percent_per_month numeric(5, 2) not null default 1.5
    check (default_interest_rate_percent_per_month > 0),
  default_currency text not null default 'INR',
  default_locale text not null default 'en-IN',
  -- See docs/04-interest-calculation.md — the business decision this
  -- setting controls (round up vs. round down a partial month) was still
  -- pending the owner's sign-off as of Phase 0; defaults to the
  -- revenue-protective option documented there.
  interest_rounding_policy text not null default 'round_up_partial_month'
    check (interest_rounding_policy in ('round_up_partial_month', 'round_down_partial_month')),
  grace_period_days integer not null default 15 check (grace_period_days >= 0),
  overdue_threshold_months integer not null default 6 check (overdue_threshold_months >= 0),

  updated_by uuid references public.profiles (id),
  updated_at timestamptz not null default now()
);

comment on table public.app_settings is
  'Per-shop business-rule configuration. One row per shop_id (unique).';

create trigger app_settings_set_updated_at
  before update on public.app_settings
  for each row execute function public.set_updated_at();

create trigger app_settings_audit_trigger
  after insert or update or delete on public.app_settings
  for each row execute function public.write_audit_log();
