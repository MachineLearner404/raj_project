/** Pure finance domain: all money is integer paise, never browser floats. */
export type InterestMode = "MONTHLY" | "YEARLY" | "FLAT";
export type FlatBasis = { kind: "AMOUNT"; paise: number } | { kind: "PERCENT_OF_ORIGINAL"; rateBps: number };
export type LoanTerms = { originalPrincipalPaise: number; rateBps: number; mode: InterestMode; depositDate: string; flatBasis?: FlatBasis };
export type Posting = { accruedPaise: number; principalPaise: number; anchor: string; settledPeriods: number; redeemed: boolean; interestPaidPaise: number; principalPaidPaise: number; flatCharged?: boolean };
const d = (s: string) => new Date(`${s}T00:00:00Z`); const iso = (x: Date) => x.toISOString().slice(0, 10);
export function anniversary(start: string, periods: number, yearly = false) { const x=d(start), y=x.getUTCFullYear()+(yearly?periods:Math.floor((x.getUTCMonth()+periods)/12)), m=yearly?x.getUTCMonth():(x.getUTCMonth()+periods)%12, last=new Date(Date.UTC(y,m+1,0)).getUTCDate(); return iso(new Date(Date.UTC(y,m,Math.min(x.getUTCDate(),last)))); }
export function completedPeriods(anchor: string, asOf: string, yearly=false) { let n=0; while(d(anniversary(anchor,n+1,yearly))<=d(asOf)) n++; return n; }
export function periodInterestPaise(principalPaise: number, rateBps: number) { return principalPaise<=0?0:Math.floor((principalPaise*rateBps+5000)/10000); }
export const initialPosting=(t: LoanTerms): Posting=>({ accruedPaise:0, principalPaise:t.originalPrincipalPaise, anchor:t.depositDate, settledPeriods:0, redeemed:false, interestPaidPaise:0, principalPaidPaise:0, flatCharged:false });
export function postPayment(t: LoanTerms, p: Posting, paymentPaise: number, paymentDate: string): Posting { if(p.redeemed) throw new Error("Loan is redeemed"); if(!Number.isInteger(paymentPaise)||paymentPaise<=0) throw new Error("Payment must be positive paise"); let accrued=p.accruedPaise, anchor=p.anchor, settled=p.settledPeriods, flat=p.flatCharged??false; if(t.mode==="FLAT"&&!flat){ accrued+=t.flatBasis?.kind==="AMOUNT"?t.flatBasis.paise:periodInterestPaise(t.originalPrincipalPaise,t.flatBasis?.rateBps??0); flat=true; } else if(t.mode!=="FLAT"){ const yearly=t.mode==="YEARLY"; let due=0; while(d(anniversary(t.depositDate,settled+due+1,yearly))<=d(paymentDate)) due++; accrued+=due*periodInterestPaise(p.principalPaise,t.rateBps*(yearly?12:1)); settled+=due; anchor=anniversary(t.depositDate,settled,yearly); } const interest=Math.min(paymentPaise,accrued), principal=paymentPaise-interest; if(principal>p.principalPaise) throw new Error("Overpayment is not permitted"); const balance=p.principalPaise-principal, unpaid=accrued-interest; return { accruedPaise:unpaid, principalPaise:balance, anchor, settledPeriods:settled, redeemed:balance===0&&unpaid===0, interestPaidPaise:interest, principalPaidPaise:principal, flatCharged:flat }; }

/** Compatibility read-only estimate for the existing demo payment page (rupees). */
export function calculateInterestDue(principalRupees: number, monthlyRatePercent: number, issueDate: string, asOf = new Date()): number {
  const periods = completedPeriods(issueDate, asOf.toISOString().slice(0, 10));
  return (periods * periodInterestPaise(Math.round(principalRupees * 100), Math.round(monthlyRatePercent * 100))) / 100;
}
