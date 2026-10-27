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

type BasketItem = { name: string; productCode: string; periodMonths: number; currency: string; price: number };

// Adds items to the panel's own basket (the same JSON-RPC call the panel's "Add to Basket" button makes).
// Not a documented 20i API: the panel page must expose its CSRF pair, and the call may change if the panel does.
async function addToPanelBasket(jar: Map<string, string>, items: BasketItem[]): Promise<{ name: string; ok: boolean; detail: string }[]> {
  const page = await fetch(`${PANEL}/domain-search`, { headers: { Cookie: cookieHeader(jar) } });
  absorb(jar, page);
  const html = await page.text();
  const pick = (res: RegExp[]) => { for (const r of res) { const m = html.match(r); if (m) return m[1]; } return undefined; };
  // The panel writes <meta name="Csrf-Name" content="...">, so matching must ignore case.
  const csrfName = pick([/name="csrf[_-]name"\s+value="([^"]+)"/i, /name="csrf[_-]name"\s+content="([^"]+)"/i, /csrf[_-]name["']?\s*[:=,]\s*["']([^"']+)["']/i]);
  const csrfValue = pick([/name="csrf[_-]value"\s+value="([^"]+)"/i, /name="csrf[_-]value"\s+content="([^"]+)"/i, /csrf[_-]value["']?\s*[:=,]\s*["']([^"']+)["']/i]);
  if (!csrfName || !csrfValue) {
    const at = html.search(/csrf/i);
    console.error("stackcp-sso basket: csrf pair not found on", page.status, "page; context:", at < 0 ? "no 'csrf' text at all" : html.slice(Math.max(0, at - 150), at + 300));
    return items.map((i) => ({ name: i.name, ok: false, detail: "could not read the panel's CSRF token" }));
  }
  const out: { name: string; ok: boolean; detail: string }[] = [];
  for (const i of items) {
    const res = await fetch(`${PANEL}/n/basket/own`, {
      method: "POST",
      headers: {
        Cookie: cookieHeader(jar), "Content-Type": "application/json", "X-Requested-With": "XMLHttpRequest",
        "csrf-name": csrfName, "csrf-value": csrfValue, Origin: PANEL, Referer: `${PANEL}/domain-search`,
      },
      body: JSON.stringify({
        jsonrpc: "2.0", method: "addWithInfo", id: null,
        params: [{ paymentItemCountries: [] }, {
          action: null, basket_pricing: 1, contact: null, currency: i.currency, dependentItems: {}, name: i.name,
          paymentRef: null, paymentSelections: null, paymentType: "any", periodMonths: i.periodMonths,
          productCode: i.productCode, productOptionSelections: null, quotedPriceFull: i.price, quotedVAT: 0,
          service: null, serviceConfiguration: null, upgradeFromProductCode: null,
        }],
      }),
    });
    absorb(jar, res);
    const text = await res.text();
    console.log("stackcp-sso basket add", i.name, res.status, text.slice(0, 300));
    let rpcError: string | undefined;
    try { rpcError = JSON.parse(text)?.error?.message; } catch { /* not JSON */ }
    out.push({ name: i.name, ok: res.ok && !rpcError, detail: rpcError ?? (res.ok ? "added" : `panel replied ${res.status}`) });
  }
  return out;
}

// Reads the panel shop's VPS plans and operating systems with the logged-in session (the same two JSON calls the
// panel's own order-vps page makes). Not a documented 20i API: the shape may change if the panel does, so every field
// is read defensively. Used by Master Data to offer "Pick from 20i" for VPS prices and operating systems.
async function fetchVpsCatalogue(jar: Map<string, string>) {
  const get = async (path: string) => {
    const res = await fetch(`${PANEL}${path}`, {
      headers: { Cookie: cookieHeader(jar), "X-Requested-With": "XMLHttpRequest", Accept: "application/json", Referer: `${PANEL}/order-vps` },
    });
    const text = await res.text();
    if (!res.ok) throw new Error(`panel ${path} replied ${res.status}: ${text.slice(0, 200)}`);
    return JSON.parse(text);
  };

  const products = await get("/a/catalogue/product");
  const plans = (Array.isArray(products) ? products : [])
    .filter((p: any) => typeof p?.code === "string" && /^vps:[a-z0-9]+$/i.test(p.code) && !p.discontinued)
    .map((p: any) => ({
      code: String(p.code),                                        // vps:a
      label: String(p.label ?? p.code),                            // 1 Core Unmanaged VPS
      months: Number(p.pricing?.[0]?.periodMonths ?? 1),
      price: Number(p.pricing?.[0]?.price ?? 0),                   // the shop's price, only a hint
    }));

  // The OS list is per product; the first plan's list is the same set the order page offers.
  let os: { code: string; label: string; paid: boolean }[] = [];
  if (plans.length) {
    const reply = await get(`/n/catalogue/product/${encodeURIComponent(plans[0].code)}/vpsOSOptions`);
    const pick = (list: any, paid: boolean) => (Array.isArray(list) ? list : [])
      .filter((o: any) => typeof o?.code === "string")
      .map((o: any) => ({ code: String(o.code), label: String(o.label ?? o.code), paid }));
    os = [...pick(reply?.free, false), ...pick(reply?.paid, true)];
  }
  console.log("stackcp-sso catalogue", plans.length, "vps plans,", os.length, "operating systems");
  return { vpsPlans: plans, vpsOs: os };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    if (!Deno.env.get("TWENTYI_API_KEY") || !Deno.env.get("SSO_PASSWORD_SECRET")) return fallback("sso not configured");
    const body = await req.json().catch(() => ({}));

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
    // Optional: push items into the panel basket in this same session, then hand the session to the browser.
    const basket = Array.isArray(body?.basket) && body.basket.length ? await addToPanelBasket(jar, body.basket as BasketItem[]) : undefined;
    // Optional: read the shop catalogue (VPS plans and operating systems) in this same session.
    let catalogue;
    if (body?.catalogue) {
      try { catalogue = await fetchVpsCatalogue(jar); } catch (e) { return json({ sso: true, cookies: [], catalogueError: String(e) }); }
    }
    return json({ sso: true, cookies: [...jar].map(([name, value]) => ({ name, value })), basket, catalogue });
  } catch (e) {
    return fallback(String(e));
  }
});
