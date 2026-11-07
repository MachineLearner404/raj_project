import { useEffect, useRef, useState, type FormEvent } from "react";
import { supabase } from "@/lib/supabase/client";
import { useAuth } from "./AuthProvider";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

const IDLE_MS = 10 * 60 * 1000;

// This is a convenience screen only. It never creates or restores an Auth
// session: the server verifies a bcrypt-hashed PIN and rate-limits failures.
export function IdleLock() {
  const { session, signOut } = useAuth();
  const [enabled, setEnabled] = useState(false); const [locked, setLocked] = useState(false); const [pin, setPin] = useState(""); const [error, setError] = useState<string | null>(null);
  const timer = useRef<number | null>(null);
  useEffect(() => {
    if (!session) return;
    void supabase.rpc("pin_is_configured", {}).then(({ data }) => setEnabled(data === true));
  }, [session]);
  useEffect(() => {
    if (!enabled || locked) return;
    const reset = () => { if (timer.current) window.clearTimeout(timer.current); timer.current = window.setTimeout(() => setLocked(true), IDLE_MS); };
    const events = ["pointerdown", "keydown", "touchstart"];
    events.forEach(event => window.addEventListener(event, reset)); reset();
    return () => { if (timer.current) window.clearTimeout(timer.current); events.forEach(event => window.removeEventListener(event, reset)); };
  }, [enabled, locked]);
  if (!locked) return null;
  async function unlock(event: FormEvent) { event.preventDefault(); setError(null); const { data, error: verifyError } = await supabase.rpc("verify_pin", { p_candidate_pin: pin }); if (verifyError) setError("Too many attempts or PIN verification failed. Sign in again or wait before retrying."); else if (!data) setError("That PIN is not correct."); else { setPin(""); setLocked(false); } }
  return <div className="fixed inset-0 z-50 grid place-items-center bg-background/95 p-4"><form onSubmit={unlock} className="w-full max-w-sm space-y-4 rounded-xl border bg-card p-6 shadow-lg"><h2 className="text-lg font-semibold">Session locked</h2><p className="text-sm text-muted-foreground">Enter your secure unlock PIN. Your authenticated session must still be valid.</p><Input aria-label="Unlock PIN" inputMode="numeric" autoComplete="one-time-code" type="password" maxLength={6} pattern="[0-9]*" required value={pin} onChange={e => setPin(e.target.value.replace(/\D/g, ""))} />{error && <p role="alert" className="text-sm text-destructive">{error}</p>}<div className="flex gap-2"><Button type="submit">Unlock</Button><Button type="button" variant="outline" onClick={() => void signOut()}>Sign out</Button></div></form></div>;
}
