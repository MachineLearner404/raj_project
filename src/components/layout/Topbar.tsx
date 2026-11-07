import { useLocation } from "react-router-dom";
import { useState } from "react";
import { MobileNav } from "./MobileNav";
import { navItems } from "./nav-items";
import { LogOut } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/features/auth/AuthProvider";

export function Topbar() {
  const { profile, shop, availableShops, signOut, switchShop } = useAuth();
  const [switching, setSwitching] = useState(false);
  const location = useLocation();
  const current = navItems.find((item) =>
    item.to === "/"
      ? location.pathname === "/"
      : location.pathname.startsWith(item.to),
  );
  async function chooseShop(shopId: string) {
    if (shopId === shop?.id) return;
    setSwitching(true);
    try { await switchShop(shopId); } finally { setSwitching(false); }
  }

  return (
    <header className="flex items-center gap-3 border-b border-border bg-card px-4 py-3 sm:px-6">
      <div className="md:hidden">
        <MobileNav />
      </div>
      <h1 className="mr-auto text-base font-semibold text-foreground">
        {current?.label ?? "Jewellery Loan Manager"}
      </h1>
      {availableShops.length > 1 && <select aria-label="Active shop" className="hidden h-8 max-w-44 rounded-md border bg-background px-2 text-xs sm:block" value={shop?.id ?? ""} disabled={switching} onChange={event => void chooseShop(event.target.value)}>{availableShops.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select>}
      <span className="hidden text-xs text-muted-foreground sm:inline">{profile?.full_name}</span>
      <Button variant="ghost" size="sm" onClick={() => void signOut()} aria-label="Sign out"><LogOut /> <span className="hidden sm:inline">Sign out</span></Button>
    </header>
  );
}
