import { TrendingUp, TrendingDown, Minus } from "lucide-react";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { cn } from "@/lib/utils";
import type { DashboardMetric } from "@/types/domain";

const trendConfig = {
  up: { icon: TrendingUp, className: "text-emerald-600 dark:text-emerald-400" },
  down: { icon: TrendingDown, className: "text-destructive" },
  flat: { icon: Minus, className: "text-muted-foreground" },
} as const;

export function MetricCard({ label, value, helpText, trend }: DashboardMetric) {
  const Trend = trend ? trendConfig[trend] : null;

  return (
    <Card>
      <CardHeader className="pb-2">
        <p className="text-sm font-medium text-muted-foreground">{label}</p>
      </CardHeader>
      <CardContent className="space-y-1">
        <div className="flex items-center gap-2">
          <p className="text-2xl font-semibold tracking-tight text-foreground">
            {value}
          </p>
          {Trend && (
            <Trend.icon className={cn("size-4", Trend.className)} />
          )}
        </div>
        <p className="text-xs text-muted-foreground">{helpText}</p>
      </CardContent>
    </Card>
  );
}
