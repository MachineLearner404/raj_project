# Phase 13 security and reliability review

This is an engineering checklist, not a security certification.

| Area | Status | Evidence / action |
| --- | --- | --- |
| RLS on business tables | Pass | Local PostgreSQL suite verifies shop-scoped reads/writes and no direct financial writes. |
| Storage photo isolation | Pass | Storage tests allow only the active shop folder; photo display uses 10-minute signed URLs. |
| Tenant isolation | Pass | `current_shop_id()` is server-side and active-shop switching validates `shop_memberships`; cross-shop reads are tested. |
| Client secrets | Pass | Browser client reads only Vite URL and public key. `.env*` is ignored. Service role is absent from `src/`. |
| Auth/password reset | Partial | UI uses Supabase Auth reset flow; project Dashboard settings (email confirmation, MFA, leaked-password protection, redirect allow-list) require owner verification. |
| Roles | Pass | RLS/RPC checks role server-side. UI guards are convenience only. |
| Input/XSS | Pass | Database constraints/RPC validation back client validation; no `dangerouslySetInnerHTML` use found. |
| Abuse protection | Partial | PIN has server rate limiting. Auth throttling, CAPTCHA, and edge/WAF limits must be configured in Supabase/hosting. |
| Audit trail | Pass | Customers/settings/transactions are audited; payment inserts and payment reversals now generate append-only audit events. |
| Financial immutability | Pass | Direct UPDATE/DELETE of payments is RLS-blocked. Reversal is owner-only, reasoned, idempotent, and preserves the original payment. |
| Payment reliability | Pass | Posting uses a transaction row lock and idempotency key; local DB tests cover retries and allocation. |
| HTTPS/headers | Fail / deployment action | Vite app has no hosting configuration. Enforce HTTPS, CSP, HSTS, frame-ancestors, nosniff, and referrer policy at the hosting/CDN layer before release. |
| Dependency audit | Fail / action required | `npm audit --omit=dev --audit-level=high` found two moderate `uuid` advisories through `exceljs`. The offered automatic fix is breaking, so it was not applied. |
| Privacy logging | Partial | App code avoids logging customer/payment data. Review Supabase/hosting logs and disable verbose request-body logging before release. |

## Required release actions

1. Enable Supabase Auth leaked-password protection and configure allowed password-reset redirect URLs.
2. Require MFA for owner accounts where the chosen Supabase plan supports it.
3. Configure authentication rate limits/CAPTCHA and deployment security headers.
4. Upgrade or replace the `exceljs` dependency after regression testing; do not use the offered forced downgrade blindly.
5. Deploy the Phase 13 migration and frontend, then rerun the database advisors. Address remaining mutable-search-path warnings in a dedicated migration.
