import { Navigate, Outlet, useLocation } from "react-router-dom";
import { LoadingState } from "@/components/shared/LoadingState";
import { useAuth } from "./AuthProvider";
import type { ProfileRole } from "@/lib/supabase/database.types";

export function RequireAuth() {
  const { session, loading, error } = useAuth();
  const location = useLocation();
  if (loading) return <LoadingState className="p-6" />;
  if (!session) return <Navigate to={`/login?next=${encodeURIComponent(location.pathname)}`} replace />;
  if (error) return <div className="p-6 text-sm text-destructive" role="alert">{error}</div>;
  return <Outlet />;
}

export function RequireOnboarding() {
  const { profile, shop, loading } = useAuth();
  if (loading) return <LoadingState className="p-6" />;
  if (!profile || !shop?.onboarding_completed_at) return <Navigate to="/onboarding" replace />;
  return <Outlet />;
}

export function RequireRole({ roles }: { roles: ProfileRole[] }) {
  const { profile, loading } = useAuth();
  if (loading) return <LoadingState className="p-6" />;
  if (!profile || !roles.includes(profile.role)) return <Navigate to="/" replace />;
  return <Outlet />;
}
