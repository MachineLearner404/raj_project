export type LoanStatus = "active" | "overdue" | "completed" | "auctioned";

export interface Customer {
  id: string;
  name: string;
  phone: string;
  address: string;
  idProofType: "Aadhaar" | "PAN" | "Voter ID" | "Driving Licence";
  idProofNumber: string;
  activeLoans: number;
  joinedOn: string;
}

export interface JewelleryLoan {
  id: string;
  loanNumber: string;
  customerName: string;
  itemDescription: string;
  grossWeightGrams: number;
  netWeightGrams: number;
  principalAmount: number;
  interestRatePercentPerMonth: number;
  issueDate: string;
  dueDate: string;
  status: LoanStatus;
  monthsCompleted: number;
  interestAccrued: number;
}

export interface Payment {
  id: string;
  loanNumber: string;
  customerName: string;
  amount: number;
  type: "interest" | "partial-principal" | "full-closure";
  date: string;
}

export interface DashboardMetric {
  label: string;
  value: string;
  helpText: string;
  trend?: "up" | "down" | "flat";
}
