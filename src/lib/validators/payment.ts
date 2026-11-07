import { z } from "zod";

export const paymentFormSchema = z.object({
  loanId: z.string().min(1, "Select a loan"),
  amount: z.coerce.number().positive("Enter the amount received"),
  type: z.enum(["interest", "partial-principal", "full-closure"]),
  method: z.enum(["cash", "upi", "bank-transfer"]),
  date: z.string().min(1, "Select the payment date"),
});

export type PaymentFormInput = z.input<typeof paymentFormSchema>;
export type PaymentFormValues = z.output<typeof paymentFormSchema>;
