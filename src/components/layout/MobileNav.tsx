import { useState } from "react";
import { NavLink } from "react-router-dom";
import { Gem, Menu } from "lucide-react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { navItems } from "./nav-items";
import { useAuth } from "@/features/auth/AuthProvider";

export function MobileNav() {
  const [open, setOpen] = useState(false);
  const { shop, profile } = useAuth();
  const visibleItems = navItems.filter((item) => !["/settings", "/audit"].includes(item.to) || profile?.role === "owner");

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger asChild>
        <Button variant="outline" size="icon" aria-label="Open navigation menu">
          <Menu className="size-5" />
        </Button>
      </SheetTrigger>
      <SheetContent
        side="left"
        className="w-72 bg-sidebar p-0 text-sidebar-foreground"
      >
        <SheetHeader className="border-b border-sidebar-border px-5 py-5">
          <SheetTitle className="flex items-center gap-2 text-sidebar-foreground">
            <span className="flex size-8 items-center justify-center rounded-lg bg-sidebar-primary text-sidebar-primary-foreground">
              <Gem className="size-4" />
            </span>
            {shop?.name ?? "Jewellery Loans"}
          </SheetTitle>
        </SheetHeader>
        <nav className="space-y-1 px-3 py-3">
          {visibleItems.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.to === "/"}
              onClick={() => setOpen(false)}
              className={({ isActive }) =>
                cn(
                  "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
                  isActive
                    ? "bg-sidebar-accent text-sidebar-accent-foreground"
                    : "text-sidebar-foreground/75 hover:bg-sidebar-accent/60 hover:text-sidebar-accent-foreground",
                )
              }
            >
              {({ isActive }) => (
                <>
                  <item.icon
                    className={cn(
                      "size-4",
                      isActive ? "text-sidebar-primary" : "",
                    )}
                  />
                  {item.label}
                </>
              )}
            </NavLink>
          ))}
        </nav>
      </SheetContent>
    </Sheet>
  );
}
