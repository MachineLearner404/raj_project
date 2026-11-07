/**
 * Seeds a Supabase project with clearly-synthetic demo data: one demo
 * shop, three demo staff accounts (owner/manager/staff), a handful of
 * obviously-fictional customers, and two transactions (one left active,
 * one partially repaid) created through the REAL create_transaction() /
 * record_payment() RPCs — not raw table inserts — so this script also
 * doubles as an end-to-end smoke test of the schema, RLS policies, and
 * RPC functions against a real (or local) Supabase project.
 *
 * NEVER put real customer data in this file. Every name, phone number,
 * and ID proof number below is synthetic and obviously so on purpose.
 *
 * Usage: see supabase/README.md. In short, with .env filled in:
 *   ALLOW_SEED=true npm run seed:demo
 *
 * This script uses the service-role key — by design, it must NEVER run
 * in a browser context. It only runs here, as a local/CI Node script.
 */

import { createClient } from "@supabase/supabase-js";
import type { Database } from "../../src/lib/supabase/database.types.ts";

// Reuses the same VITE_-prefixed vars the app itself uses (see
// .env.example) rather than duplicating them under different names —
// one .env, one source of truth for which project you're pointed at.
const SUPABASE_URL = process.env.VITE_SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.VITE_SUPABASE_ANON_KEY;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SERVICE_ROLE_KEY) {
  console.error(
    "Missing VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY and/or SUPABASE_SERVICE_ROLE_KEY.\n" +
      "Copy .env.example to .env, fill in your project's values, then run:\n" +
      "  ALLOW_SEED=true npm run seed:demo",
  );
  process.exit(1);
}

if (process.env.ALLOW_SEED !== "true") {
  console.error(
    "Refusing to run: this script writes rows to whatever project SUPABASE_URL points at.\n" +
      "Re-run with ALLOW_SEED=true once you've confirmed that's a local/dev/staging project,\n" +
      "never production.\n\n" +
      "  ALLOW_SEED=true npm run seed:demo",
  );
  process.exit(1);
}

const admin = createClient<Database>(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const DEMO_PASSWORD = "DemoPass!12345"; // local/dev seed data only — never a real account

interface DemoUser {
  email: string;
  role: Database["public"]["Tables"]["profiles"]["Row"]["role"];
  fullName: string;
  id?: string;
}

const demoUsers: DemoUser[] = [
  { email: "owner@demo-shop.seed.local", role: "owner", fullName: "Demo Owner" },
  { email: "manager@demo-shop.seed.local", role: "manager", fullName: "Demo Manager" },
  { email: "staff@demo-shop.seed.local", role: "staff", fullName: "Demo Staff" },
];

async function signInAs(email: string) {
  const client = createClient<Database>(SUPABASE_URL!, SUPABASE_ANON_KEY!, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { error } = await client.auth.signInWithPassword({ email, password: DEMO_PASSWORD });
  if (error) throw new Error(`Sign-in failed for ${email}: ${error.message}`);
  return client;
}

async function main() {
  console.log("Seeding demo data...\n");

  // ------------------------------------------------------------------
  // 1. Shop (service role — shop provisioning is an admin/onboarding
  //    operation, not something a normal authenticated user does; see
  //    docs/02-database-schema-erd.md's "shops" RLS note).
  // ------------------------------------------------------------------
  const { data: shop, error: shopError } = await admin
    .from("shops")
    .insert({ name: "Demo Jewellery Shop (seed data)", address: "Demo address, not a real location" })
    .select()
    .single();
  if (shopError) throw shopError;
  console.log(`Created shop: ${shop.name} (${shop.id})`);

  // ------------------------------------------------------------------
  // 2. Auth users + profiles. Creating the FIRST owner profile for a
  //    brand-new shop is necessarily a service-role/admin step — the
  //    profiles_insert_owner_only RLS policy requires an existing owner,
  //    which doesn't exist yet. A real "sign up a new shop" flow needs
  //    the same kind of trusted bootstrap step (e.g. an Edge Function),
  //    which is not built yet — flagged as a Phase 3+ gap.
  // ------------------------------------------------------------------
  for (const user of demoUsers) {
    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email: user.email,
      password: DEMO_PASSWORD,
      email_confirm: true,
    });
    if (createError) throw createError;
    user.id = created.user.id;

    const { error: profileError } = await admin.from("profiles").insert({
      id: user.id,
      shop_id: shop.id,
      full_name: user.fullName,
      role: user.role,
    });
    if (profileError) throw profileError;
    console.log(`Created ${user.role}: ${user.email}`);
  }

  const owner = demoUsers.find((u) => u.role === "owner")!;
  const manager = demoUsers.find((u) => u.role === "manager")!;
  const staff = demoUsers.find((u) => u.role === "staff")!;

  // ------------------------------------------------------------------
  // 3. app_settings — as the owner, through the real owner-only RLS
  //    policy (not a service-role bypass), so this doubles as a live
  //    check that the policy actually admits the owner.
  // ------------------------------------------------------------------
  const ownerClient = await signInAs(owner.email);
  const { error: settingsError } = await ownerClient
    .from("app_settings")
    .insert({ shop_id: shop.id });
  if (settingsError) throw settingsError;
  console.log("Created app_settings for the demo shop");

  // ------------------------------------------------------------------
  // 4. Customers — as staff, through the real customers INSERT policy.
  //    Every name/number/ID below is synthetic placeholder data.
  // ------------------------------------------------------------------
  const staffClient = await signInAs(staff.email);
  const customerSeeds = [
    {
      full_name: "Seed Customer Alpha",
      mobile: "9000000001",
      address: "Synthetic address 1, not a real location",
      id_proof_type: "AADHAAR" as const,
      id_proof_number: "000000000001",
    },
    {
      full_name: "Seed Customer Beta",
      mobile: "9000000002",
      address: "Synthetic address 2, not a real location",
      id_proof_type: "PAN" as const,
      id_proof_number: "ZZZZZ0000Z",
    },
  ];

  const customerIds: string[] = [];
  for (const seed of customerSeeds) {
    const { data, error } = await staffClient
      .from("customers")
      .insert({
        shop_id: shop.id,
        customer_code: "", // trigger-assigned; see database.types.ts
        mobile_normalized: "", // trigger-computed; see database.types.ts
        created_by: staff.id!,
        ...seed,
      })
      .select()
      .single();
    if (error) throw error;
    customerIds.push(data.id);
    console.log(`Created customer: ${data.full_name} (${data.customer_code})`);
  }

  // ------------------------------------------------------------------
  // 5. Transactions — as manager, through the real create_transaction()
  //    RPC (never a raw insert; see transactions.repository.ts).
  // ------------------------------------------------------------------
  const managerClient = await signInAs(manager.email);

  const { data: txn1, error: txn1Error } = await managerClient.rpc("create_transaction", {
    p_customer_id: customerIds[0],
    p_principal_amount: 50000,
    p_interest_rate_percent_per_month: 1.5,
    p_issue_date: new Date().toISOString().slice(0, 10),
    p_tenure_months: 12,
    p_items: [
      {
        category: "RING",
        description: "Seed data: 22K gold ring",
        gross_weight_grams: 8,
        net_weight_grams: 7.5,
        purity_karat: 22,
        gold_rate_used_per_gram: 6450,
        estimated_value: 48000,
      },
    ],
  });
  if (txn1Error) throw txn1Error;
  console.log(`Created transaction: ${txn1.pledge_code} (left ACTIVE)`);

  const { data: txn2, error: txn2Error } = await managerClient.rpc("create_transaction", {
    p_customer_id: customerIds[1],
    p_principal_amount: 100000,
    p_interest_rate_percent_per_month: 1.5,
    p_issue_date: new Date().toISOString().slice(0, 10),
    p_tenure_months: 12,
    p_items: [
      {
        category: "NECKLACE",
        description: "Seed data: 22K gold necklace",
        gross_weight_grams: 20,
        net_weight_grams: 19,
        purity_karat: 22,
        gold_rate_used_per_gram: 6450,
        estimated_value: 120000,
      },
    ],
  });
  if (txn2Error) throw txn2Error;
  console.log(`Created transaction: ${txn2.pledge_code}`);

  // ------------------------------------------------------------------
  // 6. One payment — as staff, through the real record_payment() RPC —
  //    leaves txn2 PARTIALLY_PAID so the seeded data shows both states.
  // ------------------------------------------------------------------
  const { data: paid, error: paymentError } = await staffClient.rpc("record_payment", {
    p_transaction_id: txn2.id,
    p_amount: 40000,
    p_payment_type: "PARTIAL_PRINCIPAL",
    p_payment_method: "CASH",
    p_payment_date: new Date().toISOString().slice(0, 10),
  });
  if (paymentError) throw paymentError;
  console.log(`Recorded a partial payment on ${txn2.pledge_code} -> status ${paid.status}`);

  console.log("\nDone. Demo sign-in credentials (local/dev only):");
  for (const user of demoUsers) {
    console.log(`  ${user.role.padEnd(8)} ${user.email}  /  ${DEMO_PASSWORD}`);
  }
}

main().catch((error) => {
  console.error("\nSeed failed:", error);
  process.exit(1);
});
