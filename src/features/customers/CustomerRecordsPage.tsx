import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { UserPlus } from "lucide-react";
import { PageHeader } from "@/components/shared/PageHeader";
import { SearchBar } from "@/components/shared/SearchBar";
import { DataTable, type DataTableColumn } from "@/components/shared/DataTable";
import { EmptyState } from "@/components/shared/EmptyState";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { listCustomers } from "@/lib/repositories/customers.repository";
import type { Database } from "@/lib/supabase/database.types";
type Customer = Database["public"]["Tables"]["customers"]["Row"];
const columns: DataTableColumn<Customer>[] = [{ key: "code", header: "Customer ID", render: c => c.customer_code }, { key: "name", header: "Name", render: c => c.full_name }, { key: "phone", header: "Mobile", render: c => c.mobile }, { key: "date", header: "Registered", render: c => new Date(c.created_at).toLocaleDateString("en-IN") }, { key: "status", header: "Status", render: c => <Badge variant={c.is_active ? "default" : "secondary"}>{c.is_active ? "Active" : "Archived"}</Badge> }];
export function CustomerRecordsPage() { const [query, setQuery] = useState(""); const [page,setPage]=useState(0); const [rows, setRows] = useState<Customer[]>([]); const [loading, setLoading] = useState(true); useEffect(() => { const timer = window.setTimeout(() => { setLoading(true); void listCustomers(query,page).then(setRows).catch(() => setRows([])).finally(() => setLoading(false)); }, 250); return () => window.clearTimeout(timer); }, [query,page]); return <div><PageHeader title="Customer Records" description="Debounced, paginated search by name, mobile number, or customer ID." actions={<Button asChild><Link to="/customers/new"><UserPlus />Add Customer</Link></Button>} /><div className="mb-4 max-w-sm"><SearchBar value={query} onChange={v=>{setQuery(v);setPage(0)}} placeholder="Name, mobile, or customer ID…" /></div><DataTable columns={columns} rows={rows} isLoading={loading} getRowId={c => c.id} actions={c => <Button asChild size="sm" variant="outline"><Link to={`/customers/${c.id}`}>View</Link></Button>} emptyState={<EmptyState title="No customers found" description="Try a different partial name, mobile number, or customer ID." />} /><div className="mt-3 flex gap-2"><Button variant="outline" size="sm" disabled={!page} onClick={()=>setPage(page-1)}>Previous</Button><Button variant="outline" size="sm" disabled={rows.length<25} onClick={()=>setPage(page+1)}>Next</Button></div></div>; }
