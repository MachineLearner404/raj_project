# Documentation Index

Phase 0 documentation for the Jewellery Loan & Transaction Management App. Read in
this order; later documents reference earlier ones.

1. [00-repo-audit.md](./00-repo-audit.md) — Repository audit, folder structure, dependency audit.
2. [01-architecture.md](./01-architecture.md) — System architecture and data flow.
3. [02-database-schema-erd.md](./02-database-schema-erd.md) — Database schema, ERD, RLS policy shape, key functions.
4. [03-business-workflows.md](./03-business-workflows.md) — Customer management, deposit/valuation, loan creation, repayments, release, overdue/auction, transaction history.
5. [04-interest-calculation.md](./04-interest-calculation.md) — Option B algorithm in full, worked examples, **one open decision needing your sign-off**.
6. [05-pages-specification.md](./05-pages-specification.md) — All 9 pages: purpose, data, controls, validation, states, access.
7. [06-components-specification.md](./06-components-specification.md) — Reusable layout and shared components, target behavior.
8. [07-environment-variables.md](./07-environment-variables.md) — Full env var reference and secrets-handling rules.
9. [08-security-threat-checklist.md](./08-security-threat-checklist.md) — Security checklist for personal data and financial records.
10. [09-error-handling-validation-backup.md](./09-error-handling-validation-backup.md) — Validation layering, error handling, concurrency correctness, backup strategy.
11. [10-phase-plan.md](./10-phase-plan.md) — Phase-by-phase scope, risks, acceptance criteria (Phase 0 through Phase 4).

## Open questions requiring your decision before later phases proceed

- **Interest rounding policy default** (round up vs. round down a partial month) —
  [04-interest-calculation.md](./04-interest-calculation.md).
- **Dashboard/Active Transactions financial-figure role-gating** for `staff` role —
  [05-pages-specification.md](./05-pages-specification.md).
- **Customer-edit permissions** (who may edit an existing customer record) —
  [03-business-workflows.md](./03-business-workflows.md), Workflow 1.
- **ID-proof-number encryption** (masking alone vs. application-level encryption) —
  [08-security-threat-checklist.md](./08-security-threat-checklist.md).
- **Settings page role split** (manager read-only vs. no access to shop profile) —
  [05-pages-specification.md](./05-pages-specification.md), page 9.
- **Regulatory confirmation** (state Pawnbrokers Act / RBI NBFC applicability) —
  [08-security-threat-checklist.md](./08-security-threat-checklist.md).

Nothing in `src/`, `supabase/`, `package.json`, or any other Phase 1
tooling/configuration file was modified while writing this documentation.
