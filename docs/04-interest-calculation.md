# Interest Calculation — Option B (Completed-Month + Reducing-Principal)

You selected **Option B**: completed-month interest, calculated on a reducing
principal balance. This document defines the algorithm precisely enough to
implement and unit-test unambiguously. **One parameter in this algorithm
(partial-month rounding) is a business decision, not a technical one — it is
flagged explicitly below and needs your sign-off before Phase 2 implements it.**

## Plain-language definition

- Interest is charged **per completed month** the loan has been outstanding —
  "month" here means a 30-day block counted from the loan's `issue_date` (e.g., a
  loan issued 1 June has month-boundaries on 1 July, 1 Aug, 1 Sep…), **not** the
  calendar month. There is no daily proration within a month.
- Whenever principal is partially repaid, the **outstanding balance used for future
  interest** drops to the new, lower amount — but only from the **next** month
  boundary onward (see "Why not prorate the reduction" below). Interest already
  accrued for months **up to and including** the month the reduction happened in is
  still calculated on the balance that applied for that month.

## The one open decision: partial-month rounding

If a customer repays mid-month (an "incomplete" month at the time of payment), does
the shop:

- **(a) `round_up_partial_month`** — charge for that month in full, as if it were
  completed (standard, revenue-protective — this is the most common convention in
  Indian gold-loan / pawnbroking practice), or
- **(b) `round_down_partial_month`** — waive interest on the started-but-not-finished
  month entirely (customer-friendly, costs the shop some interest income)?

**This document assumes (a), `round_up_partial_month`, as the default**, and models
`shop_settings.interest_rounding_policy` as a configurable field precisely so this
can be changed without a code change if you decide otherwise. **Please confirm
before Phase 2**: should the default be (a) or (b)? This single setting changes how
much interest is collected on every early repayment and every full closure, so it
should be a deliberate choice, not an inherited assumption.

## Algorithm (assuming `round_up_partial_month`)

For a loan with `principal`, monthly rate `r` (percent), `issue_date`, and
`interest_settled_through` (initially = `issue_date`):

1. **Determine completed months since last settlement:**
   `completed_months = floor(days_between(interest_settled_through, today) / 30)`.
2. **Interest due for those months:**
   `interest_due = completed_months × (current_outstanding_principal × r / 100)`,
   using whatever `current_outstanding_principal` was in effect through each of
   those months (see step 4 for when it changes).
3. **On a payment that is interest-only:** apply to `interest_due`. If it fully
   covers `interest_due`, advance `interest_settled_through` by
   `completed_months × 30 days`. If it partially covers it, record the partial
   `interest_payment` ledger entry and do **not** advance
   `interest_settled_through` — the shortfall carries forward.
4. **On a payment that includes principal reduction:** first clear `interest_due` as
   above, then apply the remainder to reduce `current_outstanding_principal`. The
   reduced principal takes effect for interest calculated from the **next** month
   boundary after the payment date onward — the month-in-progress at the time of
   payment is still billed (at closure or at its own completion) against the
   **pre-reduction** balance.
5. **On full closure:** `interest_due` is computed through the current (possibly
   partial, rounded up per policy) month, added to `current_outstanding_principal`,
   and the total is what the customer must pay to close.

### Why not prorate the reduction mid-month

Option B pairs "no daily proration for completed-month interest" with "reducing
principal." Prorating the *reduction's effective date* to the exact day would
reintroduce daily proration through the back door and contradict the "completed
month" rule. Freezing the reduction's effect to the next month boundary keeps the
whole system consistent: **every interest figure in this app is computed per whole
month, on whichever principal was in effect for that whole month** — no exceptions,
no partial-day math anywhere.

## Worked example

Loan: ₹1,00,000 principal, 1.5%/month, issued **1 June 2025**.
Month boundaries (30-day blocks from issue date): 1 Jul, 31 Jul, 30 Aug, 29 Sep …

| Date | Event | Interest due before | Action | Principal after | `interest_settled_through` after |
|---|---|---|---|---|---|
| 1 Jun 2025 | Disbursed | — | `create_loan()` | ₹1,00,000 | 1 Jun 2025 |
| 1 Jul 2025 | Month 1 completed | ₹1,500 (1,00,000 × 1.5%) | — | ₹1,00,000 | 1 Jun 2025 |
| 5 Jul 2025 | Customer pays ₹1,500 (interest only) | ₹1,500 | Fully clears month 1 | ₹1,00,000 | 1 Jul 2025 |
| 31 Jul 2025 | Month 2 completed | ₹1,500 | — | ₹1,00,000 | 1 Jul 2025 |
| 10 Aug 2025 | Customer pays ₹51,500 (₹1,500 interest + ₹50,000 principal) | ₹1,500 | Clears month-2 interest; ₹50,000 reduces principal — **takes effect next month boundary (30 Aug)**, not immediately | ₹50,000 *(effective 30 Aug)*, still ₹1,00,000 basis for the in-progress month | 31 Jul 2025 |
| 30 Aug 2025 | Month 3 completed (still on old balance, since reduction happened mid-month-3) | ₹1,500 (on ₹1,00,000 — the balance in effect for all of month 3) | — | ₹50,000 now in effect for month 4 onward | 31 Jul 2025 |
| 29 Sep 2025 | Month 4 completed (now on reduced balance) | ₹750 (₹50,000 × 1.5%) | — | ₹50,000 | — |

This table is the acceptance-test fixture for the Phase 2/3 unit tests of
`lib/calculations/interest.ts` — any implementation must reproduce these exact
figures given this exact sequence of events.

## Full closure example (continuing the table above)

If, instead of paying ₹750 at month 4, the customer closes the loan on **15
September 2025** (mid-month-4, 16 days into a started month):

- Under `round_up_partial_month` (default assumed here): month 4 is billed in full
  — ₹750 — even though only 16 of 30 days have elapsed. Total due to close:
  ₹50,000 (principal) + ₹750 (month 4, rounded up) = **₹50,750**.
- Under `round_down_partial_month`: month 4's partial interest is waived entirely.
  Total due to close: **₹50,000** (principal only).

This ₹750 difference on a single closure is exactly why the rounding policy needs
your explicit decision rather than a silent default.

## What this document deliberately does not decide

- **Exact "month" definition** — 30-day blocks from issue date (assumed here) vs.
  calendar months (1st-to-1st) vs. anniversary-of-issue-date-in-each-calendar-month.
  30-day blocks are assumed as the common gold-loan convention; confirm if your shop
  uses a different convention.
- **Grace period before "overdue"** and **overdue-to-auction-eligible threshold** —
  these are `shop_settings` values (`grace_period_days`,
  `overdue_threshold_months`) to be set by the owner, not hardcoded; see
  [03-business-workflows.md](./03-business-workflows.md) Workflow 7.
- **Penal/default interest rate** for overdue loans — not modeled in Phase 0–4 unless
  you confirm the shop charges a different (higher) rate once a loan is overdue. If
  so, this document will need a `penal_rate_percent_per_month` addition before
  Phase 2.

## Acceptance criteria for Phase 2/3 implementation

- A pure, framework-free function in `src/lib/calculations/interest.ts` implements
  this algorithm and reproduces the worked example table above exactly, via Vitest
  unit tests — before it is ever wired to a UI or to Supabase.
- The equivalent logic is **also** implemented as a Postgres function
  (`record_payment()`/`close_loan()` per [02-database-schema-erd.md](./02-database-schema-erd.md))
  so that the database enforces the same rule even if a client bypassed the UI —
  the two implementations must be kept in sync by the same test fixtures.
- `shop_settings.interest_rounding_policy` is read, not hardcoded, by both
  implementations.
