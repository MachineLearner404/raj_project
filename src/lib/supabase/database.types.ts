/**
 * Hand-maintained to mirror what `supabase gen types typescript` would
 * produce from supabase/migrations/*.sql, so swapping to a generated file
 * later is a drop-in replacement, not a rewrite. Keep this in sync with
 * the migrations by hand until a real Supabase project exists to
 * generate it from directly — see supabase/README.md.
 *
 * Row/Insert/Update shapes follow literal Postgres column constraints
 * (NOT NULL + no DEFAULT = required on Insert), even where a trigger
 * fills a column server-side (e.g. customer_code, pledge_code,
 * mobile_normalized, shop_id on child tables) — real codegen has no way
 * to know about trigger behavior either. The repository layer in
 * src/lib/repositories/ exposes friendlier input types that omit those
 * trigger-filled columns; see its comments for which ones and why.
 *
 * transactions, jewellery_items, payments, interest_events and
 * audit_logs still carry full Insert/Update shapes here (real codegen
 * would too — it has no way to know "only call this via an RPC"), but
 * every RLS policy denies direct writes to them; the repository layer
 * never calls `.insert()`/`.update()` on these, only the
 * create_transaction / record_payment / cancel_transaction RPCs. See
 * supabase/tests/rls_and_constraints.test.sql sections 6 and 11 for the
 * executed proof that a direct write is actually blocked.
 */

export type TransactionStatus = "ACTIVE" | "PARTIALLY_PAID" | "REDEEMED" | "CANCELLED";
export type ProfileRole = "owner" | "manager" | "staff";
export type IdProofType = "AADHAAR" | "PAN" | "VOTER_ID" | "DRIVING_LICENCE";
export type JewelleryCategory =
  | "NECKLACE"
  | "RING"
  | "BANGLE"
  | "COIN"
  | "CHAIN"
  | "EARRINGS"
  | "OTHER";
export type PaymentType = "INTEREST" | "PARTIAL_PRINCIPAL" | "FULL_CLOSURE";
export type PaymentMethod = "CASH" | "UPI" | "BANK_TRANSFER" | "OTHER";
export type InterestEventType = "ACCRUAL" | "SETTLEMENT" | "WAIVER";
export type InterestRoundingPolicy = "round_up_partial_month" | "round_down_partial_month";
export type AuditAction = "INSERT" | "UPDATE" | "DELETE";
export type ClosureType = "REDEEMED" | "CANCELLED";

/** `calculate_live_settlement` read model. Money arrives as a numeric string
 * over PostgREST, exactly like the transaction columns it is derived from. */
export interface LiveSettlementJson {
  transaction_id: string;
  calculation_date: string;
  original_principal: string;
  previous_principal_repayments: string;
  remaining_principal: string;
  total_interest_accrued: string;
  previous_interest_paid: string;
  outstanding_interest: string;
  total_previous_payments: string;
  amount_payable_today: string;
  redeemed: boolean;
}

export interface Database {
  public: {
    Tables: {
      shops: {
        Row: {
          id: string;
          name: string;
          address: string | null;
          gstin: string | null;
          phone: string | null;
          next_customer_seq: number;
          next_pledge_seq: number;
          created_at: string;
          updated_at: string;
          onboarding_completed_at: string | null;
        };
        Insert: {
          id?: string;
          name: string;
          address?: string | null;
          gstin?: string | null;
          phone?: string | null;
          next_customer_seq?: number;
          next_pledge_seq?: number;
          created_at?: string;
          updated_at?: string;
          onboarding_completed_at?: string | null;
        };
        Update: Partial<Database["public"]["Tables"]["shops"]["Insert"]>;
        Relationships: [];
      };

      profiles: {
        Row: {
          id: string;
          shop_id: string;
          active_shop_id: string;
          full_name: string;
          role: ProfileRole;
          phone: string | null;
          is_active: boolean;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id: string;
          shop_id: string;
          active_shop_id?: string;
          full_name: string;
          role: ProfileRole;
          phone?: string | null;
          is_active?: boolean;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["profiles"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "profiles_shop_id_fkey";
            columns: ["shop_id"];
            isOneToOne: false;
            referencedRelation: "shops";
            referencedColumns: ["id"];
          },
        ];
      };

      shop_memberships: {
        Row: { id: string; shop_id: string; user_id: string; role: ProfileRole; is_active: boolean; created_at: string; updated_at: string };
        Insert: { id?: string; shop_id: string; user_id: string; role: ProfileRole; is_active?: boolean; created_at?: string; updated_at?: string };
        Update: Partial<Database["public"]["Tables"]["shop_memberships"]["Insert"]>;
        Relationships: [];
      };

      customers: {
        Row: {
          id: string;
          shop_id: string;
          customer_code: string;
          full_name: string;
          mobile: string;
          mobile_normalized: string;
          alternate_mobile: string | null;
          address: string;
          id_proof_type: IdProofType;
          id_proof_number: string;
          photo_path: string | null;
          notes: string | null;
          is_active: boolean;
          created_by: string;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id?: string;
          shop_id: string;
          // Trigger-assigned when omitted — see file header comment.
          customer_code?: string;
          full_name: string;
          mobile: string;
          // Trigger-computed from `mobile` — see file header comment.
          mobile_normalized?: string;
          alternate_mobile?: string | null;
          address: string;
          id_proof_type: IdProofType;
          id_proof_number: string;
          photo_path?: string | null;
          notes?: string | null;
          is_active?: boolean;
          created_by: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["customers"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "customers_shop_id_fkey";
            columns: ["shop_id"];
            isOneToOne: false;
            referencedRelation: "shops";
            referencedColumns: ["id"];
          },
        ];
      };

      transactions: {
        Row: {
          id: string;
          shop_id: string;
          pledge_code: string;
          customer_id: string;
          principal_amount: string; // numeric(14,2) comes back as string over PostgREST
          interest_rate_percent_per_month: string;
          interest_type: "MONTHLY" | "YEARLY" | "FLAT";
          flat_interest_basis: string | null;
          flat_interest_basis_type: "AMOUNT" | "PERCENT_OF_ORIGINAL";
          idempotency_key: string | null;
          accrued_interest: string;
          interest_periods_settled: number;
          jewellery_returned_at: string | null;
          jewellery_returned_by: string | null;
          outstanding_principal: string;
          interest_settled_through: string;
          issue_date: string;
          is_historical: boolean;
          tenure_months: number;
          due_date: string;
          status: TransactionStatus;
          closure_type: ClosureType | null;
          closed_at: string | null;
          notes: string | null;
          created_by: string;
          created_at: string;
          updated_at: string;
        };
        // No RLS INSERT/UPDATE policy exists for this table — all writes
        // go through the create_transaction / record_payment /
        // cancel_transaction RPCs (see transactions.repository.ts). This
        // shape exists only because PostgREST's typing requires one; it
        // is never used to call `.insert()`/`.update()` directly.
        Insert: {
          id?: string;
          shop_id: string;
          pledge_code?: string;
          customer_id: string;
          principal_amount: number;
          interest_rate_percent_per_month: number;
          interest_type?: "MONTHLY" | "YEARLY" | "FLAT";
          flat_interest_basis?: number | null;
          flat_interest_basis_type?: "AMOUNT" | "PERCENT_OF_ORIGINAL";
          idempotency_key?: string | null;
          accrued_interest?: number;
          interest_periods_settled?: number;
          jewellery_returned_at?: string | null;
          jewellery_returned_by?: string | null;
          outstanding_principal: number;
          interest_settled_through: string;
          issue_date: string;
          is_historical?: boolean;
          tenure_months: number;
          due_date: string;
          status?: TransactionStatus;
          closure_type?: ClosureType | null;
          closed_at?: string | null;
          notes?: string | null;
          created_by: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["transactions"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "transactions_customer_id_fkey";
            columns: ["customer_id"];
            isOneToOne: false;
            referencedRelation: "customers";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "transactions_shop_id_fkey";
            columns: ["shop_id"];
            isOneToOne: false;
            referencedRelation: "shops";
            referencedColumns: ["id"];
          },
        ];
      };

      jewellery_items: {
        Row: {
          id: string;
          shop_id: string;
          transaction_id: string;
          category: JewelleryCategory;
          description: string;
          gross_weight_grams: string;
          net_weight_grams: string;
          stone_weight_grams: string;
          purity_karat: number;
          gold_rate_used_per_gram: string;
          estimated_value: string;
          condition_notes: string | null;
          jewellery_name: string | null;
          metal_type: string;
          quantity: number;
          photo_path: string | null;
          created_at: string;
        };
        // Written only via create_transaction() — see transactions above.
        Insert: {
          id?: string;
          shop_id?: string;
          transaction_id: string;
          category: JewelleryCategory;
          description: string;
          gross_weight_grams: number;
          net_weight_grams: number;
          stone_weight_grams?: number;
          purity_karat: number;
          gold_rate_used_per_gram: number;
          estimated_value: number;
          condition_notes?: string | null;
          jewellery_name?: string | null;
          metal_type?: string;
          quantity?: number;
          photo_path?: string | null;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["jewellery_items"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "jewellery_items_transaction_id_fkey";
            columns: ["transaction_id"];
            isOneToOne: false;
            referencedRelation: "transactions";
            referencedColumns: ["id"];
          },
        ];
      };

      payments: {
        Row: {
          id: string;
          shop_id: string;
          transaction_id: string;
          amount: string;
          payment_type: PaymentType;
          payment_method: PaymentMethod;
          payment_date: string;
          receipt_number: string | null;
          received_by: string;
          notes: string | null;
          reference_number: string | null;
          interest_amount: string;
          principal_amount: string;
          idempotency_key: string | null;
          created_at: string;
        };
        // Written only via record_payment(); append-only, never updated.
        Insert: {
          id?: string;
          shop_id?: string;
          transaction_id: string;
          amount: number;
          payment_type: PaymentType;
          payment_method: PaymentMethod;
          payment_date: string;
          receipt_number?: string | null;
          received_by: string;
          notes?: string | null;
          reference_number?: string | null;
          interest_amount?: number;
          principal_amount?: number;
          idempotency_key?: string | null;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["payments"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "payments_transaction_id_fkey";
            columns: ["transaction_id"];
            isOneToOne: false;
            referencedRelation: "transactions";
            referencedColumns: ["id"];
          },
        ];
      };

      payment_reversals: {
        Row: { id: string; shop_id: string; original_payment_id: string; transaction_id: string; reason: string; reversed_by: string; reversed_at: string; idempotency_key: string };
        Insert: { id?: string; shop_id: string; original_payment_id: string; transaction_id: string; reason: string; reversed_by: string; reversed_at?: string; idempotency_key: string };
        Update: never;
        Relationships: [];
      };

      interest_events: {
        Row: {
          id: string;
          shop_id: string;
          transaction_id: string;
          event_type: InterestEventType;
          amount: string;
          principal_balance_after: string;
          interest_due_after: string;
          event_date: string;
          related_payment_id: string | null;
          created_by: string;
          created_at: string;
        };
        // Written only via record_payment(); append-only, never updated.
        Insert: {
          id?: string;
          shop_id?: string;
          transaction_id: string;
          event_type: InterestEventType;
          amount: number;
          principal_balance_after: number;
          interest_due_after: number;
          event_date: string;
          related_payment_id?: string | null;
          created_by: string;
          created_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["interest_events"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "interest_events_transaction_id_fkey";
            columns: ["transaction_id"];
            isOneToOne: false;
            referencedRelation: "transactions";
            referencedColumns: ["id"];
          },
        ];
      };

      audit_logs: {
        Row: {
          id: number;
          shop_id: string;
          table_name: string;
          record_id: string;
          action: AuditAction;
          changed_by: string | null;
          changed_at: string;
          old_values: Record<string, unknown> | null;
          new_values: Record<string, unknown> | null;
        };
        // Written only by the write_audit_log() trigger.
        Insert: {
          id?: number;
          shop_id: string;
          table_name: string;
          record_id: string;
          action: AuditAction;
          changed_by?: string | null;
          changed_at?: string;
          old_values?: Record<string, unknown> | null;
          new_values?: Record<string, unknown> | null;
        };
        Update: Partial<Database["public"]["Tables"]["audit_logs"]["Insert"]>;
        Relationships: [];
      };

      app_settings: {
        Row: {
          id: string;
          shop_id: string;
          default_interest_rate_percent_per_month: string;
          default_currency: string;
          default_locale: string;
          interest_rounding_policy: InterestRoundingPolicy;
          grace_period_days: number;
          overdue_threshold_months: number;
          timezone: string;
          date_format: "DD/MM/YYYY" | "MM/DD/YYYY" | "YYYY-MM-DD";
          receipt_number_prefix: string;
          receipt_terms: string | null;
          staff_can_register_customers: boolean;
          staff_can_create_loans: boolean;
          staff_can_record_payments: boolean;
          updated_by: string | null;
          updated_at: string;
        };
        Insert: {
          id?: string;
          shop_id: string;
          default_interest_rate_percent_per_month?: number;
          default_currency?: string;
          default_locale?: string;
          interest_rounding_policy?: InterestRoundingPolicy;
          grace_period_days?: number;
          overdue_threshold_months?: number;
          timezone?: string;
          date_format?: "DD/MM/YYYY" | "MM/DD/YYYY" | "YYYY-MM-DD";
          receipt_number_prefix?: string;
          receipt_terms?: string | null;
          staff_can_register_customers?: boolean;
          staff_can_create_loans?: boolean;
          staff_can_record_payments?: boolean;
          updated_by?: string | null;
          updated_at?: string;
        };
        Update: Partial<Database["public"]["Tables"]["app_settings"]["Insert"]>;
        Relationships: [
          {
            foreignKeyName: "app_settings_shop_id_fkey";
            columns: ["shop_id"];
            isOneToOne: true;
            referencedRelation: "shops";
            referencedColumns: ["id"];
          },
        ];
      };
    };

    Views: Record<string, never>;

    Functions: {
      create_transaction: {
        Args: {
          p_customer_id: string;
          p_principal_amount: number;
          p_interest_rate_percent_per_month: number;
          p_issue_date: string;
          p_tenure_months: number;
          p_items: Array<{
            category: JewelleryCategory;
            description: string;
            gross_weight_grams: number;
            net_weight_grams: number;
            stone_weight_grams?: number;
            purity_karat: number;
            gold_rate_used_per_gram: number;
            estimated_value: number;
            condition_notes?: string | null;
          }>;
        };
        Returns: Database["public"]["Tables"]["transactions"]["Row"];
      };
      record_payment: {
        Args: {
          p_transaction_id: string;
          p_amount: number;
          p_payment_type: PaymentType;
          p_payment_method: PaymentMethod;
          p_payment_date: string;
        };
        Returns: Database["public"]["Tables"]["transactions"]["Row"];
      };
      post_payment: {
        Args: { p_transaction_id: string; p_amount: number; p_payment_method: "CASH" | "UPI" | "BANK_TRANSFER" | "OTHER"; p_payment_date: string; p_idempotency_key: string; p_reference_number?: string | null; p_remarks?: string | null; p_confirm_jewellery_return?: boolean };
        Returns: Database["public"]["Tables"]["transactions"]["Row"];
      };
      dashboard_summary: { Args: { p_from?: string | null; p_to?: string | null }; Returns: unknown };
      switch_active_shop: { Args: { p_shop_id: string }; Returns: Database["public"]["Tables"]["shops"]["Row"] };
      reverse_payment: { Args: { p_payment_id: string; p_reason: string; p_idempotency_key: string }; Returns: Database["public"]["Tables"]["transactions"]["Row"] };
      cancel_transaction: {
        Args: {
          p_transaction_id: string;
          p_reason: string;
        };
        Returns: Database["public"]["Tables"]["transactions"]["Row"];
      };
      bootstrap_shop_owner: {
        Args: { p_shop_name: string };
        Returns: Database["public"]["Tables"]["shops"]["Row"];
      };
      complete_onboarding: {
        Args: Record<string, never>;
        Returns: Database["public"]["Tables"]["shops"]["Row"];
      };
      set_pin: { Args: { p_new_pin: string }; Returns: undefined };
      clear_pin: { Args: Record<string, never>; Returns: undefined };
      pin_is_configured: { Args: Record<string, never>; Returns: boolean };
      verify_pin: { Args: { p_candidate_pin: string }; Returns: boolean };
      set_customer_photo: {
        Args: { p_customer_id: string; p_photo_path: string };
        Returns: Database["public"]["Tables"]["customers"]["Row"];
      };
      create_jewellery_loan: {
        Args: { p_customer_id: string; p_principal_amount: number; p_interest_type: "MONTHLY" | "YEARLY" | "FLAT"; p_interest_rate: number; p_flat_interest_basis: number | null; p_deposit_date: string; p_notes: string | null; p_idempotency_key: string; p_items: Array<{ jewellery_name: string; metal_type: string; weight_grams: number; quantity: number; notes?: string | null }> };
        Returns: Database["public"]["Tables"]["transactions"]["Row"];
      };
      create_historical_jewellery_loan: {
        Args: Database["public"]["Functions"]["create_jewellery_loan"]["Args"] & {
          p_previous_payments: Array<{ payment_date: string; amount: number; payment_method: "CASH" | "UPI" | "BANK_TRANSFER" | "OTHER"; remarks?: string | null; reference_number?: string | null; idempotency_key: string }>;
        };
        Returns: Database["public"]["Tables"]["transactions"]["Row"];
      };
      calculate_live_settlement: {
        Args: { p_transaction_id: string; p_as_of?: string };
        Returns: LiveSettlementJson;
      };
      set_jewellery_item_photo: {
        Args: { p_item_id: string; p_photo_path: string };
        Returns: Database["public"]["Tables"]["jewellery_items"]["Row"];
      };
    };

    Enums: {
      transaction_status: TransactionStatus;
    };
  };
}
