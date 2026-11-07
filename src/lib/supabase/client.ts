import { createClient } from "@supabase/supabase-js";
import type { Database } from "./database.types";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    "Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY. Copy .env.example to .env and fill in your project values.",
  );
}

// Only the public anon key is ever read here — RLS (see
// supabase/migrations/20251106121100_rls_policies.sql) is the real access
// boundary, not this key. SUPABASE_SERVICE_ROLE_KEY must never be
// imported from anywhere under src/ — see supabase/seed/seed-demo.ts for
// the one place it is used (a local/CI-only Node script).
export const supabase = createClient<Database>(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  },
});
