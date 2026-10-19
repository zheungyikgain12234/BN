// Signs the Biznest user into the white-labelled StackCP panel (cp.biznesthub.net).
//
// 20i has no "login link" API, so the server logs in on the user's behalf:
//   1. verify the caller's Supabase JWT
//   2. find (or create) their StackCP user through the 20i API; the password is derived
//      from HMAC(SSO_PASSWORD_SECRET, user id), so nothing secret is stored
//   3. fetch the panel login page, read the CSRF fields, POST /login/authenticate
//   4. return the panel's session cookies; the app sets them for the shared parent domain
//      (app.biznesthub.net -> .biznesthub.net) so the iframe opens already logged in
//
// Secrets (supabase secrets set ...):
//   TWENTYI_API_KEY        general API key from https://my.20i.com/reseller/api (do not IP-restrict it)
//   SSO_PASSWORD_SECRET    long random string; changing it breaks every derived password
//   PANEL_URL              default https://cp.biznesthub.net
//   TWENTYI_RESELLER_ID    default "*"
// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are injected automatically.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const API = "https://api.20i.com";
const PANEL = (Deno.env.get("PANEL_URL") ?? "https://cp.biznesthub.net").replace(/\/$/, "");
const RESELLER = Deno.env.get("TWENTYI_RESELLER_ID") ?? "*";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

// Falls back to the plain panel (user sees the normal StackCP login) with a reason for the logs.
const fallback = (reason: string) => {
  console.error("stackcp-sso fallback:", reason);
  return json({ sso: false, reason, cookies: [] });
};

async function api(method: "GET" | "POST", path: string, body?: unknown) {
  const res = await fetch(API + path, {
    method,
    headers: { Authorization: `Bearer ${btoa(Deno.env.get("TWENTYI_API_KEY")!)}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`20i ${method} ${path} -> ${res.status} ${text.slice(0, 300)}`);
  try { return JSON.parse(text); } catch { return text; }
}

const enc = (s: string) => new TextEncoder().encode(s);

async function panelPassword(userId: string) {
  const key = await crypto.subtle.importKey("raw", enc(Deno.env.get("SSO_PASSWORD_SECRET")!), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc(userId)));
  // suffix satisfies typical "upper + lower + digit + symbol" password rules
  return btoa(String.fromCharCode(...sig)).replace(/[+/=]/g, "x").slice(0, 32) + "aA1!";
}

// The plain susers list doesn't show a freshly created StackUser; explicitStackUserCheck does.
async function findStackUserRef(email: string): Promise<string | null> {
  const r = await api("POST", `/reseller/${RESELLER}/explicitStackUserCheck`, { email });
  const ref = r?.result;
  return typeof ref === "string" && ref.startsWith("stack-user:") ? ref : null;
}

const setPassword = (ref: string, password: string) =>
  api("POST", `/reseller/${RESELLER}/susers`, { users: { [ref]: { password } } });

// Creates the StackUser and returns its ref. The caller stores the mapping, then sets the password.
async function createStackUser(email: string, name: string): Promise<string> {
  // 20i silently ignores a newUser without a full contact (reply: ref null), so send placeholder
  // details; override per deployment with the STACKUSER_DEFAULT_* secrets.
  const d = (k: string, fallback: string) => Deno.env.get(`STACKUSER_DEFAULT_${k}`) ?? fallback;
  const created = await api("POST", `/reseller/${RESELLER}/susers`, {
    newUser: {
      person_name: name,
      company_name: d("COMPANY", ""),
      email,
      address: d("ADDRESS", "1 Raffles Place"),
      city: d("CITY", "Singapore"),
      sp: d("STATE", "Singapore"),
      pc: d("POSTCODE", "048616"),
      cc: d("COUNTRY", "SG"),
      voice: d("PHONE", "+65.60000000"),
      nominet_contact_type: "FIND",
      sendNewStackUserEmail: false,
      isAgencyClient: false,
    },
  });
  // The create reply carries the new user's ref; otherwise look it up.
  const ref = await findStackUserRef(email);
  if (!ref) throw new Error(`stack user created but not found; 20i replied: ${JSON.stringify(created).slice(0, 500)}`);
  return ref;
}

function absorb(jar: Map<string, string>, res: Response) {
  for (const c of res.headers.getSetCookie()) {
    const pair = c.split(";")[0];
    const i = pair.indexOf("=");
    if (i > 0) jar.set(pair.slice(0, i).trim(), pair.slice(i + 1).trim());
  }
}
const cookieHeader = (jar: Map<string, string>) => [...jar].map(([k, v]) => `${k}=${v}`).join("; ");

async function panelLogin(username: string, password: string): Promise<Map<string, string> | null> {
  const jar = new Map<string, string>();
  const page = await fetch(`${PANEL}/login?r=/manage`);
  absorb(jar, page);
  const html = await page.text();
  const csrfName = html.match(/name="csrf_name" value="([^"]+)"/)?.[1];
  const csrfValue = html.match(/name="csrf_value" value="([^"]+)"/)?.[1];
  if (!csrfName || !csrfValue) throw new Error("csrf fields not found on login page");

  const res = await fetch(`${PANEL}/login/authenticate`, {
    method: "POST",
    redirect: "manual",
    headers: { Cookie: cookieHeader(jar), "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ csrf_name: csrfName, csrf_value: csrfValue, username, password }),
  });
  absorb(jar, res);
  const loc = res.headers.get("location") ?? "";
  console.log("stackcp-sso authenticate ->", res.status, loc);
  if (loc.includes("failed") || jar.size === 0) return null;

  // The login-page cookie is already in the jar, so a rejected login would still look like success.
  // Confirm the session is really signed in: a protected page must not bounce back to /login.
  const check = await fetch(`${PANEL}/manage`, { redirect: "manual", headers: { Cookie: cookieHeader(jar) } });
  absorb(jar, check);
  const checkLoc = check.headers.get("location") ?? "";
  console.log("stackcp-sso session check ->", check.status, checkLoc);
  return check.status >= 300 && check.status < 400 && checkLoc.includes("login") ? null : jar;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    if (!Deno.env.get("TWENTYI_API_KEY") || !Deno.env.get("SSO_PASSWORD_SECRET")) return fallback("sso not configured");

    // 1. Who is calling?
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: { user } } = await supabase.auth.getUser();
    if (!user?.email) return json({ error: "unauthorized" }, 401);

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const password = await panelPassword(user.id);

    // 2. Their StackCP user (create on first use).
    const { data: row } = await admin.from("stackcp_users").select("stack_user_id, panel_username").eq("user_id", user.id).maybeSingle();
    let ref = row?.stack_user_id as string | undefined;
    let username = row?.panel_username as string | undefined;
    if (!ref || !username) {
      if (await findStackUserRef(user.email)) {
        // A StackCP user with this email exists but isn't ours (no mapping row): we don't know
        // whose it is, so never touch its password.
        return fallback("a StackCP user with this email already exists");
      }
      const name = (user.user_metadata?.full_name ?? user.user_metadata?.name ?? user.email.split("@")[0]) as string;
      ref = await createStackUser(user.email, name);
      // Store the mapping first so a failure after this point is recoverable (we own the user).
      await admin.from("stackcp_users").insert({ user_id: user.id, stack_user_id: ref, panel_username: user.email });
      username = user.email;
      await setPassword(ref, password);
    }

    // 3. Log in to the panel server-side and hand back the session cookies.
    const panelRef = ref!, panelUser = username!;
    let jar = await panelLogin(panelUser, password);
    if (!jar) {
      // We own this user (mapping row exists), so (re)set the derived password once and retry.
      await setPassword(panelRef, password);
      jar = await panelLogin(panelUser, password);
    }
    if (!jar) return fallback("panel login failed");
    return json({ sso: true, cookies: [...jar].map(([name, value]) => ({ name, value })) });
  } catch (e) {
    return fallback(String(e));
  }
});
