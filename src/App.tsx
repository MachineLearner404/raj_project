import { QueryClientProvider } from "@tanstack/react-query";
import { RouterProvider } from "react-router-dom";
import { queryClient } from "@/app/query-client";
import { router } from "@/app/router";
import { ErrorBoundary } from "@/app/ErrorBoundary";
import { TooltipProvider } from "@/components/ui/tooltip";
import { Toaster } from "@/components/ui/sonner";
import { AuthProvider } from "@/features/auth/AuthProvider";
import { IdleLock } from "@/features/auth/IdleLock";

// No ThemeProvider: Phase 1 ships a single light theme (no dark-mode
// toggle in scope). next-themes' provider injects an SSR-hydration
// <script> that's meaningless (and warns) in a plain Vite CSR app —
// the Toaster's useTheme() call degrades safely to "system" without it.

function App() {
  return (
    <ErrorBoundary>
      <QueryClientProvider client={queryClient}>
        <AuthProvider>
        <TooltipProvider>
          <RouterProvider router={router} />
          <IdleLock />
          <Toaster position="bottom-right" />
        </TooltipProvider>
        </AuthProvider>
      </QueryClientProvider>
    </ErrorBoundary>
  );
}

export default App;
