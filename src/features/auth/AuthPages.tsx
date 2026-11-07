import { useState, type FormEvent } from "react";
import { Navigate, useNavigate, useSearchParams } from "react-router-dom";
import { Gem } from "lucide-react";
import { supabase } from "@/lib/supabase/client";
import { useAuth } from "./AuthProvider";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

function AuthCard({ title, description, children }: { title: string; description: string; children: React.ReactNode }) {
  return <main className="flex min-h-screen items-center justify-center bg-muted/30 p-4"><Card className="w-full max-w-md"><CardHeader><div className="mb-2 flex size-10 items-center justify-center rounded-lg bg-primary text-primary-foreground"><Gem /></div><CardTitle>{title}</CardTitle><CardDescription>{description}</CardDescription></CardHeader><CardContent>{children}</CardContent></Card></main>;
}

export function LoginPage() {
  const { session } = useAuth();
  const [email, setEmail] = useState(""); const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null); const [busy, setBusy] = useState(false);
  const navigate = useNavigate(); const [params] = useSearchParams();
  if (session) return <Navigate to="/" replace />;
  async function submit(event: FormEvent) {
    event.preventDefault(); setError(null); setBusy(true);
    const { error: signInError } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    setBusy(false);
    if (signInError) setError("Email or password is incorrect. Please try again.");
    else navigate(params.get("next") || "/", { replace: true });
  }
  return <AuthCard title="Sign in" description="Use your shop account to continue."><form className="space-y-4" onSubmit={submit}><div className="space-y-1.5"><Label htmlFor="email">Email</Label><Input id="email" autoComplete="email" type="email" required value={email} onChange={e => setEmail(e.target.value)} /></div><div className="space-y-1.5"><Label htmlFor="password">Password</Label><Input id="password" autoComplete="current-password" type="password" minLength={8} required value={password} onChange={e => setPassword(e.target.value)} /></div>{error && <p role="alert" className="text-sm text-destructive">{error}</p>}<Button className="w-full" type="submit" disabled={busy}>{busy ? "Signing in…" : "Sign in"}</Button><Button className="w-full" variant="link" type="button" onClick={() => navigate("/forgot-password")}>Forgot password?</Button></form></AuthCard>;
}

export function ForgotPasswordPage() {
  const [email, setEmail] = useState(""); const [notice, setNotice] = useState<string | null>(null); const [busy, setBusy] = useState(false);
  async function submit(event: FormEvent) { event.preventDefault(); setBusy(true); const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo: `${window.location.origin}/reset-password` }); setBusy(false); setNotice(error ? "We could not send a reset email. Check the address and try again." : "If an account exists for that email, a password-reset link is on its way."); }
  return <AuthCard title="Reset your password" description="We’ll email a secure reset link."><form className="space-y-4" onSubmit={submit}><div className="space-y-1.5"><Label htmlFor="reset-email">Email</Label><Input id="reset-email" type="email" autoComplete="email" required value={email} onChange={e => setEmail(e.target.value)} /></div>{notice && <p role="status" className="text-sm text-muted-foreground">{notice}</p>}<Button className="w-full" disabled={busy}>{busy ? "Sending…" : "Send reset link"}</Button></form></AuthCard>;
}

export function ResetPasswordPage() {
  const [password, setPassword] = useState(""); const [notice, setNotice] = useState<string | null>(null); const [busy, setBusy] = useState(false); const navigate = useNavigate();
  async function submit(event: FormEvent) { event.preventDefault(); setBusy(true); const { error } = await supabase.auth.updateUser({ password }); setBusy(false); if (error) setNotice("This reset link is invalid or expired. Request a new one."); else { setNotice("Password updated. You can now sign in."); setTimeout(() => navigate("/login", { replace: true }), 700); } }
  return <AuthCard title="Choose a new password" description="Use at least 8 characters."><form className="space-y-4" onSubmit={submit}><div className="space-y-1.5"><Label htmlFor="new-password">New password</Label><Input id="new-password" type="password" autoComplete="new-password" required minLength={8} value={password} onChange={e => setPassword(e.target.value)} /></div>{notice && <p role="status" className="text-sm text-muted-foreground">{notice}</p>}<Button className="w-full" disabled={busy}>{busy ? "Saving…" : "Save new password"}</Button></form></AuthCard>;
}
