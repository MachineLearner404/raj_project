import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { PageHeader } from "@/components/shared/PageHeader";
import { SearchBar } from "@/components/shared/SearchBar";
import { DataTable, type DataTableColumn } from "@/components/shared/DataTable";
import { StatusBadge } from "@/components/shared/StatusBadge";
import { EmptyState } from "@/components/shared/EmptyState";
import { DisabledAction } from "@/components/shared/DisabledAction";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { demoLoans } from "@/data/demo-data";
import type { JewelleryLoan, LoanStatus } from "@/types/domain";

const columns: DataTableColumn<JewelleryLoan>[] = [
  { key: "loanNumber", header: "Loan #", render: (l) => l.loanNumber },
  { key: "customerName", header: "Customer", render: (l) => l.customerName },
  {
    key: "principalAmount",
    header: "Principal",
    render: (l) => `₹${l.principalAmount.toLocaleString("en-IN")}`,
  },
  {
    key: "interestAccrued",
    header: "Interest accrued",
    render: (l) => `₹${l.interestAccrued.toLocaleString("en-IN")}`,
  },
  { key: "dueDate", header: "Due date", render: (l) => l.dueDate },
  {
    key: "status",
    header: "Status",
    render: (l) => <StatusBadge status={l.status} />,
  },
];

type StatusFilter = "all" | LoanStatus;

export function ActiveTransactionsPage() {
  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");

  const openLoans = useMemo(
    () => demoLoans.filter((l) => l.status === "active" || l.status === "overdue"),
    [],
  );

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return openLoans.filter((loan) => {
      const matchesStatus = statusFilter === "all" || loan.status === statusFilter;
      const matchesQuery =
        !q ||
        loan.loanNumber.toLowerCase().includes(q) ||
        loan.customerName.toLowerCase().includes(q);
      return matchesStatus && matchesQuery;
    });
  }, [openLoans, query, statusFilter]);

  return (
    <div>
      <PageHeader
        title="Active Transactions"
        description="Loans currently open — active and overdue."
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
            placeholder="Search by loan # or customer…"
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
            <SelectItem value="active">Active</SelectItem>
            <SelectItem value="overdue">Overdue</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <DataTable
        columns={columns}
        rows={filtered}
        getRowId={(l) => l.id}
        actions={(loan) => (
          <>
            <Button variant="outline" size="sm" asChild>
              <Link to={`/payments/new?loanId=${loan.id}`}>Receive Payment</Link>
            </Button>
            <DisabledAction
              label="View"
              reason="Loan detail / ledger view ships in Phase 2"
              size="sm"
            />
          </>
        )}
        emptyState={
          <EmptyState
            title="No open loans"
            description={
              query || statusFilter !== "all"
                ? "Try a different search or filter."
                : "No active or overdue loans right now."
            }
          />
        }
      />
    </div>
  );
}
