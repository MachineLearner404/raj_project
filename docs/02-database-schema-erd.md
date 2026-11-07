# Database Schema, Relationships & Data Flow

This is the proposed Supabase (Postgres) schema for Phase 2. **No migration has been
written or applied yet** — this document is the design to be reviewed and approved
before any `supabase/migrations/*.sql` file is created.

## Design principles

1. **Append-only financial ledger.** Every event that changes money owed
   (disbursement, interest accrual, payment, closure) is written once to
   `loan_ledger_entries` and never updated or deleted. `loans` carries denormalized
   "current balance" columns for fast reads, but the ledger is the source of truth
   and the audit trail. This is standard practice for any system handling other
   people's money — it is what makes "what happened to this loan" answerable months
   later, and what a dispute or external audit would need.
2. **Single shop, not multi-tenant — by choice, not oversight.** The brief describes
   one shop. No `shop_id` column is added to every table "just in case." See
   **Future scaling note** at the end of this document for exactly what would change
   if a second branch were added later.
3. **Role-based access via Postgres Row Level Security (RLS)**, not application-layer
   checks. The browser's Supabase key is public by design (anon key); RLS policies,
   keyed off `auth.uid()` and the signed-in user's role in `app_users`, are the actual
   permission boundary. Every table below ships with RLS enabled.
4. **Money-moving writes go through Postgres functions (RPCs)**, never direct
   `INSERT`/`UPDATE` from the client, so balance recalculation is atomic and
   race-safe across multiple devices. See "Key functions" below.
5. **Valuation facts are frozen at the time they're recorded.** E.g., the gold rate
   used to appraise an item is stored directly on the item row, not looked up live
   from `gold_rates` later — because a loan's valuation must reflect what was agreed
   on the day, even if the market rate changes afterward.

## Entity-relationship diagram

```mermaid
erDiagram
    APP_USERS ||--o{ CUSTOMERS : "created_by"
    APP_USERS ||--o{ LOANS : "created_by"
    APP_USERS ||--o{ PAYMENTS : "received_by"
    APP_USERS ||--o{ AUDIT_LOG : "changed_by"
    APP_USERS ||--o{ BACKUP_JOBS : "requested_by"

    CUSTOMERS ||--o{ LOANS : "pledges against"
    LOANS ||--o{ JEWELLERY_ITEMS : "secures"
    LOANS ||--o{ PAYMENTS : "receives"
    LOANS ||--o{ LOAN_LEDGER_ENTRIES : "records"
    PAYMENTS ||--o{ LOAN_LEDGER_ENTRIES : "generates"

    CUSTOMERS ||--o{ ATTACHMENTS : "ID proof / photo"
    JEWELLERY_ITEMS ||--o{ ATTACHMENTS : "item photos"
    LOANS ||--o{ ATTACHMENTS : "agreement scan"

    GOLD_RATES ..  JEWELLERY_ITEMS : "rate frozen onto item at appraisal time (no live FK)"
    SHOP_SETTINGS

    APP_USERS {
        uuid id PK "= auth.users.id"
        text full_name
        text role "owner | manager | staff"
        text phone
        boolean is_active
        timestamptz created_at
    }

    CUSTOMERS {
        uuid id PK
        text full_name
        text phone
        text alternate_phone
        text address
        text id_proof_type "Aadhaar|PAN|VoterID|DrivingLicence"
        text id_proof_number "masked in UI lists"
        text notes
        boolean is_active
        uuid created_by FK
        timestamptz created_at
        timestamptz updated_at
    }

    LOANS {
        uuid id PK
        text loan_number "unique, human-readable e.g. JL-2025-1001"
        uuid customer_id FK
        numeric principal_amount
        numeric interest_rate_percent_per_month
        date issue_date
        int tenure_months
        date due_date
        text status "active|overdue|completed|auctioned|written_off"
        numeric current_outstanding_principal "denormalized"
        numeric total_interest_paid "denormalized"
        numeric total_interest_accrued_unpaid "denormalized"
        date interest_settled_through "last fully-paid-for month boundary"
        uuid created_by FK
        timestamptz created_at
        timestamptz updated_at
        timestamptz closed_at
        text closure_type "repaid|auctioned|written_off"
        text notes
    }

    JEWELLERY_ITEMS {
        uuid id PK
        uuid loan_id FK
        text category "necklace|ring|bangle|coin|chain|earrings|other"
        text description
        numeric gross_weight_grams
        numeric net_weight_grams "after stone deduction"
        numeric stone_weight_grams
        int purity_karat
        numeric gold_rate_used_per_gram "frozen at appraisal time"
        numeric estimated_value
        text condition_notes
        timestamptz created_at
    }

    PAYMENTS {
        uuid id PK
        uuid loan_id FK
        uuid customer_id FK "denormalized for query convenience"
        numeric amount
        text payment_type "interest|partial_principal|full_closure"
        text payment_method "cash|upi|bank_transfer"
        date payment_date
        text receipt_number
        uuid received_by FK
        text notes
        timestamptz created_at
    }

    LOAN_LEDGER_ENTRIES {
        uuid id PK
        uuid loan_id FK
        uuid related_payment_id FK "nullable"
        text entry_type "disbursement|interest_accrual|interest_payment|principal_payment|full_closure|write_off"
        numeric amount
        numeric principal_balance_after
        numeric interest_due_after
        date entry_date
        uuid created_by FK
        timestamptz created_at "append-only, never updated/deleted"
    }

    GOLD_RATES {
        uuid id PK
        date effective_date
        numeric rate_per_gram_22k
        numeric rate_per_gram_24k
        text source
        uuid created_by FK
        timestamptz created_at
    }

    ATTACHMENTS {
        uuid id PK
        uuid customer_id FK "nullable"
        uuid jewellery_item_id FK "nullable"
        uuid loan_id FK "nullable"
        text file_url "Supabase Storage path"
        text file_type
        uuid uploaded_by FK
        timestamptz uploaded_at
    }

    AUDIT_LOG {
        bigint id PK
        text table_name
        uuid record_id
        text action "insert|update|delete"
        uuid changed_by FK
        timestamptz changed_at
        jsonb old_values
        jsonb new_values
    }

    BACKUP_JOBS {
        uuid id PK
        text export_type "full_backup|csv|excel|pdf_report"
        text status "pending|completed|failed"
        text file_url
        date range_start
        date range_end
        uuid requested_by FK
        timestamptz created_at
        timestamptz completed_at
    }

    SHOP_SETTINGS {
        int id PK "always 1, singleton row"
        text shop_name
        text address
        text gstin
        text phone
        numeric default_interest_rate_percent_per_month
        text default_currency "INR"
        text default_locale "en-IN"
        text interest_rounding_policy "round_up_partial_month | round_down_partial_month"
        int grace_period_days
        int overdue_threshold_months
        text logo_url
        uuid updated_by FK
        timestamptz updated_at
    }
```

### Design note: `ATTACHMENTS` as one polymorphic-ish table

Rather than a generic `(entity_type, entity_id)` pair (which Postgres cannot enforce
a real foreign key against), `attachments` has three *nullable* FK columns
(`customer_id`, `jewellery_item_id`, `loan_id`) with a `CHECK` constraint requiring
**exactly one** to be non-null. This keeps referential integrity enforced by the
database itself, at the cost of three nullable columns instead of one generic pair —
the right trade for a table this small.

### Design note: why `payments` *and* `loan_ledger_entries` both exist

`payments` is the human-facing record ("what did the customer hand over, and when") —
one row per counter transaction, used for receipts and the Receive Payment page.
`loan_ledger_entries` is the accounting trail — one `payments` row can produce **two**
ledger entries (e.g., ₹51,500 received = one `interest_payment` entry clearing ₹1,500
due + one `principal_payment` entry reducing principal by ₹50,000). Collapsing these
into one table would force every payment to be exactly one accounting effect, which
is not true in this business.

## Key Postgres functions (RPCs) — Phase 2 scope

These are the only way client code ever changes money-related state. They are
defined here as **interface contracts**; implementation is Phase 2.

| Function | Called from | Does |
|---|---|---|
| `create_loan(customer_id, items[], principal, rate, issue_date)` | New Jewellery Loan page | Inserts `loans` row, inserts each `jewellery_items` row, writes a `disbursement` ledger entry, returns the new `loan_number`. |
| `record_payment(loan_id, amount, payment_type, method, date)` | Receive Payment page | Within one transaction: validates the loan is not already closed/auctioned, splits the amount across due interest and principal per the rules in [04-interest-calculation.md](./04-interest-calculation.md), inserts `payments` + the resulting `loan_ledger_entries`, updates `loans.current_outstanding_principal` / `interest_settled_through` / `status`, flips status to `completed` if principal reaches zero. |
| `close_loan(loan_id, closure_type)` | Receive Payment (full closure) / manual admin action | Marks a loan `completed`, `auctioned`, or `written_off`; sets `closed_at`; writes a final ledger entry; marks related jewellery items as released (see [03-business-workflows.md](./03-business-workflows.md), Jewellery Release). `auctioned`/`written_off` require `owner` or `manager` role — never automatic. |
| `recompute_overdue_status()` | Scheduled job (Phase 3+) or on-demand from Dashboard refresh | Flags loans `overdue` when `interest_settled_through` has fallen behind `grace_period_days`; does **not** auto-auction — only flags eligibility for a human decision. |
| `create_historical_jewellery_loan(…, previous_payments[])` | New Jewellery Loan page, "Previous / Historical Record" | Creates the pledge through `create_jewellery_loan` with its real past deposit date, sets `transactions.is_historical`, then replays each previous payment through `post_payment` on that payment's own date — one database transaction, idempotent on the pledge key and on each payment key. |
| `calculate_live_settlement(transaction_id, as_of)` | Transaction Detail ("Live Settlement Value"), Receive Payment ("Amount due today") | **Read-only.** Returns the settlement breakdown as of a date from the stored payment and interest ledgers plus elapsed completed periods. Writes nothing, so it never duplicates a payment or an interest event and never persists a figure that would go stale. See [11-financial-calculation-policy.md](./11-financial-calculation-policy.md). |

## Row Level Security — policy shape (Phase 2 scope)

- `app_users.role` is `owner`, `manager`, or `staff`.
- **owner**: full read/write on everything, including `shop_settings` and
  `backup_jobs`, and is the only role allowed to call `close_loan()` with
  `closure_type = 'auctioned'` or `'written_off'`.
- **manager**: full read/write on `customers`, `loans`, `jewellery_items`,
  `payments`; read-only on `shop_settings`; no access to `backup_jobs` or
  `audit_log` beyond their own actions.
- **staff**: can create `customers`, create `payments` (via `record_payment`), read
  `loans`/`jewellery_items`; cannot create loans, cannot edit `shop_settings`, cannot
  see `audit_log`.
- `loan_ledger_entries` and `audit_log` have **no `UPDATE` or `DELETE` policy for any
  role** — enforced at the database level, not just hidden in the UI. If a mistake is
  made, it is corrected with a new, clearly-labeled reversing entry, never by editing
  history.
- Every table's RLS policy requires an authenticated session (`auth.uid() is not
  null`); there is no anonymous read access to any business table.

Full policy SQL is written during Phase 2 implementation, not in this document.

## Indexing notes (Phase 2 scope)

- `customers.phone` — indexed (frequent lookup when a returning customer walks in).
- `loans.loan_number` — unique index (human lookup, printed on receipts).
- `loans.customer_id`, `loans.status` — indexed (Active/Completed Transactions pages
  filter by status constantly).
- `payments.loan_id`, `payments.payment_date` — indexed (transaction history, reports).
- `loan_ledger_entries.loan_id` — indexed (ledger is read per-loan constantly).

## Future scaling note (not built now)

If a second branch/shop is added later: add a `shop_id` column to `customers`,
`loans`, `app_users`, and `shop_settings` becomes a normal multi-row `shops` table
instead of a singleton; RLS policies gain a `shop_id = current_user_shop_id()` clause.
This is a deliberately deferred, well-contained change — not a reason to add the
column speculatively now.
