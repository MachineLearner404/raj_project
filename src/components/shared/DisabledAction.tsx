import { Button, type buttonVariants } from "@/components/ui/button";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import type { VariantProps } from "class-variance-authority";

interface DisabledActionProps extends VariantProps<typeof buttonVariants> {
  label: React.ReactNode;
  reason: string;
  className?: string;
}

/**
 * A button that is visibly disabled with a hover/focus explanation —
 * never a silently non-functional control. Used for anything scheduled
 * for a later phase (e.g. Save in Settings, Export in Reports).
 */
export function DisabledAction({
  label,
  reason,
  variant = "outline",
  size = "default",
  className,
}: DisabledActionProps) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        {/* span wrapper: a native `disabled` button would not receive the
            hover/focus events the tooltip needs to appear */}
        <span tabIndex={0} className="inline-flex">
          <Button
            type="button"
            variant={variant}
            size={size}
            aria-disabled="true"
            className={`pointer-events-none opacity-60 ${className ?? ""}`}
          >
            {label}
          </Button>
        </span>
      </TooltipTrigger>
      <TooltipContent>{reason}</TooltipContent>
    </Tooltip>
  );
}
