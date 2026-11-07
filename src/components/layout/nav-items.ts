import {
  LayoutDashboard,
  UserPlus,
  Gem,
  HandCoins,
  Users,
  ListChecks,
  CheckCircle2,
  BarChart3,
  Settings,
  ScrollText,
  type LucideIcon,
} from "lucide-react";

export interface NavItem {
  to: string;
  label: string;
  icon: LucideIcon;
}

export const navItems: NavItem[] = [
  { to: "/", label: "Dashboard", icon: LayoutDashboard },
  { to: "/customers/new", label: "Add Customer", icon: UserPlus },
  { to: "/loans/new", label: "New Jewellery Loan", icon: Gem },
  { to: "/payments/new", label: "Receive Payment", icon: HandCoins },
  { to: "/customers", label: "Customer Records", icon: Users },
  { to: "/loans/active", label: "Active Transactions", icon: ListChecks },
  {
    to: "/loans/completed",
    label: "Completed Transactions",
    icon: CheckCircle2,
  },
  { to: "/reports", label: "Reports", icon: BarChart3 },
  { to: "/settings", label: "Settings & Backup", icon: Settings },
  { to: "/audit", label: "Audit Log", icon: ScrollText },
];
