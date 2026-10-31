import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (body: Record<string, unknown>, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "Invalid request." }, 400); }
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const name = typeof body.name === "string" ? body.name.trim() : "";
  const password = typeof body.password === "string" ? body.password : "";
  const code = typeof body.code === "string" ? body.code.trim().toLowerCase() : "";
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) return json({ error: "Enter the email address the manager invited." }, 400);
  if (name.length < 2 || name.length > 80) return json({ error: "Use a name between 2 and 80 characters." }, 400);
  if (password.length < 12 || password.length > 128) return json({ error: "Choose a password with at least 12 characters." }, 400);
  if (!/^[a-f0-9]{64}$/.test(code)) return json({ error: "Check the 64-character invitation code with your manager." }, 400);

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return json({ error: "Employee sign-up is temporarily unavailable. Contact your manager." }, 503);
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const valid = await admin.rpc("validate_company_invitation_signup", { p_code: code, p_email: email });
  if (valid.error || valid.data !== true) return json({ error: "Invitation is invalid, expired, already used, or issued to a different email. Ask your manager for a new one." }, 400);

  let existing: { id: string } | null = null;
  for (let page = 1; page <= 10; page++) {
    const listed = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    if (listed.error) return json({ error: "Could not check the account safely. Please try again." }, 503);
    const match = listed.data.users.find((u) => u.email?.toLowerCase() === email);
    if (match) { existing = { id: match.id }; break; }
    if (listed.data.users.length < 1000) break;
  }

  let userId = existing?.id;
  let created = false;
  if (!userId) {
    const createdUser = await admin.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { name } });
    if (createdUser.error || !createdUser.data.user) {
      return json({ error: "Could not create this account. If it already exists, the invitation can reset it only when it belongs to this company; otherwise ask your manager for help." }, 409);
    }
    userId = createdUser.data.user.id;
    created = true;
  }

  const reserved = await admin.rpc("reserve_company_invitation_signup", { p_code: code, p_email: email, p_user: userId });
  if (reserved.error || reserved.data !== true) {
    if (created) await admin.auth.admin.deleteUser(userId);
    return json({ error: "This account already belongs to a company, or this invitation was just used. Ask your manager for another invitation." }, 409);
  }

  if (existing) {
    const updated = await admin.auth.admin.updateUserById(userId, { password, email_confirm: true, user_metadata: { name } });
    if (updated.error) return json({ error: "Could not update this account. Retry with the same invitation, or ask your manager for help." }, 503);
  }
  const accepted = await admin.rpc("accept_company_invitation_signup", { p_code: code, p_email: email, p_user: userId, p_name: name });
  if (accepted.error) return json({ error: "The account is ready, but company access did not finish. Retry with the same invitation and password, or ask your manager for a fresh code." }, 503);
  return json({ ok: true });
});
