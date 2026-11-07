import { supabase } from "@/lib/supabase/client";
import type { Database } from "@/lib/supabase/database.types";

type AppSettingsRow = Database["public"]["Tables"]["app_settings"]["Row"];
type AppSettingsUpdate = Database["public"]["Tables"]["app_settings"]["Update"];

export async function getShopSettings(shopId: string): Promise<AppSettingsRow | null> {
  const { data, error } = await supabase
    .from("app_settings")
    .select("*")
    .eq("shop_id", shopId)
    .maybeSingle();
  if (error) throw error;
  return data;
}

// owner-only per app_settings_update_owner_only — a non-owner caller gets
// a clean "0 rows updated" rather than an exception (see
// supabase/tests/rls_and_constraints.test.sql for why UPDATE under RLS
// behaves that way), so callers should check the returned row is non-null.
export async function updateShopSettings(
  shopId: string,
  patch: AppSettingsUpdate,
): Promise<AppSettingsRow | null> {
  const { data, error } = await supabase
    .from("app_settings")
    .update(patch)
    .eq("shop_id", shopId)
    .select()
    .maybeSingle();
  if (error) throw error;
  return data;
}
