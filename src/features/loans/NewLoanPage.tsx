import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Card, CardContent } from "@/components/ui/card";
import { PageHeader } from "@/components/shared/PageHeader";
import { calculateSettlement } from "@/lib/calculations/interest";
import { listCustomers } from "@/lib/repositories/customers.repository";
import { createHistoricalJewelleryLoan, createJewelleryLoan, listJewelleryItems, uploadJewelleryItemPhoto } from "@/lib/repositories/transactions.repository";
import { useAuth } from "@/features/auth/AuthProvider";
import type { Database } from "@/lib/supabase/database.types";

type Customer = Database["public"]["Tables"]["customers"]["Row"];
type Item = { id: string; jewelleryName: string; metalType: string; weightGrams: number; quantity: number; notes: string; photo: File | null; preview: string | null };
type PreviousPayment = { id: string; paymentDate: string; amount: number; paymentMethod: "CASH" | "UPI" | "BANK_TRANSFER" | "OTHER"; remarks: string };
const blankItem = (): Item => ({ id: crypto.randomUUID(), jewelleryName: "", metalType: "GOLD", weightGrams: 0, quantity: 1, notes: "", photo: null, preview: null });
const MAX_PHOTO_BYTES = 5 * 1024 * 1024;
const blankPayment = (): PreviousPayment => ({ id: crypto.randomUUID(), paymentDate: new Date().toISOString().slice(0, 10), amount: 0, paymentMethod: "CASH", remarks: "" });
const today = () => new Date().toISOString().slice(0, 10);
const money = (paise: number) => `₹${(paise / 100).toLocaleString("en-IN", { minimumFractionDigits: 2 })}`;

export function NewLoanPage() {
  const { profile, settings } = useAuth(); const navigate = useNavigate();
  const [customers, setCustomers] = useState<Customer[]>([]); const [customerId, setCustomerId] = useState(""); const [items, setItems] = useState<Item[]>([blankItem()]); const [principal, setPrincipal] = useState(0);
  const [interestType, setInterestType] = useState<"MONTHLY" | "YEARLY" | "FLAT">("MONTHLY"); const [rate, setRate] = useState(0); const [flatBasis, setFlatBasis] = useState(0); const [depositDate, setDepositDate] = useState(today()); const [historical, setHistorical] = useState(false); const [previousPayments, setPreviousPayments] = useState<PreviousPayment[]>([]);
  const [notes, setNotes] = useState(""); const [review, setReview] = useState(false); const [saving, setSaving] = useState(false); const [key] = useState(() => crypto.randomUUID());
  useEffect(() => { void listCustomers().then(setCustomers).catch(() => toast.error("Customers could not be loaded.")); }, []);
  const customer = customers.find(c => c.id === customerId); const allowed = profile?.role !== "staff" || settings?.staff_can_create_loans;
  const totalWeight = useMemo(() => items.reduce((sum, item) => sum + (Number(item.weightGrams) || 0) * (Number(item.quantity) || 0), 0), [items]);
  const settlement = useMemo(() => {
    if (!historical || principal <= 0 || rate <= 0 || depositDate > today()) return null;
    try { return calculateSettlement({ originalPrincipalPaise: Math.round(principal * 100), rateBps: Math.round(rate * 100), mode: interestType, depositDate, ...(interestType === "FLAT" ? { flatBasis: { kind: "AMOUNT" as const, paise: Math.round(flatBasis * 100) } } : {}) }, previousPayments.slice().sort((a, b) => a.paymentDate.localeCompare(b.paymentDate)).map(p => ({ paymentDate: p.paymentDate, amountPaise: Math.round(p.amount * 100) })), today()); } catch { return null; }
  }, [historical, principal, rate, interestType, flatBasis, depositDate, previousPayments]);
  function updateItem(index: number, patch: Partial<Item>) { setItems(current => current.map((item, i) => i === index ? { ...item, ...patch } : item)); }
  function removeItem(index: number) { const item = items[index]; if (item.preview) URL.revokeObjectURL(item.preview); setItems(items.filter((_, x) => x !== index)); }
  function choosePhoto(index: number, file?: File) {
    if (!file) return;
    if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) { toast.error("Use a JPG, PNG, or WebP image."); return; }
    if (file.size > MAX_PHOTO_BYTES) { toast.error("Photo must be 5 MB or smaller."); return; }
    const previous = items[index]?.preview; if (previous) URL.revokeObjectURL(previous);
    updateItem(index, { photo: file, preview: URL.createObjectURL(file) });
  }
  function updatePayment(id: string, patch: Partial<PreviousPayment>) { setPreviousPayments(current => current.map(payment => payment.id === id ? { ...payment, ...patch } : payment)); }
  function validate() {
    if (!customerId) return "Select a customer."; if (principal <= 0 || rate <= 0) return "Principal and rate must be positive."; if (depositDate > today()) return "Deposit date cannot be in the future."; if (!historical && depositDate !== today()) return "Use Previous / Historical Record for a past deposit date."; if (interestType === "FLAT" && flatBasis <= 0) return "Enter a positive flat-interest basis.";
    if (!items.length || items.some(i => !i.jewelleryName.trim() || i.weightGrams <= 0 || i.quantity <= 0)) return "Every item needs a name, positive weight, and positive quantity.";
    let last = depositDate; for (const payment of previousPayments) { if (payment.amount <= 0) return "Every previous payment needs a positive amount."; if (payment.paymentDate < depositDate || payment.paymentDate > today()) return "Previous payment dates must be between deposit date and today."; if (payment.paymentDate < last) return "Previous payments must be in chronological order."; last = payment.paymentDate; } return null;
  }
  async function submit() {
    const invalid = validate(); if (invalid) { toast.error(invalid); setReview(false); return; }
    setSaving(true);
    try {
      const input = { customerId, principalAmount: principal, interestType, interestRate: rate, flatInterestBasis: interestType === "FLAT" ? flatBasis : null, depositDate, notes, idempotencyKey: key, items };
      const txn = historical
        ? await createHistoricalJewelleryLoan({ ...input, previousPayments: previousPayments.slice().sort((a, b) => a.paymentDate.localeCompare(b.paymentDate)).map(p => ({ paymentDate: p.paymentDate, amount: p.amount, paymentMethod: p.paymentMethod, remarks: p.remarks, idempotencyKey: p.id })) })
        : await createJewelleryLoan(input);
      const photos = items.filter(i => i.photo);
      if (photos.length) {
        // Items don't exist until the server creates them above, so photos are
        // attached as a second step — matched by creation order to this form's order.
        try {
          const created = await listJewelleryItems(txn.id);
          await Promise.all(items.map((item, i) => item.photo && created[i] ? uploadJewelleryItemPhoto(created[i], item.photo) : null));
        } catch (e) { toast.error("Pledge saved, but a jewellery photo could not be uploaded", { description: e instanceof Error ? e.message : undefined }); }
      }
      toast.success(`Pledge ${txn.pledge_code} created.`); navigate(`/transactions/${txn.id}`);
    } catch (e) { toast.error(e instanceof Error ? e.message : "Loan could not be created."); } finally { setSaving(false); }
  }
  const settlementRows = settlement ? [["Original loan amount", settlement.originalPrincipalPaise], ["Previous principal repayments", settlement.previousPrincipalRepaymentsPaise], ["Remaining principal", settlement.remainingPrincipalPaise], ["Total interest accrued", settlement.totalInterestAccruedPaise], ["Previous interest paid", settlement.previousInterestPaidPaise], ["Outstanding interest", settlement.outstandingInterestPaise], ["Total previous payments", settlement.totalPreviousPaymentsPaise], ["Amount payable today", settlement.amountPayablePaise]] as Array<[string, number]> : [];
  if (review) return <div className="max-w-2xl space-y-5"><PageHeader title="Review jewellery loan" description="Confirm frozen terms before creating the pledge." /><Card><CardContent className="space-y-3 pt-6 text-sm"><p><b>Customer:</b> {customer?.full_name} · {customer?.mobile}</p><p><b>Deposit date:</b> {depositDate}{historical ? " · historical record" : ""}</p><p><b>Principal:</b> ₹{principal.toLocaleString("en-IN")} · <b>Interest:</b> {rate}% {interestType.toLowerCase()}</p><p><b>Total weight:</b> {totalWeight} g · <b>Items:</b> {items.length}</p>{settlement && <SettlementCard rows={settlementRows} />}{items.map((item, i) => <p key={i}>{item.jewelleryName} — {item.metalType}, {item.weightGrams}g × {item.quantity}</p>)}<p className="text-muted-foreground">The server atomically creates the pledge and replays historical payments using their actual dates.</p><div className="flex gap-2"><Button variant="outline" onClick={() => setReview(false)}>Back to edit</Button><Button disabled={saving} onClick={() => void submit()}>{saving ? "Creating…" : "Confirm and create"}</Button></div></CardContent></Card></div>;
  return <div className="max-w-3xl space-y-5"><PageHeader title="New Jewellery Loan" description="Create a pledge with frozen terms and a server-generated transaction ID." actions={<Button asChild variant="outline"><Link to="/customers/new">Add Customer</Link></Button>} />{!allowed && <p className="text-sm text-destructive">Your role is not permitted to create loans.</p>}<Card><CardContent className="space-y-5 pt-6"><fieldset className="space-y-2"><Label>Is this a Previous / Historical Record?</Label><div className="flex gap-5 text-sm"><label><input className="mr-2" type="radio" checked={!historical} onChange={() => { setHistorical(false); setDepositDate(today()); setPreviousPayments([]); }} />No — New transaction</label><label><input className="mr-2" type="radio" checked={historical} onChange={() => setHistorical(true)} />Yes — Previous transaction</label></div></fieldset><div className="grid gap-4 sm:grid-cols-2"><div><Label>Customer</Label><select className="mt-1 h-8 w-full rounded-md border bg-background px-2 text-sm" value={customerId} onChange={e => setCustomerId(e.target.value)}><option value="">Select customer</option>{customers.map(c => <option key={c.id} value={c.id}>{c.customer_code} · {c.full_name} · {c.mobile}</option>)}</select></div><div><Label>Original deposit date</Label><Input type="date" max={today()} value={depositDate} onChange={e => setDepositDate(e.target.value)} /></div></div>{customer && <div className="rounded-md bg-muted p-3 text-sm"><b>{customer.full_name}</b><br />{customer.address}<br />{customer.mobile}</div>}<ItemsEditor items={items} update={updateItem} choosePhoto={choosePhoto} remove={removeItem} add={() => setItems([...items, blankItem()])} /><div className="grid gap-4 sm:grid-cols-3"><div><Label>Original loan amount (₹)</Label><Input type="number" min="1" value={principal || ""} onChange={e => setPrincipal(Number(e.target.value))} /></div><div><Label>Interest type</Label><select className="mt-1 h-8 w-full rounded-md border bg-background px-2 text-sm" value={interestType} onChange={e => setInterestType(e.target.value as typeof interestType)}><option value="MONTHLY">Monthly</option><option value="YEARLY">Yearly</option><option value="FLAT">Flat</option></select></div><div><Label>Rate (%)</Label><Input type="number" min="0.01" step="0.01" value={rate || ""} onChange={e => setRate(Number(e.target.value))} /></div>{interestType === "FLAT" && <div><Label>Flat-interest basis (₹)</Label><Input type="number" min="1" value={flatBasis || ""} onChange={e => setFlatBasis(Number(e.target.value))} /></div>}</div>{historical && <HistoricalPayments payments={previousPayments} update={updatePayment} add={() => setPreviousPayments([...previousPayments, blankPayment()])} remove={id => setPreviousPayments(previousPayments.filter(p => p.id !== id))} />}{settlement && <SettlementCard rows={settlementRows} />}{historical && !settlement && <p className="text-sm text-destructive">Enter valid dated payments to calculate today’s settlement.</p>}<Textarea placeholder="Optional loan notes" value={notes} onChange={e => setNotes(e.target.value)} /><div className="flex items-center justify-between text-sm"><span>Total weight: <b>{totalWeight} g</b></span><Button disabled={!allowed} onClick={() => { const err = validate(); if (err) toast.error(err); else setReview(true); }}>Review loan</Button></div></CardContent></Card></div>;
}
function ItemsEditor({ items, update, choosePhoto, remove, add }: { items: Item[]; update: (i: number, patch: Partial<Item>) => void; choosePhoto: (i: number, file?: File) => void; remove: (i: number) => void; add: () => void }) {
  return <div className="space-y-3"><div className="flex justify-between"><Label>Jewellery items</Label><Button size="sm" variant="outline" onClick={add}>Add item</Button></div>
    {items.map((item, i) => <div key={item.id} className="grid gap-2 rounded-md border p-3 sm:grid-cols-5">
      <Input placeholder="Jewellery name" value={item.jewelleryName} onChange={e => update(i, { jewelleryName: e.target.value })} />
      <Input placeholder="Metal/type" value={item.metalType} onChange={e => update(i, { metalType: e.target.value })} />
      <Input type="number" min="0.001" step="0.001" placeholder="Weight g" value={item.weightGrams || ""} onChange={e => update(i, { weightGrams: Number(e.target.value) })} />
      <Input type="number" min="1" placeholder="Qty" value={item.quantity} onChange={e => update(i, { quantity: Number(e.target.value) })} />
      <Button variant="ghost" disabled={items.length === 1} onClick={() => remove(i)}>Remove</Button>
      <Textarea className="sm:col-span-5" placeholder="Description / notes" value={item.notes} onChange={e => update(i, { notes: e.target.value })} />
      <div className="sm:col-span-5 flex items-center gap-3">
        <Label className="shrink-0">Jewellery photo</Label>
        <Input className="max-w-xs" type="file" accept="image/jpeg,image/png,image/webp" onChange={e => choosePhoto(i, e.target.files?.[0])} />
        {item.preview && <img src={item.preview} alt={`${item.jewelleryName || "Jewellery item"} preview`} className="size-16 rounded-md object-cover" />}
      </div>
    </div>)}
  </div>;
}
function HistoricalPayments({ payments, update, add, remove }: { payments: PreviousPayment[]; update: (id: string, patch: Partial<PreviousPayment>) => void; add: () => void; remove: (id: string) => void }) { return <section className="space-y-3 rounded-md border p-3"><div className="flex justify-between"><div><Label>Previous payments</Label><p className="text-xs text-muted-foreground">Enter in chronological order. Interest and principal portions are calculated by the server.</p></div><Button size="sm" variant="outline" onClick={add}>Add payment</Button></div>{payments.map(p => <div key={p.id} className="grid gap-2 sm:grid-cols-5"><Input type="date" value={p.paymentDate} onChange={e => update(p.id, { paymentDate: e.target.value })} /><Input type="number" min="0.01" step="0.01" placeholder="Amount ₹" value={p.amount || ""} onChange={e => update(p.id, { amount: Number(e.target.value) })} /><select className="h-9 rounded border bg-background px-2" value={p.paymentMethod} onChange={e => update(p.id, { paymentMethod: e.target.value as PreviousPayment["paymentMethod"] })}><option value="CASH">Cash</option><option value="UPI">UPI</option><option value="BANK_TRANSFER">Bank transfer</option><option value="OTHER">Other</option></select><Input placeholder="Remarks" value={p.remarks} onChange={e => update(p.id, { remarks: e.target.value })} /><Button variant="ghost" onClick={() => remove(p.id)}>Remove</Button></div>)}</section>; }
function SettlementCard({ rows }: { rows: Array<[string, number]> }) { return <section className="rounded-md border border-primary/30 bg-primary/5 p-4"><h2 className="font-semibold">Current settlement calculation</h2><p className="mb-2 text-xs text-muted-foreground">Calculated as of {new Date().toLocaleDateString("en-IN")}. Preview is verified again by the server on save.</p><div className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">{rows.map(([label, value]) => <div className="contents" key={label}><span>{label}</span><b className="text-right">{money(value)}</b></div>)}</div><p className="mt-3 border-t pt-3 text-base font-semibold">Today’s settlement amount: {money(rows.at(-1)?.[1] ?? 0)}</p></section>; }
