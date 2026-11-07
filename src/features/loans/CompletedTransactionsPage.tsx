import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { PageHeader } from "@/components/shared/PageHeader";
import { SearchBar } from "@/components/shared/SearchBar";
import { DataTable, type DataTableColumn } from "@/components/shared/DataTable";
import { EmptyState } from "@/components/shared/EmptyState";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { listCompletedTransactions, type TransactionWithRelations } from "@/lib/repositories/transactions.repository";

const money = (v: string | number) => `₹${Number(v).toLocaleString("en-IN", { minimumFractionDigits: 2 })}`;

const columns: DataTableColumn<TransactionWithRelations>[] = [
  { key: "pledge_code", header: "Pledge #", render: (t) => t.pledge_code },
  { key: "customer", header: "Customer", render: (t) => `${t.customers?.full_name} · ${t.customers?.mobile}` },
  { key: "principal_amount", header: "Principal", render: (t) => money(t.principal_amount) },
  { key: "closed_at", header: "Closed on", render: (t) => (t.closed_at ? new Date(t.closed_at).toLocaleDateString("en-IN") : "—") },
  {
    key: "closure_type",
    header: "Closure type",
    render: (t) =>
      t.closure_type === "CANCELLED" ? (
        <Badge variant="outline" className="border-transparent bg-destructive/10 text-destructive">Cancelled</Badge>
      ) : (
        <Badge variant="outline" className="border-transparent bg-emerald-500/15 text-emerald-700 dark:text-emerald-400">Redeemed</Badge>
      ),
  },
];

type ClosureFilter = "all" | "REDEEMED" | "CANCELLED";

export function CompletedTransactionsPage() {
  const [query, setQuery] = useState("");
  const [closureFilter, setClosureFilter] = useState<ClosureFilter>("all");
  const [rows, setRows] = useState<TransactionWithRelations[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    void listCompletedTransactions()
      .then(setRows)
      .catch(() => setRows([]))
      .finally(() => setLoading(false));
  }, []);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return rows.filter((t) => {
      const matchesStatus = closureFilter === "all" || t.status === closureFilter;
      const matchesQuery =
        !q ||
        t.pledge_code.toLowerCase().includes(q) ||
        t.customers?.full_name?.toLowerCase().includes(q) ||
        t.customers?.mobile?.includes(q);
      return matchesStatus && matchesQuery;
    });
  }, [rows, query, closureFilter]);

  return (
    <div>
      <PageHeader
        title="Completed Transactions"
        description="Historical record of closed pledges."
      />

      <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center">
        <div className="max-w-sm flex-1">
          <SearchBar
            value={query}
            onChange={setQuery}
            placeholder="Search by pledge #, customer, or mobile…"
          />
        </div>
        <Select
          value={closureFilter}
          onValueChange={(v) => setClosureFilter(v as ClosureFilter)}
        >
          <SelectTrigger className="w-full sm:w-44">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All closures</SelectItem>
            <SelectItem value="REDEEMED">Redeemed</SelectItem>
            <SelectItem value="CANCELLED">Cancelled</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <DataTable
        columns={columns}
        rows={filtered}
        isLoading={loading}
        getRowId={(t) => t.id}
        actions={(t) => (
          <Button variant="outline" size="sm" asChild>
            <Link to={`/transactions/${t.id}`}>View</Link>
          </Button>
        )}
        emptyState={
          <EmptyState
            title="No closed pledges"
            description="Nothing matches this search or filter yet."
          />
        }
      />
    </div>
  );
}
