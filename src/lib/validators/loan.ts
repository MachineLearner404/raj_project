import { z } from "zod";

export const jewelleryItemFormSchema = z
  .object({
    category: z.enum([
      "necklace",
      "ring",
      "bangle",
      "coin",
      "chain",
      "earrings",
      "other",
    ]),
    description: z.string().trim().min(2, "Describe the item"),
    grossWeightGrams: z.coerce.number().positive("Gross weight must be positive"),
    netWeightGrams: z.coerce.number().positive("Net weight must be positive"),
    purityKarat: z.coerce.number().min(1).max(24),
  })
  .refine((item) => item.netWeightGrams <= item.grossWeightGrams, {
    message: "Net weight cannot exceed gross weight",
    path: ["netWeightGrams"],
  });

export const loanFormSchema = z.object({
  customerId: z.string().min(1, "Select a customer"),
  items: z.array(jewelleryItemFormSchema).min(1, "Add at least one item"),
  principalAmount: z.coerce.number().positive("Enter the loan amount"),
  interestRatePercentPerMonth: z.coerce
    .number()
    .positive("Enter an interest rate")
    .max(10, "That rate looks unusually high — double check it"),
  issueDate: z.string().min(1, "Select the issue date"),
});

// Input types (what the form fields hold, pre-coercion) vs output types
// (what the resolver produces after zod's z.coerce runs) differ because of
// the numeric z.coerce fields — react-hook-form needs both.
export type LoanFormInput = z.input<typeof loanFormSchema>;
export type LoanFormValues = z.output<typeof loanFormSchema>;
export type JewelleryItemFormValues = z.output<typeof jewelleryItemFormSchema>;
