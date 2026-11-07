# Phase Implementation Plan, Risks & Acceptance Criteria

## Phase 0 — Documentation (this phase)

**Scope:** repository audit, architecture, database schema/ERD, business
workflows, interest-calculation algorithm, page specs, component specs, env vars,
security checklist, error/validation/backup considerations, this plan.

**Deliverables:** all files listed in [README.md](./README.md).

**Risks:**
- Documenting a schema and algorithm before any code exists means design mistakes
  are cheap to fix now and expensive later — the main risk is **not** spending
  enough review time here before Phase 2 starts building against it.
- One business rule genuinely needs your decision, not an assumption:
  `interest_rounding_policy` default (round up vs. round down on a partial month) —
  see [04-interest-calculation.md](./04-interest-calculation.md). Proceeding into
  Phase 2 without this answered means building against an assumed default that may
  need to change.

**Acceptance criteria:**
- [ ] You have reviewed and approved (or requested changes to) every document in
      `docs/`.
- [ ] The `interest_rounding_policy` default question is answered.
- [ ] Any other open questions flagged inline across these docs (customer-edit
      permissions, dashboard financial-figure role-gating, ID-proof-number
      encryption) are answered or explicitly deferred with your sign-off.

## Phase 1 — Project foundation & app shell

**Scope (from your Phase 1 instruction):** React + TypeScript + Vite, Tailwind,
shadcn/ui, Lucide, routing, linting, formatting, Vitest, Playwright; the warm
white / champagne-gold / charcoal design system; app shell with sidebar
(desktop) + compact/mobile nav; the 9 routed pages as demo-data-backed
placeholders; the reusable components in
[06-components-specification.md](./06-components-specification.md); realistic
demo data, clearly labeled; no real persistence.

**Status at start of this phase (verified by inspection, not assumed):**
tooling (Vite/TS/Tailwind/shadcn/Lucide/oxlint/Vitest/Playwright) is installed and
verified working (`tsc -b`, `npm run lint`, `npm run test`, `npm run build` all
pass). Routing, the app shell wiring in `App.tsx`, all 9 page components, and most
shared components (`PageHeader`, `MetricCard`, `DataTable`, `StatusBadge`,
`SearchBar`, `EmptyState`, `LoadingState`, `ErrorState`, `ConfirmDialog`) do **not**
exist yet — only `Sidebar`, `MobileNav`, `Topbar`, `AppShell`, and
`DemoModeBanner` have been written, and none are wired into `App.tsx` yet. Demo
data (`src/data/demo-data.ts`) and domain types exist and are ready to be consumed
by pages once built.

**Risks:**
- Building 9 pages + ~9 shared components is a large surface for one phase —
  risk of inconsistent patterns if components are built ad hoc per page instead of
  building the shared components first and having pages consume them (the build
  order implied by [06-components-specification.md](./06-components-specification.md)
  matters).
- "No fake buttons" is an easy rule to violate accidentally (a disabled button with
  no visible explanation reads as broken, not as "coming later") — every disabled
  control needs a tooltip/caption, as specified per-page in
  [05-pages-specification.md](./05-pages-specification.md).
- The `shadcn` CLI previously mis-resolved the `@/*` path alias once before being
  fixed (documented in [00-repo-audit.md](./00-repo-audit.md)'s dependency section)
  — any further `npx shadcn add` calls should have their output location verified,
  not assumed.

**Acceptance criteria:**
- [ ] `npm run lint`, `npm run build`, `npx tsc -b`, `npm run test`, and `npm run
      e2e` all pass, re-run and reported truthfully (not claimed without running).
- [ ] All 9 routes resolve and render the correct page (manually verified in a
      running `npm run dev` session, screenshotted/described, not just "should
      work").
- [ ] Every shared component in
      [06-components-specification.md](./06-components-specification.md) exists,
      is used by at least one page, and has at least one Vitest test.
- [ ] Every control on every page matches its Phase 1 behavior as specified in
      [05-pages-specification.md](./05-pages-specification.md) — working demo
      interaction, working navigation, or visibly disabled with an explanation.
- [ ] Responsive check: sidebar collapses to the `MobileNav` sheet below the `md`
      breakpoint; no horizontal scroll/clipping on a small viewport, verified at
      at least one mobile width.
- [ ] No real Supabase calls exist anywhere in the Phase 1 code path — grep for
      `supabase.` outside `src/lib/supabase/client.ts` itself returns nothing used
      by a page yet.
- [ ] The `package.json` dependency-placement cleanup noted in
      [00-repo-audit.md](./00-repo-audit.md) (`shadcn` CLI etc. into
      `devDependencies`) is done.

## Phase 2 — Supabase schema, auth, and core CRUD

**Scope:** apply the schema from
[02-database-schema-erd.md](./02-database-schema-erd.md) as versioned migrations;
implement RLS policies per the role matrix; implement Supabase Auth sign-in; wire
Customer and Loan CRUD (Workflows 1–3) to real data, replacing demo data page by
page; implement `create_loan()` and the basic (non-interest-aware) parts of
`record_payment()`.

**Risks:**
- Migrating a page from demo data to live Supabase queries without first having
  layer-2 (server-side) validation in place (see
  [09-error-handling-validation-backup.md](./09-error-handling-validation-backup.md))
  would ship a page that *looks* done but is not actually safe against bad input
  or concurrent writes — sequencing matters: RLS + functions before UI wiring, not
  after.
- Supabase project environment separation (dev/staging/prod — see
  [01-architecture.md](./01-architecture.md)) must be set up **before** any real
  customer data is entered anywhere, or there is no safe place to test against.

**Acceptance criteria:**
- [ ] Migrations in `supabase/migrations/` reproduce the schema in
      [02-database-schema-erd.md](./02-database-schema-erd.md) exactly, reviewable
      diff against this doc.
- [ ] RLS policies tested per role (a `staff`-role test user genuinely cannot
      perform an owner-only action, verified, not assumed).
- [ ] Customer and Loan creation work end-to-end against a real Supabase project
      with a real signed-in user.
- [ ] The concurrency scenario in
      [09-error-handling-validation-backup.md](./09-error-handling-validation-backup.md)
      (two near-simultaneous payment calls on the same loan) is actually tested,
      not just designed around.

## Phase 3 — Interest engine, overdue handling, reports/exports

**Scope:** implement the full algorithm from
[04-interest-calculation.md](./04-interest-calculation.md) as both a tested
`src/lib/calculations` function and the equivalent Postgres function logic inside
`record_payment()`/`close_loan()`; `recompute_overdue_status()`; PDF receipts
(jsPDF); Excel/CSV exports (ExcelJS/PapaParse) on the Reports page; backup export
feature on Settings & Backup.

**Risks:**
- This phase has the highest correctness risk in the project — a wrong interest
  figure is a direct financial/trust problem with a real customer, not a cosmetic
  bug. The worked-example table in
  [04-interest-calculation.md](./04-interest-calculation.md) exists specifically to
  make this testable precisely, and should gate this phase's acceptance harder than
  any other phase's.

**Acceptance criteria:**
- [ ] The worked-example table in
      [04-interest-calculation.md](./04-interest-calculation.md) passes as literal
      unit test assertions.
- [ ] The client-side and database-side interest implementations agree on the same
      test fixtures (no drift between the two layers).
- [ ] A full repayment/closure cycle, including PDF receipt generation, is
      exercised end-to-end against a real (staging) Supabase project.

## Phase 4 — Realtime polish, role management, hardening

**Scope:** Realtime subscriptions live across the Dashboard/Active
Transactions/Customer detail views; an owner-facing staff/role management UI;
session timeout + device sign-out; the full security checklist in
[08-security-threat-checklist.md](./08-security-threat-checklist.md) re-verified;
a restore drill performed at least once.

**Acceptance criteria:**
- [ ] Two browser sessions on the same loan demonstrably see each other's changes
      without a manual refresh.
- [ ] Every unchecked item remaining in
      [08-security-threat-checklist.md](./08-security-threat-checklist.md) is
      either checked off or explicitly deferred with your sign-off and a reason.
- [ ] A backup has been restored into a scratch project at least once, successfully.

## Cross-phase risks worth naming once, up front

- **Regulatory uncertainty** (compliance note in
  [08-security-threat-checklist.md](./08-security-threat-checklist.md)) could
  change `overdue_threshold_months`, KYC retention requirements, or auction notice
  rules after Phase 3 is already built around assumed defaults — recommend
  resolving this with a local advisor before Phase 3, not after.
- **Open business-rule questions** flagged across these documents
  (`interest_rounding_policy` default, dashboard figure role-gating, customer-edit
  permissions, ID-proof-number encryption) compound if left unanswered — each is
  cheap to answer now and progressively more disruptive to change the later it's
  discovered.
- **No custom backend** (by design) means anything that would traditionally be "a
  cron job on the server" (scheduled overdue recomputation, scheduled backups) must
  explicitly use a Supabase-native scheduling mechanism — a plan that quietly
  assumes a server that doesn't exist is a risk to catch at Phase 3 design time,
  not at Phase 3 ship time.
