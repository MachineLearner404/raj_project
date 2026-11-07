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
import { listActiveTransactions, type TransactionWithRelations } from "@/lib/repositories/transactions.repository";

const money = (v: string | number) => `₹${Number(v).toLocaleString("en-IN", { minimumFractionDigits: 2 })}`;
const isOverdue = (t: TransactionWithRelations) => t.due_date < new Date().toISOString().slice(0, 10);

const columns: DataTableColumn<TransactionWithRelations>[] = [
  { key: "pledge_code", header: "Pledge #", render: (t) => t.pledge_code },
  { key: "customer", header: "Customer", render: (t) => `${t.customers?.full_name} · ${t.customers?.mobile}` },
  { key: "principal_amount", header: "Principal", render: (t) => money(t.principal_amount) },
  { key: "accrued_interest", header: "Interest accrued", render: (t) => money(t.accrued_interest) },
  { key: "due_date", header: "Due date", render: (t) => t.due_date },
  {
    key: "status",
    header: "Status",
    render: (t) =>
      isOverdue(t) ? (
        <Badge variant="outline" className="border-transparent bg-amber-500/15 text-amber-700 dark:text-amber-400">Overdue</Badge>
      ) : (
        <Badge variant="outline" className="border-transparent bg-secondary text-secondary-foreground">
          {t.status === "PARTIALLY_PAID" ? "Partially paid" : "Active"}
        </Badge>
      ),
  },
];

type StatusFilter = "all" | "ACTIVE" | "PARTIALLY_PAID" | "OVERDUE";

export function ActiveTransactionsPage() {
  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [rows, setRows] = useState<TransactionWithRelations[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    void listActiveTransactions()
      .then(setRows)
      .catch(() => setRows([]))
      .finally(() => setLoading(false));
  }, []);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return rows.filter((t) => {
      const matchesStatus =
        statusFilter === "all" ||
        (statusFilter === "OVERDUE" ? isOverdue(t) : t.status === statusFilter);
      const matchesQuery =
        !q ||
        t.pledge_code.toLowerCase().includes(q) ||
        t.customers?.full_name?.toLowerCase().includes(q) ||
        t.customers?.mobile?.includes(q);
      return matchesStatus && matchesQuery;
    });
  }, [rows, query, statusFilter]);

  return (
    <div>
      <PageHeader
        title="Active Transactions"
        description="Pledges currently open — active and partially paid."
        actions={
          <Button asChild>
            <Link to="/loans/new">New Jewellery Loan</Link>
          </Button>
        }
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
          value={statusFilter}
          onValueChange={(v) => setStatusFilter(v as StatusFilter)}
        >
          <SelectTrigger className="w-full sm:w-44">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All statuses</SelectItem>
            <SelectItem value="ACTIVE">Active</SelectItem>
            <SelectItem value="PARTIALLY_PAID">Partially paid</SelectItem>
            <SelectItem value="OVERDUE">Overdue</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <DataTable
        columns={columns}
        rows={filtered}
        isLoading={loading}
        getRowId={(t) => t.id}
        actions={(t) => (
          <>
            <Button variant="outline" size="sm" asChild>
              <Link to={`/payments/new?loanId=${t.id}`}>Receive Payment</Link>
            </Button>
            <Button variant="outline" size="sm" asChild>
              <Link to={`/transactions/${t.id}`}>View</Link>
            </Button>
          </>
        )}
        emptyState={
          <EmptyState
            title="No open pledges"
            description={
              query || statusFilter !== "all"
                ? "Try a different search or filter."
                : "No active or partially paid pledges right now."
            }
          />
        }
      />
    </div>
  );
}
