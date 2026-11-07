# Database — migrations, local setup, testing, seeding

This directory is the source of truth for the schema. Nothing here has
been applied to a real Supabase project yet — see "Status" below.

## Layout

```
supabase/
├── migrations/     versioned SQL files, applied in filename order
├── tests/          RLS/constraint tests, run on a scratch local Postgres
│   ├── _local_pg_stub.sql           test-only auth/storage stand-in
│   ├── rls_and_constraints.test.sql the actual assertions
│   └── run.sh                       one-command test runner
└── seed/
    └── seed-demo.ts  synthetic demo data + an end-to-end smoke test
```

## Status (read before assuming anything below is "done")

- **Migrations**: written, and applied cleanly to a real local Postgres
  15 instance during development — see "Testing" below for exactly how.
  **Never applied to an actual Supabase project**, because none is
  provisioned yet (`.env` holds only placeholders, per
  [docs/07-environment-variables.md](../docs/07-environment-variables.md)).
- **RLS policies**: 22 assertions actually executed and passing against
  the real migration SQL (shop isolation, role gating, append-only
  enforcement, status-transition control, Storage path scoping — see
  `tests/rls_and_constraints.test.sql` for the full list). This used a
  hand-built stand-in for Supabase's `auth`/`storage` schemas on plain
  Postgres — **not** the real GoTrue/PostgREST/Storage API stack, since
  this environment has no Docker and the Supabase CLI's local stack
  requires it. Re-run these tests (or an equivalent) against a real
  Supabase project before calling this production-ready — see "What
  still needs a real Supabase project" below.
- **Seed script**: written, typechecks, and its safety guard was smoke
  tested — **not executed end-to-end**, since that requires a real
  project's URL + keys.

## Prerequisites

- A Supabase project (free tier is fine to start). Get its URL, anon
  key, and service-role key from Dashboard → Project Settings → API.
- [Supabase CLI](https://supabase.com/docs/guides/cli) for applying
  migrations to that project (`npm install -g supabase` is explicitly
  unsupported by the CLI itself — use `brew install supabase/tap/supabase`
  or see their docs for your platform).
- Copy `.env.example` to `.env` and fill in the real values. **Never
  commit `.env`** — it's git-ignored.

## Applying migrations to a real Supabase project

```bash
supabase login
supabase link --project-ref <your-project-ref>   # from .env's SUPABASE_PROJECT_REF
supabase db push                                  # applies supabase/migrations/*.sql in order
```

`supabase db push` applies each file in `supabase/migrations/` exactly
as committed — nothing in this repo modifies them for local-only
testing (the `tests/_local_pg_stub.sql` stand-in lives entirely outside
`migrations/` for exactly this reason: it must never ship to a real
project).

## Generating real TypeScript types (replacing the hand-maintained ones)

Once migrations are applied to a real project:

```bash
supabase gen types typescript --project-id <your-project-ref> > src/lib/supabase/database.types.ts
```

This should be a close-to-drop-in replacement for the hand-maintained
file — see that file's header comment for the few places it was written
to diverge intentionally (trigger-filled columns, RPC-only tables).
Diff the output against the current file and reconcile before replacing
it outright.

## Testing (works today, no real project needed)

Requires a local Postgres server (not Docker, not the Supabase CLI's
local stack — see `tests/_local_pg_stub.sql`'s header for why):

```bash
# macOS, if you don't already have one running:
brew install postgresql@15
brew services start postgresql@15

npm run db:test
```

This creates a scratch database (`jewellery_loan_rls_test`), applies the
test-only auth/storage stub, applies all 13 real migrations unmodified,
runs 22 real RLS/constraint assertions, prints PASS/FAIL for each, and
drops the scratch database on exit (including on failure — see the
script's `trap cleanup EXIT`). It never touches any other database on
your machine.

### What this test suite actually covers

Shop-scoped SELECT isolation · role-gated INSERT/UPDATE on customers ·
server-side mobile normalization · mobile is NOT unique · per-shop
unique/sequential `customer_code` · cross-shop invisibility (not just
"forbidden" — the row doesn't exist as far as another shop can tell) ·
direct writes to `transactions` blocked (RPC-only) · `create_transaction()`
role gating and atomic item attachment · `record_payment()` balance
math, status transitions, and full-closure amount validation · the
status-transition trigger rejecting an illegal transition even via a
direct UPDATE · append-only enforcement on `payments` · automatic
`audit_logs` capture and its own owner/manager-only read policy ·
Storage path-scoped policies on the `customer-photos` bucket.

### What still needs a real Supabase project

- The actual GoTrue auth flow (sign-up, sessions, JWT issuance) — the
  local stub only replicates `auth.uid()` reading a GUC, not real auth.
- The actual Storage API's behavior (signed URLs, upload size/MIME
  enforcement) — the local stub only replicates the `storage.objects`
  RLS policy evaluation, not the Storage service itself.
- Supabase's own managed backups/point-in-time recovery.
- Performance under real concurrent load (the row-locking design in
  `record_payment()` is reasoned through and the lock itself is real
  Postgres `SELECT ... FOR UPDATE`, but it hasn't been load-tested).

**Do not describe RLS or Storage policies as "secure" without re-running
equivalent checks against the real project** — this local suite is
strong evidence the logic is right, not a substitute for testing the
real stack.

## Seeding demo data

```bash
ALLOW_SEED=true npm run seed:demo
```

Creates one demo shop, three demo staff accounts (owner/manager/staff,
password `DemoPass!12345` — printed at the end of the script too), two
synthetic customers, and two transactions (one left active, one
partially repaid) — all created through the real `create_transaction()`
/ `record_payment()` RPCs under real signed-in sessions, not raw
inserts, so a successful run is also an end-to-end smoke test.

Every name/phone/ID number in the seed data is obviously synthetic
(`"Seed Customer Alpha"`, `9000000001`, etc.) — see
`seed/seed-demo.ts`'s header. **Run this only against a local/dev/staging
project.** The `ALLOW_SEED=true` gate exists specifically so this can
never run by accident against whatever `.env` happens to point at.

## Authentication and first-run setup

The browser uses only `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
The Supabase client persists and refreshes the user session; never expose
`SUPABASE_SERVICE_ROLE_KEY` to the browser.

In **Authentication → URL Configuration**, set the production Site URL and
allow these redirect URLs (with the equivalent local development URL):

```
https://your-app.example/reset-password
http://localhost:5173/reset-password
```

Enable email/password sign-in. Configure a production SMTP provider before
relying on password-reset delivery, and keep email confirmation aligned with
your staff-account provisioning process. The first signed-in user without a
profile is sent to onboarding; `bootstrap_shop_owner()` atomically creates
their shop, owner profile, and default settings. It is callable only once for
an authenticated user. Existing staff must never use it to create a second
shop.

RLS and SECURITY DEFINER RPC authorization are the security boundary. The UI
hides owner-only settings as a convenience only. The optional idle lock uses a
database-verified bcrypt PIN with a server-enforced five-attempt / 15-minute
lockout; it cannot create a session or bypass Supabase Auth.
