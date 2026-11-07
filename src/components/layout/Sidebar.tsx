import { NavLink } from "react-router-dom";
import { Gem } from "lucide-react";
import { cn } from "@/lib/utils";
import { navItems } from "./nav-items";
import { useAuth } from "@/features/auth/AuthProvider";

export function Sidebar() {
  const { shop, profile } = useAuth();
  const visibleItems = navItems.filter((item) => !["/settings", "/audit"].includes(item.to) || profile?.role === "owner");
  return (
    <aside className="hidden w-64 shrink-0 flex-col border-r border-sidebar-border bg-sidebar text-sidebar-foreground md:flex">
      <div className="flex items-center gap-2 px-5 py-5">
        <span className="flex size-9 items-center justify-center rounded-lg bg-sidebar-primary text-sidebar-primary-foreground">
          <Gem className="size-5" />
        </span>
        <div className="flex flex-col leading-tight">
          <span className="text-sm font-semibold">{shop?.name ?? "Jewellery Loans"}</span>
          <span className="text-xs text-sidebar-foreground/60">
            Jewellery Loans
          </span>
        </div>
      </div>

      <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-2">
        {visibleItems.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.to === "/"}
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

      <div className="border-t border-sidebar-border px-5 py-4 text-xs text-sidebar-foreground/50">
        {profile?.role ?? "Member"} account
      </div>
    </aside>
  );
}
