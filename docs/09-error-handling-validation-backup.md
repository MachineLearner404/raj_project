# Error Handling, Validation, and Backup Considerations

## Validation — defense in depth, two layers, never just one

1. **Client-side (UX layer):** React Hook Form + Zod schemas in
   `src/lib/validators`, shared between forms wherever the same shape repeats
   (e.g., a phone-number validator used by both Add Customer and any future
   customer-edit form). Purpose: fast feedback, good UX — **not** the security or
   correctness boundary.
2. **Server-side (correctness/security layer):** Postgres `CHECK` constraints,
   `NOT NULL`, and explicit parameter validation inside the RPC functions
   (`create_loan`, `record_payment`, `close_loan` — see
   [02-database-schema-erd.md](./02-database-schema-erd.md)). This layer is what
   actually prevents bad data or an illegal state transition (e.g., overpaying a
   loan, recording a payment against a closed loan) — it must hold even if a bug
   or a malicious actor bypasses the UI entirely.

**Rule:** every validation rule described in
[05-pages-specification.md](./05-pages-specification.md) must exist at layer 2
before Phase 2 ships, even where layer 1 already covers it in the UI. A rule that
exists only in a React form is not actually enforced.

## Error handling — what the user sees

- **Form validation errors**: inline, per-field, from Zod/React Hook Form —
  specific ("Phone number must be 10 digits"), never generic ("Invalid input").
- **Mutation failures** (Phase 2+ — a `record_payment()` call rejected by the
  server, e.g., overpayment or a network drop): surfaced via toast
  (`sonner`, see [06-components-specification.md](./06-components-specification.md))
  with the specific reason returned by the RPC function, not a raw stack
  trace/error object. The form stays filled in (nothing the user typed is lost) so
  they can correct and resubmit.
- **Fetch/query failures** (Phase 2+ — a page's data fails to load): the shared
  `ErrorState` component, with a "Retry" action wired to the TanStack Query
  `refetch`. Never a blank page or a silent console-only failure.
- **Unexpected/unhandled errors**: a top-level React error boundary (Phase 2+
  addition — not yet built) catches render-time crashes and shows a generic "Something
  went wrong" screen with a reload action, rather than a blank white page — this is
  explicitly called out because a financial app going blank mid-transaction is
  worse than most apps going blank.

## Concurrency correctness (multiple devices, one database)

This is the sharpest edge case in the whole system, called out separately from
general "error handling" because it is not really an error — both devices succeed,
but naive logic could still corrupt the balance.

- **Never** apply a payment as a plain client-read-then-client-write (`read
  current_outstanding_principal`, compute new value in JS, `UPDATE` it) — two
  devices doing this within the same second can both read the same stale balance
  and both write an incorrect result, with neither erroring.
- **Always** go through the `record_payment()`/`close_loan()` Postgres functions,
  which read and update the loan row inside a single transaction — Postgres's own
  row-level locking serializes concurrent calls against the same `loan_id`, so the
  second call to complete always sees the first call's already-applied result.
- TanStack Query's cache is **not** the source of truth for anything financial —
  it is invalidated/refetched after a mutation and kept fresh via Realtime
  subscriptions (see [01-architecture.md](./01-architecture.md)), but the database
  is always re-asked before another mutation is attempted, never computed from a
  possibly-stale client cache.
- Mutations that move money are **never optimistic** (no "assume success and
  update the UI immediately, roll back if it fails" pattern) — the UI waits for the
  server's confirmed new balance before showing it as applied. A brief spinner is
  the correct cost of correctness here.

## Backup strategy

## Multi-shop ownership and recovery

An authenticated person has one `profiles` row and can have many
`shop_memberships` rows. Every ordinary request operates in exactly one
server-selected `active_shop_id`; `current_shop_id()` and `current_role()`
read that selection and every RLS policy/RPC continues to use those server-side
helpers. The browser's shop selector only calls `switch_active_shop()`; it
cannot name a shop without an active membership.

This enables a single owner account to retain access to a live shop while also
owning a separately restored shop. Roles are per shop. A staff role in one shop
does not grant any role in another. Recovery must create a new shop and owner
membership, never update the live shop or overwrite its ledger.

- **Automated**: if the chosen Supabase plan includes point-in-time or daily
  backups, that is the baseline safety net — confirm which tier is in use and what
  retention it provides (this is a plan/billing decision, not a code decision, and
  should be confirmed before go-live).
- **Manual, shop-triggered**: the Settings & Backup page's "Export full backup"
  action (Phase 3+, per [05-pages-specification.md](./05-pages-specification.md))
  produces a dated export (customers, loans, items, payments, ledger — the full
  business-data set, not just one table) via ExcelJS, optionally uploaded to
  Storage and tracked in `backup_jobs`.
- **Off-platform copy**: recommend the owner periodically downloads that export
  rather than relying solely on a copy that lives inside the same Supabase
  project — see the security checklist's note on this
  ([08-security-threat-checklist.md](./08-security-threat-checklist.md)).
- **Restore drill**: a backup that has never been restored is unverified. Recommend
  a periodic (e.g., quarterly) test restore into a scratch/staging Supabase project
  — this is a process recommendation for the business, not something the app can
  enforce in code, but it belongs in this document because an untested backup is a
  false sense of security.
- **Scheduling note**: there is no custom server to run a cron job on (see
  [01-architecture.md](./01-architecture.md)'s "no custom backend" design). Scheduled
  (as opposed to manually-triggered) backups would need Supabase's own scheduling
  primitive (e.g., `pg_cron` + an Edge Function) — flagged as a Phase 3+
  enhancement, not assumed to exist by default.

## What "tested" means in this project (so status reports stay honest)

- A feature is only described as "tested" once an actual Vitest unit test or
  Playwright e2e test has been written **and run**, with the result reported
  truthfully (pass/fail), per the standing instruction for this project. Phase 0
  documentation itself has no code to test; Phase 1 tooling claims in the earlier
  completion report were all backed by commands that were actually executed
  (`tsc -b`, `npm run lint`, `npm run test`, `npm run build`, `npm run e2e`), not
  assumed.
- The worked example table in
  [04-interest-calculation.md](./04-interest-calculation.md) is written
  specifically so it can become literal unit test fixtures in Phase 2/3 — "the
  interest calculation is tested" will mean that table passes as assertions, not
  that the function merely exists.
