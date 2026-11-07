# Financial calculation policy

The authoritative calculation is `public.post_payment(...)`, a locked database transaction. The browser may display an estimate but never supplies an interest or allocation total.

## Money and calendar rules

- Database amounts are `numeric(14,2)` (paise precision). The pure TypeScript domain module uses integer paise. Each period's interest is rounded half-up to the nearest paise before it is added.
- Interest is simple: it is calculated from outstanding principal only. Unpaid accrued interest is never added to principal and therefore never earns interest.
- A monthly charge is due only at completed calendar-month anniversaries of `issue_date`; an annual charge is due only at completed yearly anniversaries. A 31 January schedule is 28/29 February, 31 March, 30 April, and so on. There is no partial-month charge.
- Every completed period since the stored anchor is accrued before allocating a payment. A payment pays accrued interest first, then reduces principal. The new principal is used for the next completed period.
- Overpayments are rejected. A loan becomes `REDEEMED` only when both principal and accrued interest are zero.

## Modes frozen on a pledge

Loan terms (`interest_type`, rate, and flat basis) are stored with each transaction and are never read from current shop defaults. `MONTHLY` uses the stated monthly rate; `YEARLY` uses the equivalent annual rate; `FLAT` explicitly records either a fixed amount or a percentage of original principal, then posts that amount once, never periodically.

Example: ₹50,000 at 2% monthly has ₹1,000 due at its first completed month. A ₹20,000 payment allocates ₹1,000 to interest and ₹19,000 to principal, leaving ₹31,000. At the next completed month, interest is ₹620.

Each accrual and settlement is an `interest_events` row with the resulting principal and accrued-interest balance. `payments.transaction_id + idempotency_key` is unique, so a retry returns the already posted result rather than posting twice.
