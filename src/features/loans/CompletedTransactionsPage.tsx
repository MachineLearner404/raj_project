import { useMemo, useState } from "react";
import { PageHeader } from "@/components/shared/PageHeader";
import { SearchBar } from "@/components/shared/SearchBar";
import { DataTable, type DataTableColumn } from "@/components/shared/DataTable";
import { StatusBadge } from "@/components/shared/StatusBadge";
import { EmptyState } from "@/components/shared/EmptyState";
import { DisabledAction } from "@/components/shared/DisabledAction";
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
    header: "Total interest paid",
    render: (l) => `₹${l.interestAccrued.toLocaleString("en-IN")}`,
  },
  { key: "dueDate", header: "Closed by", render: (l) => l.dueDate },
  {
    key: "status",
    header: "Closure type",
    render: (l) => <StatusBadge status={l.status} />,
  },
];

type ClosureFilter = "all" | LoanStatus;

export function CompletedTransactionsPage() {
  const [query, setQuery] = useState("");
  const [closureFilter, setClosureFilter] = useState<ClosureFilter>("all");

  const closedLoans = useMemo(
    () =>
      demoLoans.filter((l) => l.status === "completed" || l.status === "auctioned"),
    [],
  );

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return closedLoans.filter((loan) => {
      const matchesStatus = closureFilter === "all" || loan.status === closureFilter;
      const matchesQuery =
        !q ||
        loan.loanNumber.toLowerCase().includes(q) ||
        loan.customerName.toLowerCase().includes(q);
      return matchesStatus && matchesQuery;
    });
  }, [closedLoans, query, closureFilter]);

  return (
    <div>
      <PageHeader
        title="Completed Transactions"
        description="Historical record of closed loans."
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
          value={closureFilter}
          onValueChange={(v) => setClosureFilter(v as ClosureFilter)}
        >
          <SelectTrigger className="w-full sm:w-44">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All closures</SelectItem>
            <SelectItem value="completed">Completed</SelectItem>
            <SelectItem value="auctioned">Auctioned</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <DataTable
        columns={columns}
        rows={filtered}
        getRowId={(l) => l.id}
        actions={() => (
          <DisabledAction
            label="View"
            reason="Full ledger/transaction history view ships in Phase 2"
            size="sm"
          />
        )}
        emptyState={
          <EmptyState
            title="No closed loans"
            description="Nothing matches this search or filter yet."
          />
        }
      />
    </div>
  );
}
