#!/usr/bin/env bash
# Runs the real migrations + RLS/constraint test suite against a scratch
# local Postgres database, then drops it. Requires a local Postgres
# server (e.g. `brew install postgresql@15 && brew services start
# postgresql@15`) — this does NOT require Docker or the Supabase CLI,
# since it talks to plain Postgres directly, not the full Supabase stack
# (no GoTrue/PostgREST/Storage API — see _local_pg_stub.sql's header for
# exactly what is and isn't stood in for).
set -euo pipefail

DB_NAME="jewellery_loan_rls_test"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS_DIR="$SCRIPT_DIR/../migrations"

echo "==> Recreating scratch database: $DB_NAME"
dropdb --if-exists "$DB_NAME"
createdb "$DB_NAME"

cleanup() {
  echo "==> Dropping scratch database: $DB_NAME"
  dropdb --if-exists "$DB_NAME"
}
trap cleanup EXIT

echo "==> Applying local auth/storage stub (test-only, never run this against a real Supabase project)"
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/_local_pg_stub.sql" > /dev/null

echo "==> Applying migrations"
for f in "$MIGRATIONS_DIR"/*.sql; do
  echo "    $(basename "$f")"
  psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$f" > /dev/null
done

echo "==> Running RLS/constraint, auth/onboarding/permission, historical settlement and jewellery photo tests"
# These deliberately share one psql session: Phase 3 tests, the historical
# settlement suite and the jewellery photo suite all reuse the temporary
# fixture table created by the baseline RLS suite, so the order below matters.
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/rls_and_constraints.test.sql" \
  -f "$SCRIPT_DIR/auth_and_permissions.test.sql" \
  -f "$SCRIPT_DIR/historical_settlement.test.sql" \
  -f "$SCRIPT_DIR/jewellery_item_photos.test.sql"

echo "==> All tests passed."
