import { useEffect, useState, type FormEvent } from "react";
import { Navigate, useNavigate } from "react-router-dom";
import { supabase } from "@/lib/supabase/client";
import { useAuth } from "@/features/auth/AuthProvider";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export function OnboardingPage() {
  const { user, profile, shop, settings, loading, refresh } = useAuth();
  const [shopName, setShopName] = useState(""); const [address, setAddress] = useState(""); const [phone, setPhone] = useState("");
  const [timezone, setTimezone] = useState("Asia/Kolkata"); const [dateFormat, setDateFormat] = useState("DD/MM/YYYY"); const [prefix, setPrefix] = useState("RCPT"); const [terms, setTerms] = useState("");
  const [error, setError] = useState<string | null>(null); const [busy, setBusy] = useState(false); const navigate = useNavigate();
  useEffect(() => { if (shop) { setShopName(shop.name); setAddress(shop.address ?? ""); setPhone(shop.phone ?? ""); } if (settings) { setTimezone(settings.timezone); setDateFormat(settings.date_format); setPrefix(settings.receipt_number_prefix); setTerms(settings.receipt_terms ?? ""); } }, [shop, settings]);
  if (loading) return null;
  if (!user) return <Navigate to="/login" replace />;
  if (shop?.onboarding_completed_at) return <Navigate to="/" replace />;
  if (profile && profile.role !== "owner") return <main className="grid min-h-screen place-items-center p-6"><Card className="max-w-lg"><CardHeader><CardTitle>Shop setup is in progress</CardTitle><CardDescription>Ask the shop owner to finish setup before using the application.</CardDescription></CardHeader></Card></main>;
  async function submit(event: FormEvent) {
    event.preventDefault(); setError(null);
    if (!shopName.trim() || !address.trim() || !phone.trim()) { setError("Shop name, address, and phone are required."); return; }
    if (!/^[A-Za-z0-9-]{1,10}$/.test(prefix)) { setError("Receipt prefix must be 1–10 letters, numbers, or hyphens."); return; }
    setBusy(true);
    let shopId = shop?.id;
    if (!shopId) {
      const { data, error: bootstrapError } = await supabase.rpc("bootstrap_shop_owner", { p_shop_name: shopName.trim() });
      if (bootstrapError || !data) { setBusy(false); setError(bootstrapError?.message ?? "Could not create the shop."); return; }
      shopId = data.id;
      await refresh();
    }
    const [{ error: shopError }, { error: settingsError }] = await Promise.all([
      supabase.from("shops").update({ name: shopName.trim(), address: address.trim(), phone: phone.trim() }).eq("id", shopId),
      supabase.from("app_settings").update({ timezone, date_format: dateFormat as "DD/MM/YYYY" | "MM/DD/YYYY" | "YYYY-MM-DD", receipt_number_prefix: prefix, receipt_terms: terms.trim() || null, default_currency: "INR" }).eq("shop_id", shopId),
    ]);
    if (shopError || settingsError) { setBusy(false); setError(shopError?.message ?? settingsError?.message ?? "Could not save setup."); return; }
    const { error: completeError } = await supabase.rpc("complete_onboarding", {});
    setBusy(false);
    if (completeError) { setError(completeError.message); return; }
    await refresh(); navigate("/", { replace: true });
  }
  return <main className="min-h-screen bg-muted/30 p-4 sm:p-8"><Card className="mx-auto max-w-2xl"><CardHeader><CardTitle>Set up your shop</CardTitle><CardDescription>These details are used on receipts and reports. Currency is fixed to INR.</CardDescription></CardHeader><CardContent><form onSubmit={submit} className="space-y-4"><div className="grid gap-4 sm:grid-cols-2"><Field label="Shop name"><Input required value={shopName} onChange={e => setShopName(e.target.value)} /></Field><Field label="Phone"><Input required type="tel" value={phone} onChange={e => setPhone(e.target.value)} /></Field><Field label="Address" className="sm:col-span-2"><Textarea required value={address} onChange={e => setAddress(e.target.value)} /></Field><Field label="Timezone"><Input required value={timezone} onChange={e => setTimezone(e.target.value)} /></Field><Field label="Date format"><select className="h-8 w-full rounded-md border border-input bg-background px-2 text-sm" value={dateFormat} onChange={e => setDateFormat(e.target.value)}><option>DD/MM/YYYY</option><option>MM/DD/YYYY</option><option>YYYY-MM-DD</option></select></Field><Field label="Receipt prefix"><Input required maxLength={10} value={prefix} onChange={e => setPrefix(e.target.value.toUpperCase())} /></Field><Field label="Currency"><Input value="INR" disabled /></Field><Field label="Receipt terms" className="sm:col-span-2"><Textarea value={terms} onChange={e => setTerms(e.target.value)} /></Field></div>{error && <p role="alert" className="text-sm text-destructive">{error}</p>}<Button type="submit" disabled={busy}>{busy ? "Saving setup…" : "Complete setup"}</Button></form></CardContent></Card></main>;
}
function Field({ label, children, className = "" }: { label: string; children: React.ReactNode; className?: string }) { return <div className={`space-y-1.5 ${className}`}><Label>{label}</Label>{children}</div>; }
