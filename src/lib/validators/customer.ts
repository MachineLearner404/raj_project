import { z } from "zod";

const idProofPatterns: Record<string, RegExp> = {
  Aadhaar: /^\d{4}-?\d{4}-?\d{4}$/,
  PAN: /^[A-Z]{5}\d{4}[A-Z]$/,
  "Voter ID": /^[A-Z]{3}\d{7}$/,
  "Driving Licence": /^[A-Z0-9-\s]{6,20}$/i,
};

export const customerFormSchema = z
  .object({
    fullName: z.string().trim().min(2, "Enter the customer's full name"),
    phone: z
      .string()
      .trim()
      .regex(/^(\+91[\s-]?)?[6-9]\d{9}$/, "Enter a valid 10-digit Indian mobile number"),
    alternatePhone: z
      .string()
      .trim()
      .regex(/^(\+91[\s-]?)?[6-9]\d{9}$/, "Enter a valid 10-digit Indian mobile number")
      .optional()
      .or(z.literal("")),
    address: z.string().trim().min(5, "Enter the customer's address"),
    idProofType: z.enum(["Aadhaar", "PAN", "Voter ID", "Driving Licence"]),
    idProofNumber: z.string().trim().min(1, "Enter the ID proof number"),
    notes: z.string().trim().optional(),
  })
  .refine(
    (data) => idProofPatterns[data.idProofType]?.test(data.idProofNumber),
    {
      message: "ID proof number doesn't match the selected proof type's format",
      path: ["idProofNumber"],
    },
  );

export type CustomerFormValues = z.infer<typeof customerFormSchema>;
