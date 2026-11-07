/** Pure finance domain: all money is integer paise, never browser floats. */
export type InterestMode = "MONTHLY" | "YEARLY" | "FLAT";
export type FlatBasis = { kind: "AMOUNT"; paise: number } | { kind: "PERCENT_OF_ORIGINAL"; rateBps: number };
export type LoanTerms = { originalPrincipalPaise: number; rateBps: number; mode: InterestMode; depositDate: string; flatBasis?: FlatBasis };
export type Posting = { accruedPaise: number; principalPaise: number; anchor: string; settledPeriods: number; redeemed: boolean; interestPaidPaise: number; principalPaidPaise: number; flatCharged?: boolean };
export type HistoricalPayment = { paymentDate: string; amountPaise: number };
export type Settlement = {
  originalPrincipalPaise: number; previousPrincipalRepaymentsPaise: number;
  remainingPrincipalPaise: number; totalInterestAccruedPaise: number;
  previousInterestPaidPaise: number; outstandingInterestPaise: number;
  totalPreviousPaymentsPaise: number; amountPayablePaise: number; asOf: string;
  redeemed: boolean;
};
const d = (s: string) => new Date(`${s}T00:00:00Z`); const iso = (x: Date) => x.toISOString().slice(0, 10);
export function anniversary(start: string, periods: number, yearly = false) { const x=d(start), y=x.getUTCFullYear()+(yearly?periods:Math.floor((x.getUTCMonth()+periods)/12)), m=yearly?x.getUTCMonth():(x.getUTCMonth()+periods)%12, last=new Date(Date.UTC(y,m+1,0)).getUTCDate(); return iso(new Date(Date.UTC(y,m,Math.min(x.getUTCDate(),last)))); }
export function completedPeriods(anchor: string, asOf: string, yearly=false) { let n=0; while(d(anniversary(anchor,n+1,yearly))<=d(asOf)) n++; return n; }
export function periodInterestPaise(principalPaise: number, rateBps: number) { return principalPaise<=0?0:Math.floor((principalPaise*rateBps+5000)/10000); }
export const initialPosting=(t: LoanTerms): Posting=>({ accruedPaise:0, principalPaise:t.originalPrincipalPaise, anchor:t.depositDate, settledPeriods:0, redeemed:false, interestPaidPaise:0, principalPaidPaise:0, flatCharged:false });
export function accrueTo(t: LoanTerms, p: Posting, asOf: string): Posting {
  if (d(asOf) < d(t.depositDate)) throw new Error("Calculation date cannot precede the deposit date");
  if (p.redeemed) return { ...p, interestPaidPaise: 0, principalPaidPaise: 0 };
  let accrued=p.accruedPaise, anchor=p.anchor, settled=p.settledPeriods, flat=p.flatCharged??false;
  if(t.mode==="FLAT"&&!flat){ accrued+=t.flatBasis?.kind==="AMOUNT"?t.flatBasis.paise:periodInterestPaise(t.originalPrincipalPaise,t.flatBasis?.rateBps??0); flat=true; }
  else if(t.mode!=="FLAT"){ const yearly=t.mode==="YEARLY"; let due=0; while(d(anniversary(t.depositDate,settled+due+1,yearly))<=d(asOf)) due++; accrued+=due*periodInterestPaise(p.principalPaise,t.rateBps*(yearly?12:1)); settled+=due; anchor=anniversary(t.depositDate,settled,yearly); }
  return { ...p, accruedPaise: accrued, anchor, settledPeriods: settled, flatCharged: flat, interestPaidPaise: 0, principalPaidPaise: 0 };
}
export function postPayment(t: LoanTerms, p: Posting, paymentPaise: number, paymentDate: string): Posting { if(p.redeemed) throw new Error("Loan is redeemed"); if(!Number.isInteger(paymentPaise)||paymentPaise<=0) throw new Error("Payment must be positive paise"); const accruedPosting=accrueTo(t,p,paymentDate); const interest=Math.min(paymentPaise,accruedPosting.accruedPaise), principal=paymentPaise-interest; if(principal>p.principalPaise) throw new Error("Overpayment is not permitted"); const balance=p.principalPaise-principal, unpaid=accruedPosting.accruedPaise-interest; return { ...accruedPosting, accruedPaise: unpaid, principalPaise: balance, redeemed:balance===0&&unpaid===0, interestPaidPaise:interest, principalPaidPaise:principal }; }
/** Replays dated payments exactly as the posting service does, then accrues only
 * completed periods to `asOf`. It is deliberately pure for previews and tests;
 * final posting remains the locked database RPC. */
export function calculateSettlement(t: LoanTerms, payments: HistoricalPayment[], asOf: string): Settlement {
  if (d(asOf) < d(t.depositDate)) throw new Error("Calculation date cannot precede the deposit date");
  let posting=initialPosting(t), previousDate=t.depositDate, interestPaid=0, principalPaid=0, totalPaid=0;
  for (const payment of payments) {
    if (d(payment.paymentDate) < d(t.depositDate) || d(payment.paymentDate) > d(asOf)) throw new Error("Payment date is outside the calculation range");
    if (d(payment.paymentDate) < d(previousDate)) throw new Error("Payments must be in chronological order");
    posting=postPayment(t, posting, payment.amountPaise, payment.paymentDate);
    interestPaid+=posting.interestPaidPaise; principalPaid+=posting.principalPaidPaise; totalPaid+=payment.amountPaise; previousDate=payment.paymentDate;
  }
  posting=accrueTo(t,posting,asOf);
  return { originalPrincipalPaise:t.originalPrincipalPaise, previousPrincipalRepaymentsPaise:principalPaid, remainingPrincipalPaise:posting.principalPaise, totalInterestAccruedPaise:interestPaid+posting.accruedPaise, previousInterestPaidPaise:interestPaid, outstandingInterestPaise:posting.accruedPaise, totalPreviousPaymentsPaise:totalPaid, amountPayablePaise:posting.principalPaise+posting.accruedPaise, asOf, redeemed:posting.redeemed };
}

/** Compatibility read-only estimate for the existing demo payment page (rupees). */
export function calculateInterestDue(principalRupees: number, monthlyRatePercent: number, issueDate: string, asOf = new Date()): number {
  const periods = completedPeriods(issueDate, asOf.toISOString().slice(0, 10));
  return (periods * periodInterestPaise(Math.round(principalRupees * 100), Math.round(monthlyRatePercent * 100))) / 100;
}
