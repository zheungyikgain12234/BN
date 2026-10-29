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

type BasketItem = {
  name: string; productCode: string; periodMonths: number; currency: string; price: number;
  basketPricing?: number;                                                   // the panel sends 1 for domains, 0 for VPS
  options?: unknown;                                                        // productOptionSelections, e.g. { app: null, os: "rhel7" }
  config?: unknown;                                                         // serviceConfiguration, e.g. { location: "dc_location-lhr" }
  addons?: { productCode: string; periodMonths: number; price: number }[];  // dependentItems, e.g. a VPS disk
};

// Reads the panel's CSRF pair from one of its pages (every basket call must send it back as headers).
async function panelCsrf(jar: Map<string, string>): Promise<{ name: string; value: string } | null> {
  const page = await fetch(`${PANEL}/domain-search`, { headers: { Cookie: cookieHeader(jar) } });
  absorb(jar, page);
  const html = await page.text();
  const pick = (res: RegExp[]) => { for (const r of res) { const m = html.match(r); if (m) return m[1]; } return undefined; };
  // The panel writes <meta name="Csrf-Name" content="...">, so matching must ignore case.
  const name = pick([/name="csrf[_-]name"\s+value="([^"]+)"/i, /name="csrf[_-]name"\s+content="([^"]+)"/i, /csrf[_-]name["']?\s*[:=,]\s*["']([^"']+)["']/i]);
  const value = pick([/name="csrf[_-]value"\s+value="([^"]+)"/i, /name="csrf[_-]value"\s+content="([^"]+)"/i, /csrf[_-]value["']?\s*[:=,]\s*["']([^"']+)["']/i]);
  if (!name || !value) {
    const at = html.search(/csrf/i);
    console.error("stackcp-sso basket: csrf pair not found on", page.status, "page; context:", at < 0 ? "no 'csrf' text at all" : html.slice(Math.max(0, at - 150), at + 300));
    return null;
  }
  return { name, value };
}

// Adds items to the panel's own basket (the same JSON-RPC call the panel's "Add to Basket" button makes).
// Not a documented 20i API: the panel page must expose its CSRF pair, and the call may change if the panel does.
// `id` is the item's id inside the panel basket (a 40-character hex string found in the reply), needed to remove it later.
async function addToPanelBasket(jar: Map<string, string>, items: BasketItem[]): Promise<{ name: string; ok: boolean; detail: string; id?: string }[]> {
  const csrf = await panelCsrf(jar);
  if (!csrf) return items.map((i) => ({ name: i.name, ok: false, detail: "could not read the panel's CSRF token" }));
  const out: { name: string; ok: boolean; detail: string; id?: string }[] = [];
  for (const i of items) {
    const res = await fetch(`${PANEL}/n/basket/own`, {
      method: "POST",
      headers: {
        Cookie: cookieHeader(jar), "Content-Type": "application/json", "X-Requested-With": "XMLHttpRequest",
        "csrf-name": csrf.name, "csrf-value": csrf.value, Origin: PANEL, Referer: `${PANEL}/domain-search`,
      },
      body: JSON.stringify({
        jsonrpc: "2.0", method: "addWithInfo", id: null,
        params: [{ paymentItemCountries: [] }, {
          action: null, basket_pricing: i.basketPricing ?? 1, contact: null, currency: i.currency,
          dependentItems: Object.fromEntries((i.addons ?? []).map((a, n) => [String(n), {
            action: null, basket_pricing: 0, contact: null, currency: i.currency, dependentItems: {}, name: null,
            paymentRef: null, paymentSelections: null, paymentType: "any", periodMonths: a.periodMonths,
            productCode: a.productCode, productOptionSelections: null, quotedPriceFull: a.price, quotedVAT: 0,
            service: null, serviceConfiguration: null, upgradeFromProductCode: null,
          }])),
          name: i.name,
          paymentRef: null, paymentSelections: null, paymentType: "any", periodMonths: i.periodMonths,
          productCode: i.productCode, productOptionSelections: i.options ?? null, quotedPriceFull: i.price, quotedVAT: 0,
          service: null, serviceConfiguration: i.config ?? null, upgradeFromProductCode: null,
        }],
      }),
    });
    absorb(jar, res);
    const text = await res.text();
    console.log("stackcp-sso basket add", i.name, res.status, text.slice(0, 600));
    if (!res.ok) console.log("stackcp-sso basket add: sent", JSON.stringify({ code: i.productCode, months: i.periodMonths, price: i.price, options: i.options, config: i.config, addons: i.addons }));
    let rpcError: string | undefined;
    try { rpcError = JSON.parse(text)?.error?.message; } catch { /* not JSON */ }
    const id = text.match(/\b[0-9a-f]{40}\b/i)?.[0];
    out.push({ name: i.name, ok: res.ok && !rpcError, detail: rpcError ?? (res.ok ? "added" : `panel replied ${res.status}`), id });
  }
  return out;
}

// Removes items from the panel basket (the DELETE call the panel's own "remove" button makes).
async function removeFromPanelBasket(jar: Map<string, string>, ids: string[]): Promise<{ id: string; ok: boolean; detail: string }[]> {
  const csrf = await panelCsrf(jar);
  if (!csrf) return ids.map((id) => ({ id, ok: false, detail: "could not read the panel's CSRF token" }));
  const out: { id: string; ok: boolean; detail: string }[] = [];
  for (const id of ids) {
    if (!/^[0-9a-f]{40}$/i.test(id)) { out.push({ id, ok: false, detail: "not a basket item id" }); continue; }
    const res = await fetch(`${PANEL}/n/basket/own/${id}`, {
      method: "DELETE",
      headers: {
        Cookie: cookieHeader(jar), "X-Requested-With": "XMLHttpRequest",
        "csrf-name": csrf.name, "csrf-value": csrf.value, Origin: PANEL, Referer: `${PANEL}/checkout`,
      },
    });
    absorb(jar, res);
    const text = await res.text();
    console.log("stackcp-sso basket remove", id, res.status, text.slice(0, 200));
    out.push({ id, ok: res.ok, detail: res.ok ? "removed" : `panel replied ${res.status}` });
  }
  return out;
}

// Reads the panel shop's VPS plans, operating systems and SSL certificates with the logged-in session (the same two JSON calls the
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
  // One entry per billing period a product is sold for. The entry with no action is the normal purchase price for that
  // period (renewals/upgrades carry an action); if a product has none, every entry is used. price = 20i's cost for the whole period.
  const periods = (p: any, fallbackMonths: number): { months: number; price: number }[] => {
    const all = (Array.isArray(p?.pricing) ? p.pricing : []).filter((x: any) => Number.isFinite(Number(x?.price)));
    const buy = all.filter((x: any) => x?.action == null);
    const list = buy.length ? buy : all;
    return list.length
      ? list.map((x: any) => ({ months: Number(x.periodMonths ?? fallbackMonths), price: Number(x.price) }))
      : [{ months: fallbackMonths, price: 0 }];
  };
  const plans = (Array.isArray(products) ? products : [])
    .filter((p: any) => typeof p?.code === "string" && /^vps:[a-z0-9]+$/i.test(p.code) && !p.discontinued)
    .flatMap((p: any) => periods(p, 1).map((x) => ({
      code: String(p.code),                                        // vps:a
      label: String(p.label ?? p.code),                            // 1 Core Unmanaged VPS
      months: x.months,
      price: x.price,                                              // 20i's cost for the whole period
    })));

  // SSL certificates live in the same catalogue as tls_certificate:<class-code> (e.g. tls_certificate:tucows-rapidssl).
  const sslPlans = (Array.isArray(products) ? products : [])
    .filter((p: any) => typeof p?.code === "string" && /^tls_certificate:[a-z0-9_-]+$/i.test(p.code) && !p.discontinued)
    .map((p: any) => ({
      code: String(p.code).replace(/^tls_certificate:/i, ""),      // tucows-rapidssl, the 20i class-code
      label: String(p.label ?? p.code),                            // Simple SSL
      months: Number(p.pricing?.[0]?.periodMonths ?? 12),
      price: Number(p.pricing?.[0]?.price ?? 0),                   // the shop price, only a hint
    }));

  // VPS add-ons: cPanel licences, snapshot backup and extra disks (vps_addon:cpanelpro, vps_addon:disk100GB ...).
  // spec is the 20i productSpec ("vps_addon-cpanelpro"), which is what addVpsAddon wants.
  const vpsAddons = (Array.isArray(products) ? products : [])
    .filter((p: any) => typeof p?.code === "string" && /^vps_addon:(cpanel[a-z0-9]*|backup|disk\d+GB)$/i.test(p.code) && !p.discontinued)
    .flatMap((p: any) => periods(p, 1).map((x) => ({
      spec: String(p.code).replace(":", "-"),                      // vps_addon-cpanelpro
      label: String(p.label ?? p.code),                            // cPanel Pro (Max 30 Sites)
      months: x.months,
      price: x.price,                                              // 20i's cost for the whole period
    })));

  // Domains: domain:.com ... The entry with no action and a 12-month period is the yearly registration price, i.e. what 20i
  // charges the reseller (the "transfer" entries are ignored).
  const domains = (Array.isArray(products) ? products : [])
    .filter((p: any) => typeof p?.code === "string" && /^domain:\.[a-z0-9.-]+$/i.test(p.code) && !p.discontinued)
    .map((p: any) => {
      const reg = (p.pricing ?? []).find((x: any) => x?.action == null && Number(x?.periodMonths) === 12);
      return reg && Number.isFinite(Number(reg.price)) ? { tld: String(p.code).replace(/^domain:\./i, "").toLowerCase(), cost: Number(reg.price) } : null;
    })
    .filter((d: unknown) => d !== null)
    .sort((a: any, b: any) => a.tld.localeCompare(b.tld));

  // The OS list is per product; the first plan's list is the same set the order page offers.
  let os: { code: string; label: string; paid: boolean }[] = [];
  if (plans.length) {
    const reply = await get(`/n/catalogue/product/${encodeURIComponent(plans[0].code)}/vpsOSOptions`);
    const pick = (list: any, paid: boolean) => (Array.isArray(list) ? list : [])
      .filter((o: any) => typeof o?.code === "string")
      .map((o: any) => ({ code: String(o.code), label: String(o.label ?? o.code), paid }));
    os = [...pick(reply?.free, false), ...pick(reply?.paid, true)];
  }
  // Data centres: 20i has no list endpoint; the panel's own order page carries them in its script (dcLocations: [{ text: "UK",
  // id: "dc_location-lhr" }, ...]), so read them from there. Not a documented API: if the script changes this comes back empty.
  const vpsLocations: { code: string; label: string }[] = [];
  try {
    const js = await (await fetch(`${PANEL}/assets/js/page/s/order-vps.js`, { headers: { Cookie: cookieHeader(jar) } })).text();
    const block = js.match(/dcLocations\s*:\s*\[([\s\S]*?)\]/)?.[1] ?? "";
    for (const m of block.matchAll(/text\s*:\s*"([^"]+)"\s*,\s*id\s*:\s*"([^"]+)"/g)) vpsLocations.push({ code: m[2], label: m[1] });
  } catch (e) {
    console.error("stackcp-sso: could not read the VPS locations", String(e));
  }
  console.log("stackcp-sso catalogue", plans.length, "vps plans,", os.length, "operating systems,", sslPlans.length, "ssl certificates,", vpsAddons.length, "vps add-ons,", domains.length, "domains");
  return { vpsPlans: plans, vpsOs: os, vpsLocations, sslPlans, vpsAddons, domains };
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
    let { data: { user } } = await supabase.auth.getUser();
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    // The stripe-webhook has no user token: it calls with the service-role key and names the user whose basket to clean.
    const bearer = (req.headers.get("Authorization") ?? "").replace(/^Bearers+/i, "");
    if (!user && body?.userId && bearer === Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")) {
      user = (await admin.auth.admin.getUserById(String(body.userId))).data.user;
    }
    if (!user?.email) return json({ error: "unauthorized" }, 401);
    const password = await panelPassword(user.id);

    // 2. Their StackCP user (create on first use).
    const { data: row } = await admin.from("stackcp_users").select("stack_user_id, panel_username").eq("user_id", user.id).maybeSingle();
    let ref = row?.stack_user_id as string | undefined;
    let username = row?.panel_username as string | undefined;
    if (!ref || !username) {
      const existing = await findStackUserRef(user.email);
      if (existing) {
        // A StackCP user with this email exists but isn't ours (no mapping row): we don't know
        // whose it is, so never touch its password.
        return fallback(`a StackCP user with this email already exists (${existing})`);
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
    // Optional: take items out of the panel basket (the app's remove / clear, and the webhook after a payment).
    const removed = Array.isArray(body?.removeBasket) && body.removeBasket.length ? await removeFromPanelBasket(jar, body.removeBasket.map(String)) : undefined;
    // Optional: read the shop catalogue (VPS plans and operating systems) in this same session.
    let catalogue;
    if (body?.catalogue) {
      try { catalogue = await fetchVpsCatalogue(jar); } catch (e) { return json({ sso: true, cookies: [], catalogueError: String(e) }); }
    }
    return json({ sso: true, cookies: [...jar].map(([name, value]) => ({ name, value })), basket, removed, catalogue, panelUser });
  } catch (e) {
    return fallback(String(e));
  }
});
