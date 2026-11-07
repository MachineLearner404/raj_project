import { createBrowserRouter } from "react-router-dom";
import { AppShell } from "@/components/layout/AppShell";
import { NotFoundPage } from "@/app/NotFoundPage";
import { DashboardPage } from "@/features/dashboard/DashboardPage";
import { AddCustomerPage } from "@/features/customers/AddCustomerPage";
import { CustomerRecordsPage } from "@/features/customers/CustomerRecordsPage";
import { CustomerProfilePage } from "@/features/customers/CustomerProfilePage";
import { NewLoanPage } from "@/features/loans/NewLoanPage";
import { ActiveTransactionsPage } from "@/features/loans/ActiveTransactionsPage";
import { CompletedTransactionsPage } from "@/features/loans/CompletedTransactionsPage";
import { TransactionDetailPage } from "@/features/loans/TransactionDetailPage";
import { PaymentReceiptPage } from "@/features/receipts/PaymentReceiptPage";
import { ReceivePaymentPage } from "@/features/payments/ReceivePaymentPage";
import { ReversePaymentPage } from "@/features/payments/ReversePaymentPage";
import { ReportsPage } from "@/features/reports/ReportsPage";
import { SettingsBackupPage } from "@/features/settings/SettingsBackupPage";
import { AuditLogPage } from "@/features/settings/AuditLogPage";
import { LoginPage, ForgotPasswordPage, ResetPasswordPage } from "@/features/auth/AuthPages";
import { RequireAuth, RequireOnboarding, RequireRole } from "@/features/auth/RouteGuards";
import { OnboardingPage } from "@/features/onboarding/OnboardingPage";

export const router = createBrowserRouter([
  { path: "/login", element: <LoginPage /> },
  { path: "/forgot-password", element: <ForgotPasswordPage /> },
  { path: "/reset-password", element: <ResetPasswordPage /> },
  {
    element: <RequireAuth />,
    children: [
      { path: "/onboarding", element: <OnboardingPage /> },
      {
        element: <RequireOnboarding />,
        children: [{ path: "/", element: <AppShell />, children: [
          { index: true, element: <DashboardPage /> },
          { path: "customers", element: <CustomerRecordsPage /> },
          { path: "customers/new", element: <AddCustomerPage /> },
          { path: "customers/:id", element: <CustomerProfilePage /> },
          { path: "loans/new", element: <NewLoanPage /> },
          { path: "loans/active", element: <ActiveTransactionsPage /> },
          { path: "loans/completed", element: <CompletedTransactionsPage /> },
          { path: "transactions/:id", element: <TransactionDetailPage /> },
          { path: "receipts/payment/:id", element: <PaymentReceiptPage /> },
          { path: "payments/new", element: <ReceivePaymentPage /> },
          { element: <RequireRole roles={["owner"]} />, children: [{ path: "payments/:id/reverse", element: <ReversePaymentPage /> }] },
          { path: "reports", element: <ReportsPage /> },
          { element: <RequireRole roles={["owner"]} />, children: [{ path: "settings", element: <SettingsBackupPage /> }, { path: "audit", element: <AuditLogPage /> }] },
          { path: "*", element: <NotFoundPage /> },
        ] }],
      },
    ],
  },
]);
