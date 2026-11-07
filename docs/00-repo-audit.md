# Repository Audit & Folder Structure

## Starting state

The repository was found completely empty (no git history, no files) on 2026-11-06.
It was scaffolded from scratch using `npm create vite@latest . -- --template react-ts`,
then layered with Tailwind v4, shadcn/ui, and the rest of the agreed stack. See
[10-phase-plan.md](./10-phase-plan.md) for what was verified working (typecheck, lint,
unit test, build) at the end of the Phase 1 tooling pass.

## Folder structure (current, as scaffolded)

```
new_work/
├── docs/                       # This documentation set (Phase 0)
├── e2e/                        # Playwright end-to-end specs
├── public/                     # Static assets served as-is
├── src/
│   ├── app/                    # Cross-cutting app wiring (query client, router — router pending)
│   ├── components/
│   │   ├── ui/                 # shadcn/ui primitives (generated, treated as vendor code)
│   │   ├── layout/              # AppShell, Sidebar, MobileNav, Topbar, nav config
│   │   └── shared/              # Reusable business-agnostic components (see 06-components-specification.md)
│   ├── data/                   # Demo/sample data for Phase 1 UI only — never imported once Supabase is wired
│   ├── features/                # One folder per business domain page group (customers, loans, payments, reports, settings, auth, interest, gold-rates)
│   ├── hooks/                   # Shared React hooks (TanStack Query hooks land here in Phase 2)
│   ├── lib/
│   │   ├── supabase/            # Supabase client factory
│   │   ├── calculations/        # Interest/ledger math (pure functions, unit-tested) — Phase 2+
│   │   ├── validators/          # Zod schemas shared by forms and (where feasible) edge functions
│   │   └── utils.ts             # `cn()` class-name helper (shadcn convention)
│   ├── test/                    # Vitest setup
│   └── types/                   # Shared TypeScript domain types
├── supabase/
│   ├── migrations/              # SQL migrations (empty until Phase 2 — see 02-database-schema-erd.md)
│   └── seed/                    # Seed scripts for local/staging data
├── .env.example                 # Placeholders only — see 07-environment-variables.md
└── components.json              # shadcn/ui configuration
```

**Rationale for this layout:**
- `features/*` groups by business capability (vertical slices) rather than by technical
  type, so a developer working on "loans" finds pages, hooks, and local components
  together as that domain grows in Phase 2+.
- `components/ui` is kept separate from `components/shared` because `ui/` is
  CLI-generated (shadcn) and should be treated as near-vendor code — regenerated via
  `npx shadcn add`, not hand-edited where avoidable. `components/shared` is
  hand-written, business-aware reusable UI (see [06-components-specification.md](./06-components-specification.md)).
- `lib/calculations` is isolated from UI code specifically so the interest/ledger
  math (the highest-risk logic in this app — see
  [04-interest-calculation.md](./04-interest-calculation.md)) can be unit-tested in
  complete isolation from React and from Supabase.
- `supabase/migrations` is the source of truth for schema (not the Supabase dashboard),
  so schema changes are versioned in git and reproducible across environments.

## Dependencies audit (as installed)

All packages below were installed and confirmed to resolve correctly via `npm install`
and a successful `npm run build`:

| Concern | Package(s) |
|---|---|
| Framework | react, react-dom, vite, @vitejs/plugin-react, typescript |
| Styling | tailwindcss (v4), @tailwindcss/vite, tw-animate-css |
| UI kit | shadcn (CLI), radix-ui, class-variance-authority, lucide-react, next-themes, sonner, cn |
| Routing | react-router-dom |
| Data/cloud | @supabase/supabase-js |
| Server state | @tanstack/react-query, @tanstack/react-query-devtools |
| Forms/validation | react-hook-form, @hookform/resolvers, zod |
| Charts | recharts |
| Documents/exports | jspdf, jspdf-autotable, exceljs, papaparse |
| Dates | date-fns |
| Linting | oxlint |
| Testing | vitest, @vitest/ui, jsdom, @testing-library/react, @testing-library/jest-dom, @testing-library/user-event, @playwright/test |

**Known issue to fix in Phase 1 implementation (not yet actioned):** `shadcn`, `cn`,
`radix-ui`, `next-themes`, `sonner`, `tw-animate-css`, and `@fontsource-variable/geist`
were installed by the shadcn CLI under `dependencies` in `package.json`. The `shadcn`
CLI package itself is a dev-time tool and belongs in `devDependencies` — it should not
ship in the production bundle. This is a packaging cleanup, not a functional bug.

**`npm audit` status (accepted, tracked, not yet remediated):** 8 vulnerabilities (2
low, 6 moderate), all transitive, all in tooling rather than runtime app code:
- `exceljs` → old `uuid` (moderate). Fixing requires downgrading `exceljs` to 3.4.0,
  a breaking change — not worth taking for a non-exploitable-in-our-usage path.
- `shadcn` CLI's own dependency chain (`deepmerge`, `ts-morph` → `minimatch`) — dev-tool
  only, never ships to users.

Re-audit before each production release; see
[08-security-threat-checklist.md](./08-security-threat-checklist.md).

## What this audit does **not** cover

No application code (pages, business logic, Supabase schema) existed at audit time —
that is exactly what Phases 1–4 build, as sequenced in
[10-phase-plan.md](./10-phase-plan.md).
