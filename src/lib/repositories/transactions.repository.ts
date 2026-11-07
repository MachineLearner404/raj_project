import { supabase } from "@/lib/supabase/client";
import type { Database, PaymentMethod, PaymentType } from "@/lib/supabase/database.types";

type TransactionRow = Database["public"]["Tables"]["transactions"]["Row"];

export interface TransactionWithRelations extends TransactionRow {
  customers: Pick<Database["public"]["Tables"]["customers"]["Row"], "id" | "full_name" | "mobile">;
  jewellery_items: Database["public"]["Tables"]["jewellery_items"]["Row"][];
}

async function listByStatus(
  statuses: TransactionRow["status"][],
): Promise<TransactionWithRelations[]> {
  const { data, error } = await supabase
    .from("transactions")
    .select("*, customers(id, full_name, mobile), jewellery_items(*)")
    .in("status", statuses)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data as unknown as TransactionWithRelations[];
}

export const listActiveTransactions = () => listByStatus(["ACTIVE", "PARTIALLY_PAID"]);
export const listCompletedTransactions = () => listByStatus(["REDEEMED", "CANCELLED"]);

export async function getTransaction(id: string): Promise<TransactionWithRelations | null> {
  const { data, error } = await supabase
    .from("transactions")
    .select("*, customers(id, full_name, mobile), jewellery_items(*)")
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  return data as unknown as TransactionWithRelations | null;
}

export interface CreateTransactionInput {
  customerId: string;
  principalAmount: number;
  interestRatePercentPerMonth: number;
  issueDate: string; // YYYY-MM-DD
  tenureMonths: number;
  items: Array<{
    category: Database["public"]["Tables"]["jewellery_items"]["Row"]["category"];
    description: string;
    grossWeightGrams: number;
    netWeightGrams: number;
    stoneWeightGrams?: number;
    purityKarat: number;
    goldRateUsedPerGram: number;
    estimatedValue: number;
    conditionNotes?: string | null;
  }>;
}

// All transaction creation goes through the create_transaction() RPC —
// see supabase/migrations/20251106121000_rpc_functions.sql — never a
// direct insert; the transactions table has no INSERT policy.
export async function createTransaction(input: CreateTransactionInput): Promise<TransactionRow> {
  const { data, error } = await supabase.rpc("create_transaction", {
    p_customer_id: input.customerId,
    p_principal_amount: input.principalAmount,
    p_interest_rate_percent_per_month: input.interestRatePercentPerMonth,
    p_issue_date: input.issueDate,
    p_tenure_months: input.tenureMonths,
    p_items: input.items.map((item) => ({
      category: item.category,
      description: item.description,
      gross_weight_grams: item.grossWeightGrams,
      net_weight_grams: item.netWeightGrams,
      stone_weight_grams: item.stoneWeightGrams ?? 0,
      purity_karat: item.purityKarat,
      gold_rate_used_per_gram: item.goldRateUsedPerGram,
      estimated_value: item.estimatedValue,
      condition_notes: item.conditionNotes ?? null,
    })),
  });
  if (error) throw error;
  return data;
}

export interface CreateJewelleryLoanInput {
  customerId: string;
  principalAmount: number;
  interestType: "MONTHLY" | "YEARLY" | "FLAT";
  interestRate: number;
  flatInterestBasis?: number | null;
  depositDate: string;
  notes?: string | null;
  idempotencyKey: string;
  items: Array<{ jewelleryName: string; metalType: string; weightGrams: number; quantity: number; notes?: string | null }>;
}

export async function createJewelleryLoan(input: CreateJewelleryLoanInput): Promise<TransactionRow> {
  const { data, error } = await supabase.rpc("create_jewellery_loan", {
    p_customer_id: input.customerId, p_principal_amount: input.principalAmount,
    p_interest_type: input.interestType, p_interest_rate: input.interestRate,
    p_flat_interest_basis: input.flatInterestBasis ?? null, p_deposit_date: input.depositDate,
    p_notes: input.notes ?? null, p_idempotency_key: input.idempotencyKey,
    p_items: input.items.map(item => ({ jewellery_name: item.jewelleryName, metal_type: item.metalType, weight_grams: item.weightGrams, quantity: item.quantity, notes: item.notes ?? null })),
  });
  if (error) throw error;
  return data;
}

export interface RecordPaymentInput {
  transactionId: string;
  amount: number;
  paymentType: PaymentType;
  paymentMethod: PaymentMethod;
  paymentDate: string; // YYYY-MM-DD
}

// Goes through the record_payment() RPC — see createTransaction's
// comment above; the same "no direct writes" rule applies to payments.
export async function recordPayment(input: RecordPaymentInput): Promise<TransactionRow> {
  const { data, error } = await supabase.rpc("record_payment", {
    p_transaction_id: input.transactionId,
    p_amount: input.amount,
    p_payment_type: input.paymentType,
    p_payment_method: input.paymentMethod,
    p_payment_date: input.paymentDate,
  });
  if (error) throw error;
  return data;
}

export interface PostPaymentInput {
  transactionId: string; amount: number; paymentMethod: "CASH" | "UPI" | "BANK_TRANSFER" | "OTHER";
  paymentDate: string; idempotencyKey: string; referenceNumber?: string; remarks?: string; confirmJewelleryReturn?: boolean;
}

/** Final allocation, balance and redemption are calculated under a DB row lock. */
export async function postPayment(input: PostPaymentInput): Promise<TransactionRow> {
  const { data, error } = await supabase.rpc("post_payment", {
    p_transaction_id: input.transactionId, p_amount: input.amount, p_payment_method: input.paymentMethod,
    p_payment_date: input.paymentDate, p_idempotency_key: input.idempotencyKey,
    p_reference_number: input.referenceNumber ?? null, p_remarks: input.remarks ?? null,
    p_confirm_jewellery_return: input.confirmJewelleryReturn ?? false,
  });
  if (error) throw error;
  return data;
}

export async function cancelTransaction(
  transactionId: string,
  reason: string,
): Promise<TransactionRow> {
  const { data, error } = await supabase.rpc("cancel_transaction", {
    p_transaction_id: transactionId,
    p_reason: reason,
  });
  if (error) throw error;
  return data;
}
