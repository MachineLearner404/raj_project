import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import type { Session, User } from "@supabase/supabase-js";
import { supabase } from "@/lib/supabase/client";
import type { Database } from "@/lib/supabase/database.types";

type Profile = Database["public"]["Tables"]["profiles"]["Row"];
type Shop = Database["public"]["Tables"]["shops"]["Row"];
type Settings = Database["public"]["Tables"]["app_settings"]["Row"];
type Membership = Database["public"]["Tables"]["shop_memberships"]["Row"];

type AuthState = {
  session: Session | null;
  user: User | null;
  profile: Profile | null;
  shop: Shop | null;
  settings: Settings | null;
  memberships: Membership[];
  availableShops: Pick<Shop, "id" | "name">[];
  loading: boolean;
  error: string | null;
  refresh: () => Promise<void>;
  signOut: () => Promise<void>;
  switchShop: (shopId: string) => Promise<void>;
};

const AuthContext = createContext<AuthState | null>(null);

function message(error: unknown) {
  return error instanceof Error ? error.message : "We could not load your account. Please try again.";
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [shop, setShop] = useState<Shop | null>(null);
  const [settings, setSettings] = useState<Settings | null>(null);
  const [memberships, setMemberships] = useState<Membership[]>([]);
  const [availableShops, setAvailableShops] = useState<Pick<Shop, "id" | "name">[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    const { data: { session: currentSession }, error: sessionError } = await supabase.auth.getSession();
    if (sessionError) {
      setError(message(sessionError));
      setLoading(false);
      return;
    }
    setSession(currentSession);
    if (!currentSession) {
      setProfile(null); setShop(null); setSettings(null); setMemberships([]); setAvailableShops([]); setError(null); setLoading(false);
      return;
    }

    const { data: currentProfile, error: profileError } = await supabase
      .from("profiles").select("*").eq("id", currentSession.user.id).maybeSingle();
    if (profileError) {
      setError(message(profileError)); setLoading(false); return;
    }
    if (!currentProfile) {
      setProfile(null); setShop(null); setSettings(null); setMemberships([]); setAvailableShops([]); setError(null); setLoading(false); return;
    }
    const { data: currentMemberships, error: membershipsError } = await supabase.from("shop_memberships").select("*").eq("is_active", true).order("created_at");
    if (membershipsError) { setError(message(membershipsError)); setLoading(false); return; }
    const activeMembership = currentMemberships.find(membership => membership.shop_id === currentProfile.active_shop_id);
    if (!activeMembership) { setError("Your active shop membership is unavailable. Please contact an owner."); setLoading(false); return; }
    const activeProfile: Profile = { ...currentProfile, shop_id: activeMembership.shop_id, role: activeMembership.role };
    setProfile(activeProfile); setMemberships(currentMemberships);
    const [{ data: currentShop, error: shopError }, { data: currentSettings, error: settingsError }, { data: shops, error: shopsError }] = await Promise.all([
      supabase.from("shops").select("*").eq("id", activeMembership.shop_id).maybeSingle(),
      supabase.from("app_settings").select("*").eq("shop_id", activeMembership.shop_id).maybeSingle(),
      supabase.from("shops").select("id,name").order("name"),
    ]);
    setShop(currentShop); setSettings(currentSettings); setAvailableShops(shops ?? []);
    setError(shopError ? message(shopError) : settingsError ? message(settingsError) : shopsError ? message(shopsError) : null);
    setLoading(false);
  }, []);

  useEffect(() => {
    void refresh();
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      // Defer DB work so it never runs inside Supabase's auth callback lock.
      queueMicrotask(() => void refresh());
    });
    return () => subscription.unsubscribe();
  }, [refresh]);

  const signOut = useCallback(async () => {
    const { error: signOutError } = await supabase.auth.signOut();
    if (signOutError) throw signOutError;
  }, []);

  const switchShop = useCallback(async (shopId: string) => {
    const { error: switchError } = await supabase.rpc("switch_active_shop", { p_shop_id: shopId });
    if (switchError) throw switchError;
    await refresh();
  }, [refresh]);

  const value = useMemo(() => ({ session, user: session?.user ?? null, profile, shop, settings, memberships, availableShops, loading, error, refresh, signOut, switchShop }), [session, profile, shop, settings, memberships, availableShops, loading, error, refresh, signOut, switchShop]);
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const value = useContext(AuthContext);
  if (!value) throw new Error("useAuth must be used inside AuthProvider");
  return value;
}
