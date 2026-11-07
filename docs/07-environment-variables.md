# Environment Variables

Canonical reference for every environment variable the app uses. `.env.example` at
the repo root holds the same list with placeholder values only — **never** copy real
values into that file; copy it to `.env` locally (git-ignored) and fill in real
values there, per environment.

## Rules

- No real secret has ever been entered into this repository — `.env.example`
  contains placeholders only (e.g., `your-anon-key-here`).
- `.env` is listed in `.gitignore`; only `.env.example` is tracked.
- Every browser-exposed variable is prefixed `VITE_` (Vite's convention for what it
  inlines into the client bundle) — anything **not** prefixed `VITE_` must never be
  read from `src/` code, because it will not be available to it, and more
  importantly, it is a signal that the value is server/script-only and must stay
  that way.
- Each of staging and production is a **separate Supabase project** (see
  [01-architecture.md](./01-architecture.md)) with its own `.env` — never point a
  local `.env` at the production project.

## Browser-exposed (safe to ship in the client bundle)

| Variable | Required | Purpose |
|---|---|---|
| `VITE_SUPABASE_URL` | Yes | The Supabase project's REST/Auth endpoint. |
| `VITE_SUPABASE_ANON_KEY` | Yes | Public anon key. Safe to expose **because** Row Level Security policies (see [02-database-schema-erd.md](./02-database-schema-erd.md)), not this key, are the real access boundary. |
| `VITE_SHOP_NAME` | No (has a sensible fallback in Phase 1 demo data) | Printed on receipts/reports. |
| `VITE_SHOP_ADDRESS` | No | Printed on receipts/reports. |
| `VITE_SHOP_GSTIN` | No | Printed on receipts/reports if the shop is GST-registered. |
| `VITE_SHOP_PHONE` | No | Printed on receipts/reports. |
| `VITE_DEFAULT_CURRENCY` | No (defaults `INR`) | Currency formatting. |
| `VITE_DEFAULT_LOCALE` | No (defaults `en-IN`) | Number/date formatting. |
| `VITE_SENTRY_DSN` | No (Phase 3+) | Client-side error monitoring, if/when adopted. |

## Server/script-only (must never reach the browser bundle)

| Variable | Required | Purpose |
|---|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | Yes, for admin scripts/migrations only | Bypasses RLS entirely — used only by trusted contexts: migration scripts, admin CLI tooling, scheduled backup jobs. **Never** imported from anything under `src/`. |
| `SUPABASE_PROJECT_REF` | Yes, for Supabase CLI operations | Identifies which project migrations/CLI commands target. |

## Verification checklist (re-run before every deploy)

- [ ] `.env` is not tracked by git (`git status` shows it untracked/ignored, never
      staged).
- [ ] `grep -r "SUPABASE_SERVICE_ROLE_KEY" src/` returns nothing.
- [ ] `.env.example` contains no value that looks like a real key, URL, or secret
      (placeholders only — this was true at last review and must stay true on every
      PR that touches it).
- [ ] Production `.env` values live only in the hosting platform's secret manager /
      CI secret store, never in a file committed anywhere, including private
      branches.

See [08-security-threat-checklist.md](./08-security-threat-checklist.md) for the
broader secrets-management threat model this supports.
