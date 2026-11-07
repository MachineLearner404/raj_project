import { Info } from "lucide-react";

export function DemoModeBanner() {
  return (
    <div className="flex items-center gap-2 border-b border-accent bg-accent/60 px-4 py-2 text-xs text-accent-foreground sm:px-6">
      <Info className="size-3.5 shrink-0" />
      <span>
        Demo mode — sample data only. Nothing you enter here is saved to a
        database yet.
      </span>
    </div>
  );
}
