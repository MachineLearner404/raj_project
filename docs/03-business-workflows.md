# Business Workflows

All workflows below reference the schema in
[02-database-schema-erd.md](./02-database-schema-erd.md) and the interest rules in
[04-interest-calculation.md](./04-interest-calculation.md). Each workflow lists
actors, preconditions, steps, postconditions, and edge cases — this is the
specification the Phase 2+ implementation must satisfy.

## 1. Customer management

**Actors:** staff, manager, owner.

**Preconditions:** none (first-time customer) or an existing `customers` row
(returning customer).

**Steps:**
1. Staff searches by phone number or name (Customer Records page) to check whether
   the person is already a customer, before creating a duplicate.
2. If new: staff opens Add Customer, enters full name, phone, address, ID proof type
   and number, optionally a photo of the ID proof (Storage upload → `attachments`).
3. System validates: phone format, ID proof number format per type (e.g., Aadhaar =
   12 digits), required fields present.
4. On save, a `customers` row is created with `created_by` = current staff user.
5. For a returning customer, staff instead opens their existing record from Customer
   Records and proceeds directly to New Jewellery Loan.

**Postconditions:** a `customers` row exists; it can now be selected when creating a
loan.

**Edge cases:**
- Duplicate phone number: system warns ("A customer with this phone already exists —
  open their record instead?") rather than silently creating a second record, but
  does **not** hard-block (same phone can legitimately be shared within a family;
  the warning, not a unique constraint, is the right control here).
- Customer declines to show photo ID: shop policy decision, not a system decision —
  the ID proof fields remain required by default (standard pawn/gold-loan practice
  for KYC), but this is a `shop_settings`-level policy the owner should be able to
  review, not hardcoded as unchangeable.
- Customer's details change later (new address/phone): editing a customer record is
  allowed by manager/owner; every edit is captured in `audit_log` (old values +
  new values + who + when), since this is still personal data tied to money owed.

## 2. Jewellery deposit and valuation

**Actors:** staff/manager/owner (appraisal itself is a human judgment call the
system records, not automates).

**Preconditions:** a customer exists and has brought item(s) to pledge.

**Steps:**
1. Staff weighs each item: gross weight, then net weight after mentally/physically
   deducting non-gold parts (stones, studs) — `gross_weight_grams`,
   `net_weight_grams`, `stone_weight_grams`.
2. Staff records purity (`purity_karat` — typically 22K in Indian gold-loan practice,
   sometimes 18K/20K).
3. Staff enters or confirms today's gold rate (`gold_rates` reference table, or a
   manual override) — this rate is **frozen onto the item** as
   `gold_rate_used_per_gram`, not re-read later.
4. System computes a suggested `estimated_value` (net weight × purity factor × rate),
   shown as a starting point — the shop can adjust it; the final value is a business
   judgment, not purely mechanical.
5. Staff photographs the item(s) (`attachments` linked to `jewellery_items`) —
   protects both the shop and the customer against later disputes about condition.
6. Item(s) are attached to the loan being created (see Workflow 3) — items do not
   exist independent of a loan; they are appraised *as part of* creating that loan.

**Postconditions:** one or more `jewellery_items` rows exist, each linked to the loan
created in the same flow, each with a frozen valuation snapshot.

**Edge cases:**
- Multiple items in one pledge (common — e.g., a necklace + two bangles): all attach
  to the **same** loan; the loan's principal is against the combined valuation.
  Partial item release (releasing *one* bangle while the loan on the necklace stays
  open) is explicitly **out of scope for Phase 1–3** — flagged as a possible Phase 4+
  feature, not silently assumed.
- Item valuation significantly exceeds requested loan amount or vice versa: the UI
  surfaces the suggested value vs. requested principal side by side so staff can
  catch an obvious mismatch before disbursing; the system does not block it (lending
  below value is normal shop practice — a loan-to-value margin is expected).

## 3. Loan creation and disbursement

**Actors:** staff (creation allowed per role matrix in
[02-database-schema-erd.md](./02-database-schema-erd.md)) — **not** `staff` role in
the default policy; loan creation requires `manager` or `owner` (money is leaving
the shop).

**Preconditions:** customer exists; item(s) appraised (Workflow 2).

**Steps:**
1. Manager/owner opens New Jewellery Loan, selects the customer, attaches the
   appraised item(s), enters principal amount and interest rate (defaults from
   `shop_settings.default_interest_rate_percent_per_month`, overridable per loan),
   sets issue date (defaults to today) and tenure (e.g., 12 months, informational —
   gold loans are typically renewable rather than hard-expiring).
2. System validates principal > 0, rate > 0, at least one item attached, item(s) not
   already attached to another open loan.
3. On submit, `create_loan()` (see schema doc) runs as one transaction: inserts
   `loans`, inserts `jewellery_items` (if not already inserted during appraisal),
   writes a `disbursement` ledger entry, generates the human-readable `loan_number`.
4. A loan receipt/agreement is generated (jsPDF, Phase 3) summarizing items, value,
   principal, rate, and terms — given to the customer.

**Postconditions:** `loans.status = 'active'`, `interest_settled_through = issue_date`
(no interest owed yet), item(s) marked as pledged against this loan.

**Edge cases:**
- Disbursement is recorded as having happened (cash handed over) — the system does
  not track *how* the shop sourced that cash; that is outside this app's scope.
- Backdating `issue_date` (e.g., correcting a data-entry delay) is allowed for
  manager/owner within a short window and is always audit-logged — backdating by
  months to artificially change interest due is a red flag the audit log makes
  visible, not something the system tries to detect automatically.

## 4. Interest calculation

Full algorithm, worked examples, and the one business decision that needs the
owner's explicit sign-off are in the dedicated
[04-interest-calculation.md](./04-interest-calculation.md) — this is the single most
error-prone part of the whole system and deserves its own document rather than a
summary here.

## 5. Partial and full repayments

**Actors:** staff can record a payment (role matrix allows `staff` for
`record_payment`, since this is money coming *in*, lower risk than disbursement);
full closure and anything touching `closed_loan` status still visible to
manager/owner for review.

**Preconditions:** loan exists and is `active` or `overdue`.

**Steps (interest-only payment):**
1. Customer pays the interest due for completed month(s). Staff opens Receive
   Payment, selects the loan (search by loan number or customer), system shows
   interest due as of today per [04-interest-calculation.md](./04-interest-calculation.md).
2. Staff enters amount received, `payment_type = 'interest'`, method, date.
3. `record_payment()` validates amount matches (or is less than — see partial
   interest edge case below) interest due, writes `payments` + `interest_payment`
   ledger entry, advances `interest_settled_through`.
4. Loan `status` stays `active` (or flips from `overdue` back to `active` if this
   payment clears the backlog).

**Steps (partial principal repayment):**
1. Customer pays more than interest due — the excess is applied to principal.
2. `record_payment()` splits the amount: first clears any interest due, remainder
   reduces `current_outstanding_principal`, writes **two** ledger entries
   (`interest_payment` + `principal_payment`) from the one `payments` row.
3. Future interest (from the next completed-month boundary) is calculated on the
   new, lower principal — see [04-interest-calculation.md](./04-interest-calculation.md)
   for exactly when the reduction takes effect.

**Steps (full closure):**
1. Customer pays outstanding principal + all interest due through closure per the
   shop's `interest_rounding_policy`.
2. `record_payment()` with `payment_type = 'full_closure'` zeroes
   `current_outstanding_principal`; `close_loan()` sets `status = 'completed'`,
   `closed_at = now()`, `closure_type = 'repaid'`.
3. Triggers Workflow 6 (Jewellery Release).

**Postconditions:** ledger reflects the payment; loan balance/status updated
atomically; customer receives a receipt (Phase 3, jsPDF).

**Edge cases:**
- **Underpayment of interest** (customer pays less than full interest due): allowed —
  recorded as a partial `interest_payment`; the remainder stays due and
  `interest_settled_through` does **not** advance past the partially-paid month.
  The system does not silently treat a partial interest payment as "this month is
  settled."
- **Overpayment beyond outstanding principal**: rejected by `record_payment()` with
  a clear validation error — the UI must show the exact outstanding amount before
  submission so this is rare, but the server-side function is the actual guard
  (never trust the client alone for a financial boundary).
- **Two devices recording payments on the same loan near-simultaneously**: the
  Postgres function serializes on the loan row; the second call sees the
  already-updated balance and computes against *that*, not a stale read. This is
  exactly why payments are never applied as a plain client-side `UPDATE`.
- **Payment method is cash vs. UPI/bank transfer**: recorded for the shop's own
  reconciliation; the app does not integrate with a payment gateway in Phase 1–4 —
  all payments are manually recorded after money is received by other means.

## 6. Jewellery release

**Actors:** staff hands over the item; manager/owner's prior approval is implicit in
having authorized the closure.

**Preconditions:** loan `status` transitions to `completed` (Workflow 5, full
closure) or an `auctioned`/`written_off` closure (Workflow 7, below).

**Steps:**
1. On `close_loan(closure_type = 'repaid')`, the system marks the loan's items as
   released and generates a release receipt (Phase 3) that the customer signs/takes.
2. Staff physically returns the item(s) to the customer **only after** the system
   confirms `status = 'completed'** — the release receipt is the proof of return, so
   the on-screen confirmation should happen before, not after, the physical handover.

**Postconditions:** item(s) are logically "released"; the loan is closed and
read-only (no further payments can be recorded against a `completed` loan — enforced
by `record_payment()` checking status, and by RLS if attempted directly).

**Edge cases:**
- Customer loses the original receipt: identity verification (ID proof already on
  file) plus matching loan number/customer record substitutes — a shop policy
  decision, not a system-enforced requirement, since the system's job here is to
  have the record available, not to dictate the shop's in-person verification
  process.
- Partial item release (see Workflow 2 edge case) remains out of scope.

## 7. Overdue handling and auction (extends repayment/release)

**Steps:**
1. `recompute_overdue_status()` (Phase 3+, scheduled or triggered on dashboard load)
   flips `status` to `overdue` once `interest_settled_through` falls behind
   `shop_settings.grace_period_days` past the last completed month.
2. If overdue persists beyond `shop_settings.overdue_threshold_months`, the loan
   becomes **eligible** for auction — surfaced on the dashboard/Active Transactions
   page as a flag, never an automatic status change.
3. An owner/manager makes the actual auction decision and calls
   `close_loan(closure_type = 'auctioned')` deliberately. This is a legally and
   relationally significant action (the shop is disposing of someone's pledged
   gold) — the system's role is to surface accurate information, not to act
   autonomously. See [08-security-threat-checklist.md](./08-security-threat-checklist.md)
   for the compliance note on this.

**Postconditions:** `status = 'auctioned'`, `closure_type = 'auctioned'`, ledger
closed out, item marked disposed (not "released to customer").

## 8. Transaction history

**Actors:** any authenticated staff can view history scoped to their role's read
access (see RLS policy shape in
[02-database-schema-erd.md](./02-database-schema-erd.md)).

**What it is:** the union of `loan_ledger_entries` (the accounting trail) and
`payments` (the human-facing receipts) for a given loan, customer, or date range —
surfaced on the Customer Records detail view, the loan detail view (reached from
Active/Completed Transactions), and the Reports page.

**Why both tables matter here:** `payments` answers "what did this customer hand
over and when" (receipt-level); `loan_ledger_entries` answers "exactly how did that
money get applied" (accounting-level) — a shop owner reconciling cash at day's end
wants the first; resolving a customer dispute about how much principal is left wants
the second.

**Immutability guarantee:** because `loan_ledger_entries` has no `UPDATE`/`DELETE`
RLS policy for any role, transaction history shown to the user is guaranteed to
match what the database will show anyone else, at any later time — this is the
property that makes the history trustworthy as a record, not just a convenient
view.
