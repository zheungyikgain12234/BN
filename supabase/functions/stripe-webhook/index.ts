// Receives Stripe's "payment finished" message, marks the order paid and registers the domains.
// Deploy WITHOUT JWT verification (Stripe has no Supabase token; the signature below is the proof):
//   supabase functions deploy stripe-webhook --no-verify-jwt
// In Stripe (test mode) > Developers > Webhooks, add this function's URL for the event
// checkout.session.completed, then copy the signing secret (whsec_...).
//
// Secrets:
//   STRIPE_WEBHOOK_SECRET        whsec_...
//   DOMAIN_REGISTRATION_LIVE     "true" to really register with 20i. Anything else = TEST MODE:
//                                the order is paid (in Stripe test money) but registration is only logged.
//   TWENTYI_API_KEY              general API key (same one stackcp-sso uses)
//   TWENTYI_RESELLER_ID          optional, default "*"
//   TWENTYI_DEFAULT_CONTACT      JSON registrant details, see registerWith20i
//   LIVE MODE SPENDS REAL 20i CREDIT. Keep DOMAIN_REGISTRATION_LIVE unset unless that is intended.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const enc = (s: string) => new TextEncoder().encode(s);
const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");

// Stripe-Signature: t=<time>,v1=<hmac of "<time>.<raw body>">
async function validSignature(body: string, header: string, secret: string): Promise<boolean> {
  const parts = Object.fromEntries(header.split(",").map((p) => p.split("=") as [string, string]));
  const t = parts["t"], v1 = parts["v1"];
  if (!t || !v1) return false;
  if (Math.abs(Date.now() / 1000 - Number(t)) > 300) return false; // reject replays older than 5 minutes
  const key = await crypto.subtle.importKey("raw", enc(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const expected = hex(await crypto.subtle.sign("HMAC", key, enc(`${t}.${body}`)));
  return expected.length === v1.length && expected.split("").reduce((d, c, i) => d | (c.charCodeAt(0) ^ v1.charCodeAt(i)), 0) === 0;
}

type Item = { id: string; domain: string; years: number };

// 20i: POST /reseller/{id}/addDomain registers the domain and CHARGES THE 20i ACCOUNT BALANCE immediately.
// With too little credit the call fails and nothing is registered.
// The contact block is required by the registry. Until the app collects the customer's own details, a default
// registrant comes from the TWENTYI_DEFAULT_CONTACT secret (JSON: organisation, name, address, telephone,
// email, cc, pc, sp, city), with the customer's login email used when the secret has none.
async function registerWith20i(admin: ReturnType<typeof createClient>, userId: string, email: string | null, item: Item): Promise<void> {
  const key = Deno.env.get("TWENTYI_API_KEY");
  if (!key) throw new Error("TWENTYI_API_KEY is not set");
  const reseller = Deno.env.get("TWENTYI_RESELLER_ID") ?? "*";

  let contact: Record<string, unknown>;
  try {
    contact = JSON.parse(Deno.env.get("TWENTYI_DEFAULT_CONTACT") ?? "");
  } catch {
    throw new Error("TWENTYI_DEFAULT_CONTACT is missing or not valid JSON");
  }
  if (!contact.email && email) contact.email = email;

  // Attach the domain to the customer's own panel user, if they have one (created at first panel login).
  const { data: su } = await admin.from("stackcp_users").select("stack_user_id").eq("user_id", userId).maybeSingle();

  // years is required by 20i even though the docs example omits it ("Invalid years: 0" without it).
  const body: Record<string, unknown> = { name: item.domain, years: item.years, contact };
  if (su?.stack_user_id) body.stackUser = su.stack_user_id;

  const res = await fetch(`https://api.20i.com/reseller/${reseller}/addDomain`, {
    method: "POST",
    headers: { Authorization: `Bearer ${btoa(key)}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  console.log("20i addDomain", item.domain, res.status, text.slice(0, 500));
  if (!res.ok) throw new Error(`20i ${res.status}: ${text.slice(0, 250)}`);
  if (text.trim() === "false") throw new Error("20i refused the registration");
}

type HostingItem = { id: string; domain: string; package_type_id: string; plan_name: string; months: number };

// 20i: POST /reseller/{id}/addWeb creates the hosting package for the domain. The documented body has no
// billing period, so months is only stored on our side for now; check the first live result against 20i.
async function createHostingWith20i(admin: ReturnType<typeof createClient>, userId: string, item: HostingItem): Promise<string> {
  const key = Deno.env.get("TWENTYI_API_KEY");
  if (!key) throw new Error("TWENTYI_API_KEY is not set");
  const reseller = Deno.env.get("TWENTYI_RESELLER_ID") ?? "*";

  const { data: su } = await admin.from("stackcp_users").select("stack_user_id").eq("user_id", userId).maybeSingle();
  const body: Record<string, unknown> = { type: item.package_type_id, domain_name: item.domain, label: item.plan_name };
  if (su?.stack_user_id) body.stackUser = su.stack_user_id;

  const res = await fetch(`https://api.20i.com/reseller/${reseller}/addWeb`, {
    method: "POST",
    headers: { Authorization: `Bearer ${btoa(key)}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  console.log("20i addWeb", item.domain, res.status, text.slice(0, 500));
  if (!res.ok) throw new Error(`20i ${res.status}: ${text.slice(0, 250)}`);
  // Success looks like {"result":3965135}: the new package id. Anything else is not a confirmed creation.
  let packageId: unknown;
  try { packageId = JSON.parse(text)?.result; } catch { /* handled below */ }
  if (typeof packageId !== "number" && !(typeof packageId === "string" && packageId !== "")) {
    throw new Error(`20i did not return a package id: ${text.slice(0, 200)}`);
  }
  return String(packageId);
}

// Same shape as the domain branch below, on the hosting_* tables.
async function handleHosting(admin: ReturnType<typeof createClient>, orderId: string): Promise<Response> {
  // Only the first delivery wins: Stripe may send the same event again, and we must not create twice.
  const { data: claimed } = await admin.from("hosting_orders")
    .update({ status: "paid", paid_at: new Date().toISOString() })
    .eq("id", orderId).eq("status", "pending").select("id, user_id").maybeSingle();
  if (!claimed) return new Response("already handled");

  const live = Deno.env.get("DOMAIN_REGISTRATION_LIVE") === "true";
  const { data: items } = await admin.from("hosting_order_items").select("id, domain, package_type_id, plan_name, months").eq("order_id", orderId);
  for (const item of (items ?? []) as HostingItem[]) {
    if (!live) {
      console.log(`TEST MODE: would create ${item.plan_name} for ${item.domain} for user ${claimed.user_id}`);
      await admin.from("hosting_order_items").update({ status: "test_registered", note: "test mode: not sent to 20i" }).eq("id", item.id);
      continue;
    }
    try {
      const packageId = await createHostingWith20i(admin, claimed.user_id, item);
      await admin.from("hosting_order_items").update({ status: "registered", note: `20i package ${packageId}` }).eq("id", item.id);
    } catch (e) {
      console.error("hosting creation failed", item.domain, e);
      await admin.from("hosting_order_items").update({ status: "failed", note: String((e as Error).message ?? e).slice(0, 300) }).eq("id", item.id);
    }
  }
  await admin.from("hosting_cart_items").delete().eq("user_id", claimed.user_id).in("domain", (items ?? []).map((i) => i.domain));
  return new Response("ok");
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  if (!secret) return new Response("not configured", { status: 500 });
  const body = await req.text();
  if (!(await validSignature(body, req.headers.get("stripe-signature") ?? "", secret))) {
    return new Response("bad signature", { status: 400 });
  }

  const event = JSON.parse(body);
  if (event.type !== "checkout.session.completed") return new Response("ignored");
  const session = event.data.object;
  if (session.payment_status !== "paid") return new Response("not paid yet");
  const orderId = session.metadata?.order_id ?? session.client_reference_id;
  if (!orderId) return new Response("no order id", { status: 400 });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  if (session.metadata?.kind === "hosting") return handleHosting(admin, orderId);

  // Only the first delivery wins: Stripe may send the same event again, and we must not register twice.
  const { data: claimed } = await admin.from("domain_orders")
    .update({ status: "paid", paid_at: new Date().toISOString() })
    .eq("id", orderId).eq("status", "pending").select("id, user_id").maybeSingle();
  if (!claimed) return new Response("already handled");

  const live = Deno.env.get("DOMAIN_REGISTRATION_LIVE") === "true";
  const { data: items } = await admin.from("domain_order_items").select("id, domain, years").eq("order_id", orderId);
  for (const item of (items ?? []) as Item[]) {
    if (!live) {
      console.log(`TEST MODE: would register ${item.domain} for ${item.years} year(s) for user ${claimed.user_id}`);
      await admin.from("domain_order_items").update({ status: "test_registered", note: "test mode: not sent to 20i" }).eq("id", item.id);
      continue;
    }
    try {
      await registerWith20i(admin, claimed.user_id, session.customer_details?.email ?? session.customer_email ?? null, item);
      await admin.from("domain_order_items").update({ status: "registered" }).eq("id", item.id);
    } catch (e) {
      console.error("registration failed", item.domain, e);
      await admin.from("domain_order_items").update({ status: "failed", note: String((e as Error).message ?? e).slice(0, 300) }).eq("id", item.id);
    }
  }

  // The basket has been turned into an order, so empty the bought domains from it.
  await admin.from("domain_cart_items").delete().eq("user_id", claimed.user_id).in("domain", (items ?? []).map((i) => i.domain));
  return new Response("ok");
});
