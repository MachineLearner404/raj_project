import { useState, type FormEvent } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { supabase } from "@/lib/supabase/client";

export function ReversePaymentPage() {
  const { id } = useParams(); const navigate = useNavigate(); const [reason, setReason] = useState(""); const [confirm, setConfirm] = useState(""); const [error, setError] = useState(""); const [busy, setBusy] = useState(false);
  async function submit(event: FormEvent) { event.preventDefault(); if (!id) return; if (reason.trim().length < 5) { setError("Give a correction reason of at least 5 characters."); return; } if (confirm !== "REVERSE PAYMENT") { setError("Type REVERSE PAYMENT exactly to confirm."); return; } setBusy(true); setError(""); const { data, error: rpcError } = await supabase.rpc("reverse_payment", { p_payment_id: id, p_reason: reason.trim(), p_idempotency_key: crypto.randomUUID() }); setBusy(false); if (rpcError) { setError(rpcError.message); return; } navigate(`/transactions/${data.id}`, { replace: true }); }
  return <main className="mx-auto max-w-xl space-y-5 p-6"><Button variant="outline" asChild><Link to="/loans/active">Back</Link></Button><Card className="border-destructive"><CardHeader><CardTitle>Reverse payment</CardTitle><CardDescription>This creates an append-only correction linked to the original payment. It never deletes the payment or receipt. Only the latest payment on a non-redeemed pledge can be reversed.</CardDescription></CardHeader><CardContent><form className="space-y-4" onSubmit={submit}><div className="space-y-2"><Label>Reason</Label><Textarea required minLength={5} maxLength={500} value={reason} onChange={event => setReason(event.target.value)} /></div><div className="space-y-2"><Label>Type “REVERSE PAYMENT”</Label><Input value={confirm} onChange={event => setConfirm(event.target.value)} /></div>{error && <p role="alert" className="text-sm text-destructive">{error}</p>}<Button type="submit" variant="destructive" disabled={busy}>{busy ? "Reversing…" : "Reverse payment"}</Button></form></CardContent></Card></main>;
}
