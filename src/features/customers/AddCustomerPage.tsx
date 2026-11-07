import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { PageHeader } from "@/components/shared/PageHeader";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { customerFormSchema, type CustomerFormValues } from "@/lib/validators/customer";
import { createCustomer, findPossibleDuplicates, uploadCustomerPhoto } from "@/lib/repositories/customers.repository";
import { useAuth } from "@/features/auth/AuthProvider";
import type { Database } from "@/lib/supabase/database.types";

type CustomerRow = Database["public"]["Tables"]["customers"]["Row"];
const proofMap = { Aadhaar: "AADHAAR", PAN: "PAN", "Voter ID": "VOTER_ID", "Driving Licence": "DRIVING_LICENCE" } as const;
const MAX_PHOTO_BYTES = 5 * 1024 * 1024;

export function AddCustomerPage() {
  const { profile, settings } = useAuth(); const navigate = useNavigate();
  const [photo, setPhoto] = useState<File | null>(null); const [preview, setPreview] = useState<string | null>(null);
  const [duplicates, setDuplicates] = useState<CustomerRow[] | null>(null); const [pending, setPending] = useState<CustomerFormValues | null>(null); const [saving, setSaving] = useState(false);
  const { register, handleSubmit, reset, formState: { errors, isSubmitting } } = useForm<CustomerFormValues>({ resolver: zodResolver(customerFormSchema), defaultValues: { fullName: "", phone: "", alternatePhone: "", address: "", idProofType: "Aadhaar", idProofNumber: "", notes: "" } });
  useEffect(() => () => { if (preview) URL.revokeObjectURL(preview); }, [preview]);
  const allowed = profile?.role !== "staff" || settings?.staff_can_register_customers;
  function choosePhoto(file?: File) {
    if (!file) return;
    if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) { toast.error("Use a JPG, PNG, or WebP image."); return; }
    if (file.size > MAX_PHOTO_BYTES) { toast.error("Photo must be 5 MB or smaller."); return; }
    if (preview) URL.revokeObjectURL(preview); setPhoto(file); setPreview(URL.createObjectURL(file));
  }
  async function submit(values: CustomerFormValues, confirmed = false) {
    if (!profile || !allowed) { toast.error("You are not permitted to register customers."); return; }
    if (!confirmed) { const matches = await findPossibleDuplicates(values.fullName, values.phone); if (matches.length) { setPending(values); setDuplicates(matches); return; } }
    setSaving(true);
    try {
      let customer = await createCustomer({ shop_id: profile.shop_id, full_name: values.fullName.trim(), mobile: values.phone.trim(), alternate_mobile: values.alternatePhone?.trim() || null, address: values.address.trim(), id_proof_type: proofMap[values.idProofType], id_proof_number: values.idProofNumber.trim(), notes: values.notes?.trim() || null, created_by: profile.id });
      if (photo) customer = await uploadCustomerPhoto(customer, photo);
      toast.success(`Customer ${customer.customer_code} registered.`); reset(); navigate(`/customers/${customer.id}`);
    } catch (error) { toast.error(error instanceof Error ? error.message : "Customer could not be saved."); } finally { setSaving(false); }
  }
  return <div className="max-w-2xl space-y-5"><PageHeader title="Add Customer" description="Customer ID and registration date are generated securely when saved." />
    {!allowed && <p role="alert" className="rounded-md border border-destructive/30 p-3 text-sm text-destructive">Your role is not currently allowed to register customers.</p>}
    <Card><CardContent><form onSubmit={handleSubmit(v => submit(v))} className="grid gap-4 sm:grid-cols-2"><Field label="Full name" error={errors.fullName?.message}><Input disabled={!allowed} {...register("fullName")} /></Field><Field label="Mobile number" error={errors.phone?.message}><Input disabled={!allowed} inputMode="numeric" placeholder="98230 11223" {...register("phone")} /></Field><Field label="Complete address" error={errors.address?.message} className="sm:col-span-2"><Textarea disabled={!allowed} rows={3} {...register("address")} /></Field><Field label="Alternate phone"><Input disabled={!allowed} {...register("alternatePhone")} /></Field><Field label="ID proof number" error={errors.idProofNumber?.message}><Input disabled={!allowed} {...register("idProofNumber")} /></Field><Field label="ID proof type"><select className="h-8 w-full rounded-md border border-input bg-background px-2 text-sm" disabled={!allowed} {...register("idProofType")}><option>Aadhaar</option><option>PAN</option><option>Voter ID</option><option>Driving Licence</option></select></Field><Field label="Notes"><Input disabled={!allowed} {...register("notes")} /></Field><div className="space-y-2 sm:col-span-2"><Label>Customer photograph (optional)</Label><div className="flex flex-wrap items-center gap-2"><Input className="max-w-xs" disabled={!allowed} type="file" accept="image/jpeg,image/png,image/webp" onChange={e => choosePhoto(e.target.files?.[0])} /><Input className="max-w-xs" disabled={!allowed} type="file" accept="image/*" capture="environment" onChange={e => choosePhoto(e.target.files?.[0])} /></div>{preview && <img src={preview} alt="Selected customer preview" className="mt-2 size-28 rounded-md object-cover" />}</div><div className="flex justify-end gap-2 sm:col-span-2"><Button type="button" variant="outline" onClick={() => reset()}>Clear</Button><Button disabled={!allowed || isSubmitting || saving}>{saving ? "Saving…" : "Register customer"}</Button></div></form></CardContent></Card>
    {duplicates && pending && <Card><CardHeader><CardTitle>Possible duplicate</CardTitle><CardDescription>These records share this mobile number or a similar name. Family members may share a number; confirm only if this is a separate customer.</CardDescription></CardHeader><CardContent className="space-y-3">{duplicates.map(c => <p key={c.id} className="text-sm">{c.customer_code} · {c.full_name} · {c.mobile}</p>)}<div className="flex gap-2"><Button variant="outline" onClick={() => { setDuplicates(null); setPending(null); }}>Review form</Button><Button onClick={() => void submit(pending, true)} disabled={saving}>Create separate customer</Button></div></CardContent></Card>}
  </div>;
}
function Field({ label, error, className = "", children }: { label: string; error?: string; className?: string; children: React.ReactNode }) { return <div className={`space-y-1.5 ${className}`}><Label>{label}</Label>{children}{error && <p className="text-xs text-destructive">{error}</p>}</div>; }
