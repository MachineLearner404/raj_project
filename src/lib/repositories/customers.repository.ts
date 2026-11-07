import { supabase } from "@/lib/supabase/client";
import type { Database } from "@/lib/supabase/database.types";

type CustomerRow = Database["public"]["Tables"]["customers"]["Row"];
type CustomerInsert = Database["public"]["Tables"]["customers"]["Insert"];

// Omits columns the database fills in itself:
// - id, created_at, updated_at: DB defaults.
// - customer_code: assigned by the customers_assign_code trigger.
// - mobile_normalized: computed by the customers_normalize_mobile trigger.
export type CreateCustomerInput = Omit<
  CustomerInsert,
  "id" | "created_at" | "updated_at" | "customer_code" | "mobile_normalized"
>;

export async function listCustomers(search?: string, page = 0, pageSize = 25): Promise<CustomerRow[]> {
  let query = supabase
    .from("customers")
    .select("*")
    .eq("is_active", true)
    .order("created_at", { ascending: false })
    .range(page * pageSize, page * pageSize + pageSize - 1);

  if (search?.trim()) {
    const term = search.trim().replace(/[%_,]/g, "");
    const mobile = normalizeMobile(term);
    query = query.or(`full_name.ilike.%${term}%,customer_code.ilike.%${term}%,mobile_normalized.ilike.%${mobile}%`);
  }

  const { data, error } = await query;
  if (error) throw error;
  return data;
}

export async function getCustomer(id: string): Promise<CustomerRow | null> {
  const { data, error } = await supabase
    .from("customers")
    .select("*")
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  return data;
}

export async function createCustomer(input: CreateCustomerInput): Promise<CustomerRow> {
  const { data, error } = await supabase
    .from("customers")
    .insert(input)
    .select()
    .single();
  if (error) throw error;
  return data;
}

export function normalizeMobile(value: string) {
  return value.replace(/\D/g, "").slice(-10);
}

export async function findPossibleDuplicates(fullName: string, mobile: string): Promise<CustomerRow[]> {
  const normalized = normalizeMobile(mobile);
  const name = fullName.trim().replace(/[%_,]/g, "");
  const { data, error } = await supabase
    .from("customers")
    .select("*")
    .or(`mobile_normalized.eq.${normalized},full_name.ilike.%${name}%`)
    .order("created_at", { ascending: false })
    .limit(10);
  if (error) throw error;
  return data;
}

export async function uploadCustomerPhoto(customer: CustomerRow, file: File): Promise<CustomerRow> {
  const extension = file.type === "image/png" ? "png" : file.type === "image/webp" ? "webp" : "jpg";
  const path = `${customer.shop_id}/${customer.id}/profile.${extension}`;
  const { error: uploadError } = await supabase.storage.from("customer-photos").upload(path, file, {
    contentType: file.type,
    upsert: true,
  });
  if (uploadError) throw uploadError;
  const { data, error } = await supabase.rpc("set_customer_photo", { p_customer_id: customer.id, p_photo_path: path });
  if (error) throw error;
  return data;
}

export async function getCustomerPhotoUrl(path: string) {
  const { data, error } = await supabase.storage.from("customer-photos").createSignedUrl(path, 60 * 10);
  if (error) throw error;
  return data.signedUrl;
}

export async function archiveCustomer(id: string) {
  const { data, error } = await supabase.from("customers").update({ is_active: false }).eq("id", id).select().single();
  if (error) throw error;
  return data;
}
