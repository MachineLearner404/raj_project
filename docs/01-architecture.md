# Application Architecture & Data Flow

## Summary

This is a **serverless single-page application**: a React SPA talks directly to
Supabase (hosted Postgres + Auth + Storage + Realtime) over HTTPS. There is no
custom backend server to deploy, patch, or scale — Supabase *is* the backend.
Business-critical mutations (anything that touches money — payments, loan closure,
principal reduction) are routed through **Postgres functions (RPCs)**, not raw
table writes, so that the database — not the client — is the single point of truth
for financial correctness, even when two shop devices write at the same time.

```mermaid
flowchart LR
    subgraph Client["Browser / Tablet (React SPA)"]
        UI[React UI<br/>pages + shared components]
        RQ[TanStack Query<br/>cache + invalidation]
        SB_JS[Supabase JS client]
        UI --> RQ --> SB_JS
    end

    subgraph Supabase["Supabase Project (single source of truth)"]
        AUTH[Auth<br/>staff accounts, JWT]
        PG[(Postgres<br/>tables + RLS + RPC functions)]
        RT[Realtime<br/>change broadcasts]
        ST[Storage<br/>item photos, ID proof, backups]
    end

    SB_JS -- "REST (PostgREST) /<br/>RPC calls, JWT auth" --> PG
    SB_JS -- "sign in / session" --> AUTH
    SB_JS -- "subscribe to changes" --> RT
    PG -- "row change events" --> RT
    SB_JS -- "upload/download files" --> ST

    DeviceB["A second staff device<br/>(tablet / PC)"] -. "same Supabase project,\nlive via Realtime" .-> Supabase
```

## Why this shape

- **Multiple devices share one cloud database** (a hard requirement): Supabase
  Postgres is the single shared store; every device — whether the owner's laptop or
  a counter tablet — reads and writes the same project. No local-only state for
  anything financial.
- **No custom server** keeps operational burden near zero for a small shop business —
  nothing to patch, no server to go down independently of the database.
- **Row Level Security (RLS)**, not application code, is the real authorization
  boundary. The browser only ever holds the Supabase *anon* public key — safe to
  expose because RLS policies (scoped by the signed-in staff user's role) decide what
  that key can actually read or write. The `service_role` key (which bypasses RLS)
  is never sent to the browser — see [07-environment-variables.md](./07-environment-variables.md)
  and [08-security-threat-checklist.md](./08-security-threat-checklist.md).
- **Postgres RPC functions for money-moving actions** (`record_payment()`,
  `close_loan()`, etc. — see [02-database-schema-erd.md](./02-database-schema-erd.md))
  wrap the ledger update + balance recalculation + status change in one atomic
  transaction. This is what prevents a race where two devices recording a payment
  for the same loan within seconds of each other could corrupt the outstanding
  balance — the function serializes on the loan row.
- **Realtime subscriptions** let a second device see a loan flip to "paid this month"
  or "closed" within seconds, without a manual refresh — important when, e.g., the
  owner is on a laptop doing reports while a staff member is at the counter
  recording payments.

## Layers

| Layer | Responsibility | Where |
|---|---|---|
| Presentation | Pages, forms, tables, charts — no business math | `src/features/*`, `src/components/*` |
| Client state/cache | Server-state caching, invalidation, retries | `src/app/query-client.ts`, TanStack Query hooks in `src/hooks` (Phase 2) |
| Domain logic (pure) | Interest/ledger math, validation schemas — framework-free, unit-tested | `src/lib/calculations`, `src/lib/validators` |
| Data access | Supabase client, typed queries/RPC calls | `src/lib/supabase` |
| Backend (managed) | Auth, RLS-enforced Postgres, Storage, Realtime | Supabase project (see [02-database-schema-erd.md](./02-database-schema-erd.md)) |

The **domain logic layer is deliberately framework-free**: the interest calculation
in [04-interest-calculation.md](./04-interest-calculation.md) must be implementable
and unit-testable as a plain TypeScript function (and, for the parts that must be
race-safe, as a Postgres function) — not something that only works wired into React.

## Data flow: a representative request (recording a payment)

```mermaid
sequenceDiagram
    actor Staff
    participant UI as Receive Payment page
    participant RHF as React Hook Form + Zod
    participant RQ as TanStack Query mutation
    participant PG as Supabase Postgres RPC: record_payment()
    participant RT as Realtime

    Staff->>UI: Enter amount, select loan, submit
    UI->>RHF: Validate (amount > 0, amount <= logical max, loan not already closed)
    RHF-->>UI: Valid
    UI->>RQ: mutate(record_payment params)
    RQ->>PG: RPC call (authenticated via staff JWT)
    PG->>PG: Begin transaction:\n- insert payments row\n- insert loan_ledger_entries row(s)\n- recompute outstanding principal / interest_settled_through\n- update loan status if now overdue/closed
    PG-->>RQ: New loan + payment state
    PG-->>RT: Row change broadcast
    RQ-->>UI: Cache updated, receipt data returned
    RT-->>UI: Any other open device auto-refreshes the same loan
    UI->>Staff: Toast confirmation + option to print receipt
```

## Environments

Local development, staging, and production are **three separate Supabase projects**
(not schemas within one project), so a bug in staging can never touch real customer
money or data. Each environment gets its own `.env` (never committed — see
[07-environment-variables.md](./07-environment-variables.md)) pointing at its own
project URL/keys. Schema is kept in sync across environments via the versioned SQL
migrations in `supabase/migrations/`, applied with the Supabase CLI.

## Out of scope for this architecture (explicitly deferred)

- A native mobile app — the SPA is responsive and installable as a PWA if needed
  later, but no App Store/Play Store artifact is planned.
- Multi-branch / multi-shop tenancy — the schema in
  [02-database-schema-erd.md](./02-database-schema-erd.md) is deliberately
  single-shop for now; see that doc's "Future scaling note" for what would change.
- Offline-first support — the app assumes shop wifi/mobile data is available;
  no offline queue/sync is designed in Phase 0–4.
