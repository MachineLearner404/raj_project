import { useEffect, useState } from "react";
import { PageHeader } from "@/components/shared/PageHeader";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { supabase } from "@/lib/supabase/client";
import type { Database } from "@/lib/supabase/database.types";

type Audit = Database["public"]["Tables"]["audit_logs"]["Row"];
export function AuditLogPage() {
  const [rows, setRows] = useState<Audit[]>([]); const [error, setError] = useState(""); const [loading, setLoading] = useState(true);
  const load = async () => { setLoading(true); const { data, error: queryError } = await supabase.from("audit_logs").select("*").order("changed_at", { ascending: false }).limit(100); if (queryError) setError("Audit log could not be loaded."); else { setRows(data); setError(""); } setLoading(false); };
  useEffect(() => { void load(); }, []);
  return <div className="max-w-5xl space-y-6"><PageHeader title="Audit log" description="Owner-visible, append-only record of changes in the active shop." actions={<Button variant="outline" onClick={() => void load()}>Refresh</Button>} />{error ? <p role="alert" className="text-sm text-destructive">{error}</p> : <Card><CardHeader><CardTitle>Recent events</CardTitle></CardHeader><CardContent>{loading ? <p className="text-sm text-muted-foreground">Loading…</p> : rows.length ? <div className="overflow-x-auto"><table className="w-full text-left text-sm"><thead><tr className="border-b"><th className="p-2">When</th><th className="p-2">Record</th><th className="p-2">Action</th></tr></thead><tbody>{rows.map(row => <tr key={row.id} className="border-b"><td className="p-2 whitespace-nowrap">{new Date(row.changed_at).toLocaleString("en-IN")}</td><td className="p-2">{row.table_name}</td><td className="p-2">{row.action}</td></tr>)}</tbody></table></div> : <p className="text-sm text-muted-foreground">No audit events yet.</p>}</CardContent></Card>}</div>;
}
