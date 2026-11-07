# Security Threat Checklist

Scope: this app handles **personal data** (customer name, phone, address, government
ID numbers, photos) and **financial records** (loan principal, interest, payments —
real money). Both categories demand more care than a typical internal tool. This
checklist is organized by threat category; each item states the control and where
it is (or will be) implemented.

**This is a checklist to verify against at each phase gate, not a one-time task.**
Re-review it at the end of Phase 2 (once Supabase/auth/RLS are real) and again
before go-live.

## Authentication

- [ ] Staff sign in via Supabase Auth (email/password or magic link) — no shared
      "shop login"; every action is attributable to an individual `app_users` row
      (`created_by`, `received_by`, `changed_by` columns throughout the schema
      exist specifically for this).
- [ ] Owner account uses a strong, unique password; recommend enabling Supabase's
      MFA option for the owner role at minimum once available in the project tier.
- [ ] Session timeout / auto sign-out after a period of inactivity on shared shop
      devices (tablets at the counter are a realistic loss/theft vector) —
      Phase 2+ implementation item, not yet built.
- [ ] Failed-login throttling relies on Supabase Auth's built-in protections; no
      custom brute-force logic is being hand-rolled (avoid reinventing this badly).

## Authorization

- [ ] **Row Level Security is the real boundary**, not client-side role checks —
      every table in [02-database-schema-erd.md](./02-database-schema-erd.md) has
      RLS enabled with policies keyed to `app_users.role`. Client-side
      role-gating (hiding a button) is a UX convenience, never the security
      control.
- [ ] `loan_ledger_entries` and `audit_log` have no `UPDATE`/`DELETE` policy for
      **any** role, enforced at the database level — history cannot be altered
      even by a compromised owner account, only appended to.
- [ ] Money-moving actions (`create_loan`, `record_payment`, `close_loan`) are
      Postgres functions with their own role checks inside — never exposed as
      unrestricted direct table writes from the client.
- [ ] `closure_type = 'auctioned'`/`'written_off'` is owner-only (see Workflow 7 in
      [03-business-workflows.md](./03-business-workflows.md)) — a legally sensitive
      action requires the highest-privilege role.

## Data at rest

- [ ] Supabase Postgres and Storage are encrypted at rest by the platform — no
      additional app-level encryption is planned for most fields, **except**:
- [ ] ID proof numbers (`customers.id_proof_number`) are a specific concern —
      recommend **masking in all list/table views** (show last 4 digits only,
      e.g., `XXXX-XXXX-4521`, matching the demo data convention already used in
      `src/data/demo-data.ts`) and only revealing the full number on an explicit
      "reveal" action on the customer detail view, logged to `audit_log` when
      revealed. **Decision needed**: whether to go further and encrypt this column
      application-side (e.g., pgsodium/pgcrypto) — flagged for your input before
      Phase 2, as it adds real key-management complexity for a shop-scale app.
- [ ] Item/ID photos in Storage use private buckets with RLS-equivalent Storage
      policies (not public URLs) — signed URLs with short expiry for display.

## Data in transit

- [ ] All traffic to Supabase is HTTPS/TLS by default (Supabase does not offer
      unencrypted endpoints) — no action needed, just confirm no code ever
      constructs an `http://` Supabase URL.
- [ ] No sensitive data (customer PII, amounts) is ever logged to third-party
      analytics/monitoring in plaintext — if `VITE_SENTRY_DSN` (Phase 3+) is
      adopted, error reports must be scrubbed of PII before this is enabled.

## Input validation & injection

- [ ] All form input validated client-side via Zod schemas
      (`src/lib/validators`), **and** re-validated at the database boundary (RLS
      `CHECK` constraints / Postgres function parameter checks) — client
      validation is a UX convenience, never the only gate (same principle as
      authorization above).
- [ ] No raw SQL string concatenation anywhere — all Postgres access goes through
      the Supabase client (parameterized) or named RPC functions with typed
      parameters; this structurally rules out classic SQL injection.
- [ ] File uploads (ID photos, item photos) are restricted by type/size at the
      client and should be re-validated by a Storage policy/Edge Function in
      Phase 2+ (a malicious file renamed with an image extension is a real vector
      otherwise).

## Client-side (XSS/CSRF)

- [ ] React's default JSX escaping is relied on; `dangerouslySetInnerHTML` is not
      used anywhere in this codebase — if a future feature seems to need it (e.g.,
      rendering rich text), that is a flag to re-examine, not a default tool.
- [ ] CSRF is low-risk by construction here: the Supabase client authenticates via
      a bearer JWT in the `Authorization` header (not an ambient cookie), so
      classic CSRF (which relies on browsers auto-attaching cookies) does not
      apply the same way it would to a cookie-session server app. No action beyond
      keeping this auth pattern.
- [ ] A Content-Security-Policy header is recommended once a hosting platform is
      chosen (Phase 2+ deployment task) — restrict script sources to self +
      Supabase's domains.

## Secrets management

- [ ] See [07-environment-variables.md](./07-environment-variables.md)'s
      verification checklist in full — `service_role` key never in the browser
      bundle, `.env` never committed, placeholders only in `.env.example`.
- [ ] Production secrets live in the hosting platform's secret store / CI secret
      store only.

## Audit & accountability

- [ ] Every financial state change is attributable (`created_by`, `received_by`)
      and append-only (`loan_ledger_entries`) — see
      [02-database-schema-erd.md](./02-database-schema-erd.md) design principle 1.
- [ ] Non-ledger sensitive edits (customer detail changes, settings changes) write
      to `audit_log` with old/new values — Phase 2+ implementation via Postgres
      triggers, not optional application-layer logging that can be skipped.

## Backup & recovery

- [ ] See [09-error-handling-validation-backup.md](./09-error-handling-validation-backup.md)
      for the full backup strategy — summarized here as a security concern because
      an un-backed-up financial ledger is itself a risk (ransomware, accidental
      deletion, Supabase account issue).
- [ ] Recommend an **off-platform** copy of backups (not solely inside the same
      Supabase project/Storage bucket) — a backup that lives next to what it's
      backing up does not protect against account-level incidents.

## Physical/operational (shop-specific, often overlooked)

- [ ] Counter devices face customers — masked ID numbers (above) also protect
      against a customer or bystander reading another customer's full ID number
      off the screen.
- [ ] Device loss/theft: session timeout (above) plus the ability for the owner to
      revoke a specific device's session from Supabase Auth if a tablet is lost —
      document this as a runbook step for Phase 2+, not just a technical capability
      nobody knows how to invoke.

## Regulatory note (not legal advice)

Pawnbroking/gold-loan businesses in India may be subject to state-level
Pawnbrokers Acts and, depending on business structure and loan sizes, RBI
regulations applicable to NBFCs. This document is a software security checklist,
not legal guidance — **recommend the shop owner confirm applicable compliance
requirements (KYC retention periods, interest rate caps if any, auction notice
requirements) with a local advisor**, since some of those requirements (e.g., a
mandated minimum notice period before auction) could affect the
`overdue_threshold_months` default and the auction workflow in
[03-business-workflows.md](./03-business-workflows.md) Workflow 7.
