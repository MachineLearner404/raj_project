# Pages Specification

Specifies purpose, data, controls, validation, and states for all 9 planned pages.
"Phase 1 behavior" describes what the page does when wired only to demo data (no
Supabase) per your Phase 1 instruction; "Phase 2+ behavior" describes the real,
database-backed behavior once Supabase is connected. Every control is either (a)
fully functional in Phase 1 against demo/local state, (b) a working navigation link,
or (c) visibly disabled with an explanation — nothing is a silently fake button.

---

## 1. Dashboard (`/`)

**Purpose:** at-a-glance shop health for the owner/manager when they open the app.

**Data shown:** metric cards (active loan count, principal outstanding, interest
accrued this month, overdue count — see `DashboardMetric` type); a status breakdown
chart (Recharts); a recent-activity table (latest payments).

**Phase 1 behavior:** all data from `src/data/demo-data.ts`; metric cards and chart
render real numbers computed from that fixed demo dataset (not fake placeholder
text); recent-activity table is read-only.

**Phase 2+ behavior:** metrics and chart computed from live Supabase queries
(TanStack Query), auto-refreshed via Realtime subscriptions so a payment recorded on
another device updates this page without a manual reload.

**Controls:** none that mutate data — this page is read-only by design. "View all"
links on the recent-activity table navigate to Active/Completed Transactions.

**States:** loading (skeleton metric cards), error (ErrorState with retry — Phase
2+, since Phase 1 demo data cannot fail to load), empty (unlikely in Phase 1 — demo
data is always present; in Phase 2+, a brand-new shop with zero loans shows
EmptyState guiding the owner to "Add your first customer").

**Access:** all roles can view; figures shown may be scoped (Phase 2+: a `staff`
role might see counts but not currency totals, if the owner decides financial
totals are manager/owner-only — **flagged as an open question for Phase 2**, not
decided here).

---

## 2. Add Customer (`/customers/new`)

**Purpose:** onboard a new customer (Workflow 1 in
[03-business-workflows.md](./03-business-workflows.md)).

**Form fields:** full name*, phone*, alternate phone, address*, ID proof type*
(select: Aadhaar/PAN/Voter ID/Driving Licence), ID proof number*, ID photo upload,
notes. (*required)

**Validation (Zod):** name non-empty; phone matches `+91XXXXXXXXXX` or 10-digit
pattern; ID proof number format checked per selected type (e.g., Aadhaar = 12
digits, PAN = `AAAAA9999A` pattern).

**Phase 1 behavior:** form is fully interactive and validates in real time; on
submit, the new customer is appended to **local component state only** (not
persisted, not even to `localStorage`, so a refresh resets it) and a success toast
confirms "Added (demo) — not saved to a database yet." This is a real, working
interaction, not a disabled button — it demonstrates the actual form/validation
flow without implying real persistence.

**Phase 2+ behavior:** submit calls Supabase insert into `customers`; duplicate-phone
warning (Workflow 1 edge case) queries existing customers first; ID photo uploads to
Storage, written to `attachments`.

**States:** validation errors inline per field; submit button disabled while
submitting; success toast; no loading/error/empty states apply (this is a form, not
a list).

**Access:** staff, manager, owner can all create customers.

---

## 3. New Jewellery Loan (`/loans/new`)

**Purpose:** appraise item(s) and disburse a loan (Workflows 2 & 3).

**Form fields:** customer (searchable select — existing demo customers in Phase 1),
item(s) repeating group (category, description, gross weight, net weight, stone
weight, purity, estimated value — with a live-computed suggested value), principal
amount*, interest rate %/month* (defaults from demo shop settings), issue date*
(defaults today).

**Validation:** principal > 0; rate > 0; at least one item; weights > 0 and
net ≤ gross.

**Phase 1 behavior:** fully interactive multi-item form; submit appends to local
in-memory demo loan list and shows a toast; does not persist. The suggested-value
calculation runs for real against entered weights/rate (it's a pure calculation, not
a stub).

**Phase 2+ behavior:** submit calls `create_loan()` RPC (see
[02-database-schema-erd.md](./02-database-schema-erd.md)); generates the loan
receipt PDF (Phase 3, jsPDF — **disabled with "PDF receipts ship in Phase 3" in
Phase 1/2** until then, not silently missing).

**Access:** manager, owner only (per the role matrix in
[02-database-schema-erd.md](./02-database-schema-erd.md) — loan creation moves money
out).

---

## 4. Receive Payment (`/payments/new`)

**Purpose:** record an interest, partial-principal, or full-closure payment
(Workflow 5).

**Form fields:** loan (searchable select by loan number or customer name), the
page shows computed "interest due as of today" and "outstanding principal" for the
selected loan (read-only, computed via
[04-interest-calculation.md](./04-interest-calculation.md) logic) before the amount
field, amount received*, payment type (auto-suggested from amount vs. interest due,
overridable), payment method (cash/UPI/bank transfer), date (defaults today).

**Validation:** amount > 0; amount ≤ outstanding principal + interest due (full
closure ceiling) — overpayment is rejected client-side as a first line of defense
*and* server-side in Phase 2+ (per the edge case in
[03-business-workflows.md](./03-business-workflows.md) Workflow 5 — never trust the
client alone for this).

**Phase 1 behavior:** fully interactive against the demo loan list; running the
actual interest-calculation function from `src/lib/calculations` (once written) on
demo loans so the "interest due" figure shown is real math, not a placeholder;
submit updates local demo state and shows a toast, does not persist.

**Phase 2+ behavior:** submit calls `record_payment()` RPC; on full closure,
triggers the release flow (Workflow 6) and shows a confirmation dialog ("This will
close the loan and mark the item(s) as released — continue?") before committing,
since closure is a one-way action.

**Access:** staff, manager, owner can record payments (see role matrix); full
closure confirmation dialog is shown to all roles, but the system still logs
`received_by` for accountability.

---

## 5. Customer Records (`/customers`)

**Purpose:** search/browse all customers; entry point to a customer's loan history.

**Data shown:** DataTable of customers (name, phone, address, active loan count,
joined date) backed by `demo-data.ts` in Phase 1.

**Controls:** SearchBar (filters by name/phone — **fully working client-side filter
in Phase 1**, not disabled); "View" row action — **disabled with tooltip "Customer
detail view ships in Phase 2"** in Phase 1, since there is no detail route yet;
"Add Customer" button navigates to page 2 (fully working navigation).

**Phase 2+ behavior:** search becomes a server-side/query-cached filter for scale;
"View" opens a customer detail page (loan history, documents) — a new route added
in Phase 2, not specified further here since it did not exist in the original 9-page
list.

**States:** EmptyState ("No customers yet — Add your first customer") if the list is
empty; LoadingState (skeleton rows) in Phase 2+ while fetching.

**Access:** all roles can view; edit/delete actions (Phase 2+) restricted to
manager/owner.

---

## 6. Active Transactions (`/loans/active`)

**Purpose:** work queue of currently open loans (`active` + `overdue` status).

**Data shown:** DataTable (loan number, customer, principal, interest accrued,
status badge, due/next-due date) from `demo-data.ts`, filtered to non-completed
statuses.

**Controls:** SearchBar + status filter (active/overdue) — **fully working
client-side** in Phase 1; "Receive Payment" row action navigates to page 4 with the
loan pre-selected (**fully working**); "View" row action — **disabled, same reason
as Customer Records**.

**Phase 2+ behavior:** live via Realtime — a payment recorded on another device
updates this table without reload; overdue flag reflects
`recompute_overdue_status()`.

**States:** StatusBadge color-codes `active` (neutral) vs `overdue` (warning);
EmptyState if no active loans; LoadingState in Phase 2+.

**Access:** all roles can view; financial columns may be role-gated — same open
question flagged on the Dashboard page.

---

## 7. Completed Transactions (`/loans/completed`)

**Purpose:** historical record of closed loans (`completed`, `auctioned`,
`written_off`).

**Data shown:** DataTable (loan number, customer, principal, total interest paid,
closure type, closed date) from `demo-data.ts`.

**Controls:** SearchBar + closure-type filter — **fully working client-side**;
"View" row action — **disabled, same reason as above** (detail/ledger view is
Phase 2+).

**Phase 2+ behavior:** "View" opens the full ledger/transaction history for that
loan (Workflow 8) — read-only, since the loan is closed.

**States:** EmptyState, LoadingState as above.

**Access:** all roles can view (historical record, lower sensitivity than active
money).

---

## 8. Reports (`/reports`)

**Purpose:** shop-level reporting — monthly interest collected, overdue list,
customer ledger exports.

**Phase 1 behavior:** cards describing each report type (Monthly Interest Report,
Overdue Report, Customer Ledger Export) with a live Recharts chart of demo loan
status breakdown (**fully working, real chart of demo data**); each report card's
"Export" button is **disabled with an inline explanation: "Reporting engine
(ExcelJS / jsPDF) ships in Phase 3"** — visible and explained, not hidden or fake.

**Phase 3+ behavior:** Export buttons become functional — ExcelJS for
spreadsheet exports, jsPDF for printable summaries, PapaParse for CSV; exports are
optionally saved to Storage and tracked in `backup_jobs`.

**Access:** manager, owner (reports expose aggregate financial data).

---

## 9. Settings & Backup (`/settings`)

**Purpose:** shop profile, business-rule defaults, and backup/export management.

**Sections:**
- **Shop profile** (name, address, GSTIN, phone — used on receipts/reports):
  Phase 1 shows the form pre-filled from demo values, **fields are editable and
  validate**, but the Save button is **disabled with tooltip "Connect Supabase in
  Phase 2 to persist settings"** — so the interaction is visibly real, just not yet
  wired to persistence.
- **Business rules** (default interest rate, interest rounding policy, grace period
  days, overdue threshold months — the exact settings named in
  [04-interest-calculation.md](./04-interest-calculation.md) and
  [03-business-workflows.md](./03-business-workflows.md)): same Phase 1 treatment —
  editable, validated, Save disabled with the same explanation.
- **Backup & export**: "Export full backup" / "Restore from backup" buttons —
  **disabled with tooltip "Requires Supabase Storage integration (Phase 2/3)"**;
  a read-only list of past backup jobs (empty in Phase 1, since `backup_jobs` has no
  real data yet) uses EmptyState.

**Access:** owner only for business rules and backup/restore (highest-sensitivity
settings in the app); manager may view shop profile read-only — **this role
restriction is a recommendation, flagged for your confirmation**, since the brief
did not specify per-field settings permissions.

**States:** no loading/error states needed in Phase 1 (static demo values); Phase
2+ adds standard loading/error handling consistent with
[09-error-handling-validation-backup.md](./09-error-handling-validation-backup.md).
