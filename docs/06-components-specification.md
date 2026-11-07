# Reusable Components Specification

Covers the shared, business-aware components (`src/components/shared/`) and layout
components (`src/components/layout/`). `src/components/ui/*` (shadcn primitives —
Button, Input, Table, Dialog, Sheet, etc.) are vendor components used *by* these and
are not separately specified here beyond noting which ones each wraps.

Status column reflects what exists in the repository today (see the Phase 0/1
completion report shared earlier in this conversation) — this document specifies
the **target** behavior for Phase 1 implementation, regardless of current status.

---

## Layout components

### `Sidebar` (desktop, `≥ md` breakpoint)

**Wraps:** plain `nav` + `NavLink` (react-router-dom), themed via sidebar CSS
tokens in `src/index.css`.

**Behavior:** fixed-width (16rem) column, charcoal background, lists all 9 nav
items (from the shared `navItems` config in `src/components/layout/nav-items.ts`)
with Lucide icons; the active route is highlighted (champagne-gold icon + lighter
background) via `NavLink`'s `isActive` render prop — this must reflect the **real**
current route once routing is wired, not a hardcoded highlight.

**Accessibility:** each link has visible focus state (inherited from
`focus-visible` ring tokens); icons are decorative (`aria-hidden` via Lucide
default) since link text is always present alongside them.

### `MobileNav` (compact, `< md` breakpoint)

**Wraps:** shadcn `Sheet` (slide-in drawer) triggered by a `Button` with a Lucide
`Menu` icon.

**Behavior:** same `navItems` list as `Sidebar`; selecting an item navigates **and**
closes the sheet (`onClick={() => setOpen(false)}`) — a nav item that leaves the
drawer open after navigating is a bug, not acceptable behavior.

**Accessibility:** `Sheet` (Radix-based) provides focus trap and `Esc`-to-close for
free; trigger button has an `aria-label` ("Open navigation menu") since it has no
visible text label.

### `Topbar`

**Behavior:** shows the current page's title, derived from `navItems` by matching
the current route (not a hardcoded per-page string, so it can never drift out of
sync with the sidebar's own labels); hosts the `MobileNav` trigger on small screens
only.

### `AppShell`

**Behavior:** the route layout element — renders `Sidebar` + a right column of
`Topbar` + `DemoModeBanner` + `<Outlet />` (the active page). This is the single
place that composes the whole app frame; individual pages never re-implement
navigation chrome.

### `DemoModeBanner`

**Behavior:** a persistent, non-dismissible strip stating the app is in demo mode
and nothing entered is saved — present on every page while any page still uses demo
data (i.e., through the end of Phase 1). **Must be removed (or made conditional on
an actual "is this environment connected to real data" check) once Phase 2 wires
real persistence** — leaving it up after real data is live would be actively
misleading, not just unnecessary.

---

## Shared business components (target spec — build order for Phase 1 implementation)

### `PageHeader`

**Props:** `title: string`, `description?: string`, `actions?: ReactNode`.

**Behavior:** renders a consistent heading block at the top of every page body
(title + optional one-line description + optional right-aligned action slot, e.g. an
"Add Customer" button). Every one of the 9 pages uses this instead of a bespoke
`<h1>` — consistency is the entire point of this component.

### `MetricCard`

**Props:** matches the `DashboardMetric` type (`label`, `value`, `helpText`,
`trend?: "up" | "down" | "flat"`).

**Behavior:** a `Card` showing a label, a large value, a help line, and (if `trend`
given) a small colored up/down indicator (green/red/neutral — must remain legible
against both light and dark theme tokens, not hardcoded hex). Used on Dashboard;
reusable anywhere a single headline number needs showing (e.g., Reports).

### `DataTable`

**Props:** generic `columns: Column<T>[]`, `rows: T[]`, optional `onRowClick`,
optional per-row `actions` render slot, optional `isLoading`, optional `emptyState`
override.

**Behavior:** thin, typed wrapper around shadcn `Table` — handles the loading
(renders `LoadingState` skeleton rows), empty (renders `EmptyState` or the caller's
override), and populated states consistently, so no page hand-rolls its own
loading/empty branching around a raw `<table>`. **This is the single most
reused component in the app** — Customer Records, Active Transactions, Completed
Transactions, and (Phase 2+) report tables all go through it.

### `StatusBadge`

**Props:** `status: LoanStatus` (`"active" | "overdue" | "completed" | "auctioned"`
— matches the domain type in `src/types/domain.ts`, which must stay in sync with the
`loans.status` enum in [02-database-schema-erd.md](./02-database-schema-erd.md)).

**Behavior:** maps each status to a fixed label + color via the shadcn `Badge`
variant system — `active` neutral/default, `overdue` warning/destructive-leaning,
`completed` success/muted-positive, `auctioned` destructive. The mapping lives in
exactly one place so a status color never has to be remembered/re-decided per page.

### `SearchBar`

**Props:** `value: string`, `onChange: (v: string) => void`, `placeholder?: string`.

**Behavior:** a controlled `Input` with a leading Lucide `Search` icon and a clear
("×") affordance when non-empty. In Phase 1, every page that uses it performs a
**real** client-side filter against demo data — this is explicitly one of the "must
actually work" interactions called out in the Phase 1 requirements, not a decorative
input.

### `EmptyState`

**Props:** `title: string`, `description?: string`, `action?: ReactNode`, optional
`icon`.

**Behavior:** centered placeholder for an empty list/table (e.g., "No customers yet"
+ an "Add Customer" button as `action`). Used by `DataTable`'s default empty
rendering and directly by pages like Reports' backup-jobs list.

### `LoadingState`

**Props:** `rows?: number` (default 5), or a `variant: "table" | "card"`.

**Behavior:** shadcn `Skeleton`-based placeholder matching the shape of what's
loading (table-row skeletons for `DataTable`, card skeletons for `MetricCard`
grids) — the goal is that the loading state never visually "pops" into a
differently-shaped final layout.

### `ErrorState`

**Props:** `message?: string`, `onRetry?: () => void`.

**Behavior:** shown when a data fetch fails (Phase 2+ only — Phase 1 demo data
cannot fail); a clear message plus a "Retry" button when `onRetry` is given. Must
never show a raw error object/stack trace to the user — technical detail, if any,
is logged to the console/monitoring, not rendered.

### `ConfirmDialog`

**Props:** `trigger: ReactNode`, `title`, `description`, `confirmLabel?`,
`destructive?: boolean`, `onConfirm: () => void | Promise<void>`.

**Behavior:** wraps shadcn `AlertDialog`; used anywhere an action is one-way or
high-consequence — the clearest Phase 1 example named in
[05-pages-specification.md](./05-pages-specification.md) is confirming a full loan
closure before calling `record_payment()`/`close_loan()`, since that both releases
jewellery and is not reversible through normal UI. `destructive` styles the confirm
button via the destructive Badge/Button variant tokens.

### Toast (via shadcn `sonner` wrapper, `src/components/ui/sonner.tsx`)

**Behavior:** mounted once at the app root (`<Toaster />` alongside
`QueryClientProvider`/router in `App.tsx`); used for transient confirmations (Phase
1: "Added (demo) — not saved to a database yet.") and, in Phase 2+, for
success/error feedback on real mutations. Not used for anything the user must be
able to re-read later — persistent information belongs on the page, not in a toast
that disappears.

---

## Cross-cutting rules for all shared components

- **No component in `components/shared` imports from `features/*`** — dependencies
  only flow one direction (features depend on shared, never the reverse), so shared
  components stay reusable and testable in isolation.
- **Every component here takes typed props matching `src/types/domain.ts` or plain
  primitives** — none reach into `src/data/demo-data.ts` directly. Pages pass demo
  data in via props in Phase 1; swapping to real Supabase-backed data in Phase 2+ is
  then a change to the *pages*, not to these components.
- **Theming**: components use only the CSS variable tokens defined in
  `src/index.css` (`background`, `foreground`, `primary`, `sidebar-*`, etc.) — never
  a hardcoded hex color — so the warm-white/champagne-gold/charcoal design system
  stays consistent and themeable from one file.
