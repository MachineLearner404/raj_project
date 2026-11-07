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

## Historical pledges and the live settlement value

A pledge deposited before it was entered into the app is created with `public.create_historical_jewellery_loan(...)`, which sets `transactions.is_historical` and keeps the real `issue_date` rather than today. It creates the pledge through the ordinary `create_jewellery_loan` path, then replays each supplied previous payment through `post_payment` on that payment's own date, so historical and counter payments obey one set of rules. Replayed payments are pre-confirmed for jewellery return, because a historical payment that clears a pledge is a redemption that already happened. Payments must be chronological, dated on or after the deposit date and not in the future, must carry distinct idempotency keys, and may not exceed what was outstanding on their own date. Retrying the whole call with the same transaction idempotency key returns the existing pledge and imports nothing again.

The amount a customer owes today is a **read model**, never a stored column: `public.calculate_live_settlement(transaction_id, as_of)` returns original principal, previous principal repayments, remaining principal, total interest accrued, interest already paid, outstanding interest, total payments received and the amount payable, together with the calculation date. It derives everything from the stored `payments` and `interest_events` ledgers plus the completed periods that have elapsed since the last posted anchor, and it writes nothing — so opening a transaction any number of times never duplicates a payment or an interest event, and a settlement figure can never go stale in the database. Reads are shop-scoped and reject future dates and dates before the deposit.

`settlement amount = remaining principal + outstanding interest`

Because the projected interest is not persisted, a change to global interest defaults cannot alter an existing pledge: terms stay frozen on the transaction row.

`src/lib/calculations/interest.ts` exposes `calculateSettlement(...)`, the same replay in pure integer paise. It drives the on-screen preview in the New Jewellery Loan form before anything is saved, and it is a test oracle — it is never the posting authority. `supabase/tests/historical_settlement.test.sql` asserts the database engine and `src/lib/calculations/interest.test.ts` asserts the pure one; both cover the no-payment, partial-payment, multi-payment, incomplete-month, fully-settled and reopened-transaction cases and must agree.
