import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import type { LoanStatus } from "@/types/domain";

const statusConfig: Record<
  LoanStatus,
  { label: string; className: string }
> = {
  active: {
    label: "Active",
    className: "bg-secondary text-secondary-foreground",
  },
  overdue: {
    label: "Overdue",
    className:
      "bg-amber-500/15 text-amber-700 dark:text-amber-400",
  },
  completed: {
    label: "Completed",
    className:
      "bg-emerald-500/15 text-emerald-700 dark:text-emerald-400",
  },
  auctioned: {
    label: "Auctioned",
    className: "bg-destructive/10 text-destructive",
  },
};

export function StatusBadge({ status }: { status: LoanStatus }) {
  const config = statusConfig[status];
  return (
    <Badge variant="outline" className={cn("border-transparent", config.className)}>
      {config.label}
    </Badge>
  );
}
