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
    .eq("id", orderId).eq("status", "pending").select("id, user_id, tenant_id, currency").maybeSingle();
  if (!claimed) return new Response("already handled");

  const live = Deno.env.get("DOMAIN_REGISTRATION_LIVE") === "true";
  const { data: items } = await admin.from("hosting_order_items").select("id, domain, package_type_id, plan_name, months, price").eq("order_id", orderId);
  for (const item of (items ?? []) as (HostingItem & { price: number })[]) {
    let status: "test_registered" | "registered" | "failed";
    let note: string | null = null;
    if (!live) {
      console.log(`TEST MODE: would create ${item.plan_name} for ${item.domain} for user ${claimed.user_id}`);
      status = "test_registered";
      note = "test mode: not sent to 20i";
    } else {
      try {
        const packageId = await createHostingWith20i(admin, claimed.user_id, item);
        status = "registered";
        note = `20i package ${packageId}`;
      } catch (e) {
        console.error("hosting creation failed", item.domain, e);
        status = "failed";
        note = String((e as Error).message ?? e).slice(0, 300);
      }
    }
    await admin.from("hosting_order_items").update({ status, note }).eq("id", item.id);
    // The reseller's company now owns this package: it shows under Purchased Hosting, ready to assign to a client.
    // (Orders made before tenant_id existed have none, so they get no row.)
    if (claimed.tenant_id) {
      const { error } = await admin.from("purchased_hosting").insert({
        tenant_id: claimed.tenant_id, order_item_id: item.id, plan_name: item.plan_name, package_type_id: item.package_type_id,
        months: item.months, domain: item.domain, unit_price: item.price, currency: claimed.currency, status, note,
      });
      if (error) console.error("purchased_hosting insert failed", item.domain, error.message);
    }
  }
  await admin.from("hosting_cart_items").delete().eq("user_id", claimed.user_id).in("domain", (items ?? []).map((i) => i.domain));
  return new Response("ok");
}

type VpsAddon = { spec: string; label: string; months: number; price: number };
type VpsItem = { id: string; vps_type: string; plan_name: string; months: number; os_code: string; os_label: string; location: string; server_name: string; addons: VpsAddon[] };

// 20i: POST /reseller/{id}/addVpsAddon orders one add-on (cPanel licence, snapshot backup or extra disk) for an existing
// server and CHARGES THE 20i ACCOUNT BALANCE immediately; it gets its own contract, so it renews separately from the server.
// Body per the 20i docs: configuration.vpsRef (the server id), productSpec ("vps_addon-cpanelpro", "vps_addon-backup",
// "vps_addon-disk100GB"...), periodMonths, serviceType "vps_addon", and for backups options.vpsType (the server type
// without the "vps-" prefix). UNVERIFIED against a live reply, notably whether cPanel needs a compatible operating system
// and whether a brand-new server is ready for add-ons straight away.
async function addVpsAddonWith20i(admin: ReturnType<typeof createClient>, userId: string, vpsId: string, item: VpsItem, addon: VpsAddon): Promise<void> {
  const key = Deno.env.get("TWENTYI_API_KEY");
  if (!key) throw new Error("TWENTYI_API_KEY is not set");
  const reseller = Deno.env.get("TWENTYI_RESELLER_ID") ?? "*";

  const { data: su } = await admin.from("stackcp_users").select("stack_user_id").eq("user_id", userId).maybeSingle();
  const body: Record<string, unknown> = {
    configuration: { vpsRef: vpsId },
    periodMonths: addon.months,
    productSpec: addon.spec,
    serviceType: "vps_addon",
  };
  if (addon.spec === "vps_addon-backup") body.options = { vpsType: item.vps_type.replace(/^vps-/, "") };
  if (su?.stack_user_id) body.forUser = su.stack_user_id;

  const res = await fetch(`https://api.20i.com/reseller/${reseller}/addVpsAddon`, {
    method: "POST",
    headers: { Authorization: `Bearer ${btoa(key)}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  console.log("20i addVpsAddon", item.server_name, addon.spec, res.status, text.slice(0, 500));
  if (!res.ok) throw new Error(`20i ${res.status}: ${text.slice(0, 250)}`);
  let addonId: unknown;
  try { addonId = JSON.parse(text)?.result; } catch { /* handled below */ }
  if (typeof addonId !== "number" && !(typeof addonId === "string" && addonId !== "")) {
    throw new Error(`20i did not return an add-on id: ${text.slice(0, 200)}`);
  }
}

// 20i: POST /reseller/{id}/addVPS orders the server and CHARGES THE 20i ACCOUNT BALANCE immediately; with too little
// credit it fails and nothing is created. Body per the 20i docs: type ("vps-e" style), periodMonths, options.os,
// configuration.{Name, location ("dc_location-lhr" = UK, "dc_location-dfw" = USA)}, forUser. UNVERIFIED against a
// live reply: the exact type codes of your plans (vps:a in the shop is assumed to be "vps-a") and whether every OS
// code is accepted. Success is expected to return the new VPS id as {"result": <id>}, like addWeb.
async function createVpsWith20i(admin: ReturnType<typeof createClient>, userId: string, item: VpsItem): Promise<string> {
  const key = Deno.env.get("TWENTYI_API_KEY");
  if (!key) throw new Error("TWENTYI_API_KEY is not set");
  const reseller = Deno.env.get("TWENTYI_RESELLER_ID") ?? "*";

  const { data: su } = await admin.from("stackcp_users").select("stack_user_id").eq("user_id", userId).maybeSingle();
  const body: Record<string, unknown> = {
    type: item.vps_type.startsWith("vps-") ? item.vps_type : `vps-${item.vps_type}`, // "a" and "vps-a" both work
    periodMonths: item.months,
    options: { os: item.os_code },
    configuration: { Name: item.server_name, location: item.location },
  };
  if (su?.stack_user_id) body.forUser = su.stack_user_id;

  const res = await fetch(`https://api.20i.com/reseller/${reseller}/addVPS`, {
    method: "POST",
    headers: { Authorization: `Bearer ${btoa(key)}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  console.log("20i addVPS", item.server_name, res.status, text.slice(0, 500));
  if (!res.ok) throw new Error(`20i ${res.status}: ${text.slice(0, 250)}`);
  let vpsId: unknown;
  try { vpsId = JSON.parse(text)?.result; } catch { /* handled below */ }
  if (typeof vpsId !== "number" && !(typeof vpsId === "string" && vpsId !== "")) {
    throw new Error(`20i did not return a VPS id: ${text.slice(0, 200)}`);
  }
  return String(vpsId);
}

// Same shape as the hosting branch, on the vps_* tables.
async function handleVps(admin: ReturnType<typeof createClient>, orderId: string): Promise<Response> {
  // Only the first delivery wins: Stripe may send the same event again, and we must not order twice.
  const { data: claimed } = await admin.from("vps_orders")
    .update({ status: "paid", paid_at: new Date().toISOString() })
    .eq("id", orderId).eq("status", "pending").select("id, user_id, tenant_id, currency").maybeSingle();
  if (!claimed) return new Response("already handled");

  const live = Deno.env.get("DOMAIN_REGISTRATION_LIVE") === "true";
  const { data: items } = await admin.from("vps_order_items")
    .select("id, vps_type, plan_name, months, os_code, os_label, location, server_name, price, addons").eq("order_id", orderId);
  for (const item of (items ?? []) as (VpsItem & { price: number })[]) {
    let status: "test_registered" | "registered" | "failed";
    let note: string | null = null;
    if (!live) {
      console.log(`TEST MODE: would order ${item.plan_name} "${item.server_name}" for user ${claimed.user_id}`);
      status = "test_registered";
      note = "test mode: not sent to 20i";
    } else {
      try {
        const vpsId = await createVpsWith20i(admin, claimed.user_id, item);
        status = "registered";
        note = `20i VPS ${vpsId}`;
        // The server exists now. A failed add-on does not undo it: it is listed in the note so it can be ordered by hand.
        const failed: string[] = [];
        for (const addon of item.addons ?? []) {
          try {
            await addVpsAddonWith20i(admin, claimed.user_id, vpsId, item, addon);
          } catch (e) {
            console.error("vps add-on failed", item.server_name, addon.spec, e);
            failed.push(`${addon.label}: ${String((e as Error).message ?? e).slice(0, 120)}`);
          }
        }
        if (failed.length) note = `${note}; add-on(s) NOT ordered, order by hand: ${failed.join(" | ")}`.slice(0, 600);
      } catch (e) {
        console.error("vps creation failed", item.server_name, e);
        status = "failed";
        note = String((e as Error).message ?? e).slice(0, 300);
      }
    }
    await admin.from("vps_order_items").update({ status, note }).eq("id", item.id);
    if (claimed.tenant_id) {
      const { error } = await admin.from("purchased_vps").insert({
        tenant_id: claimed.tenant_id, order_item_id: item.id, plan_name: item.plan_name, vps_type: item.vps_type,
        months: item.months, os_label: item.os_label, location: item.location, server_name: item.server_name,
        // The reseller's cost is the server plus every add-on.
        unit_price: item.price + (item.addons ?? []).reduce((t, a) => t + a.price, 0), addons: item.addons ?? [], currency: claimed.currency, status, note,
      });
      if (error) console.error("purchased_vps insert failed", item.server_name, error.message);
    }
  }
  await admin.from("vps_cart_items").delete().eq("user_id", claimed.user_id).in("server_name", (items ?? []).map((i) => i.server_name));
  return new Response("ok");
}

type SslItem = { id: string; class_code: string; plan_name: string; months: number; hostname: string; verification: string; contact: Record<string, string> };

// 20i: POST /reseller/{id}/addTlsCertificate orders the certificate and CHARGES THE 20i ACCOUNT BALANCE immediately; with
// too little credit it fails and nothing is created. Body per the 20i docs: class-code, name (the site name), periodMonths and
// configuration. UNVERIFIED against a live reply: the docs say the configuration options vary by certificate type and give no
// field list, so the verification method and contact block below follow the panel's order form. Check the first live reply
// (logged below) and adjust. Success is expected to return the new certificate id as {"result": <id>}, like addWeb.
async function createSslWith20i(admin: ReturnType<typeof createClient>, userId: string, item: SslItem): Promise<string> {
  const key = Deno.env.get("TWENTYI_API_KEY");
  if (!key) throw new Error("TWENTYI_API_KEY is not set");
  const reseller = Deno.env.get("TWENTYI_RESELLER_ID") ?? "*";

  const { data: su } = await admin.from("stackcp_users").select("stack_user_id").eq("user_id", userId).maybeSingle();
  const body: Record<string, unknown> = {
    "class-code": item.class_code,
    name: item.hostname,
    periodMonths: item.months,
    configuration: { verification: item.verification, contact: item.contact },
  };
  if (su?.stack_user_id) body.forUser = su.stack_user_id;

  const res = await fetch(`https://api.20i.com/reseller/${reseller}/addTlsCertificate`, {
    method: "POST",
    headers: { Authorization: `Bearer ${btoa(key)}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  console.log("20i addTlsCertificate", item.hostname, res.status, text.slice(0, 500));
  if (!res.ok) throw new Error(`20i ${res.status}: ${text.slice(0, 250)}`);
  let certId: unknown;
  try { certId = JSON.parse(text)?.result; } catch { /* handled below */ }
  if (typeof certId !== "number" && !(typeof certId === "string" && certId !== "")) {
    throw new Error(`20i did not return a certificate id: ${text.slice(0, 200)}`);
  }
  return String(certId);
}

// Same shape as the VPS branch, on the ssl_* tables.
async function handleSsl(admin: ReturnType<typeof createClient>, orderId: string): Promise<Response> {
  // Only the first delivery wins: Stripe may send the same event again, and we must not order twice.
  const { data: claimed } = await admin.from("ssl_orders")
    .update({ status: "paid", paid_at: new Date().toISOString() })
    .eq("id", orderId).eq("status", "pending").select("id, user_id, tenant_id, currency").maybeSingle();
  if (!claimed) return new Response("already handled");

  const live = Deno.env.get("DOMAIN_REGISTRATION_LIVE") === "true";
  const { data: items } = await admin.from("ssl_order_items")
    .select("id, class_code, plan_name, months, hostname, verification, contact, price").eq("order_id", orderId);
  for (const item of (items ?? []) as (SslItem & { price: number })[]) {
    let status: "test_registered" | "registered" | "failed";
    let note: string | null = null;
    if (!live) {
      console.log(`TEST MODE: would order ${item.plan_name} for ${item.hostname} for user ${claimed.user_id}`);
      status = "test_registered";
      note = "test mode: not sent to 20i";
    } else {
      try {
        const certId = await createSslWith20i(admin, claimed.user_id, item);
        status = "registered";
        note = `20i certificate ${certId}`;
      } catch (e) {
        console.error("ssl order failed", item.hostname, e);
        status = "failed";
        note = String((e as Error).message ?? e).slice(0, 300);
      }
    }
    await admin.from("ssl_order_items").update({ status, note }).eq("id", item.id);
    if (claimed.tenant_id) {
      const { error } = await admin.from("purchased_ssl").insert({
        tenant_id: claimed.tenant_id, order_item_id: item.id, plan_name: item.plan_name, class_code: item.class_code,
        months: item.months, hostname: item.hostname, verification: item.verification,
        unit_price: item.price, currency: claimed.currency, status, note,
      });
      if (error) console.error("purchased_ssl insert failed", item.hostname, error.message);
    }
  }
  const { data: me } = await admin.from("ssl_order_items").select("hostname, class_code").eq("order_id", orderId);
  for (const i of me ?? []) {
    await admin.from("ssl_cart_items").delete().eq("user_id", claimed.user_id).eq("hostname", i.hostname).eq("class_code", i.class_code);
  }
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
  if (session.metadata?.kind === "vps") return handleVps(admin, orderId);
  if (session.metadata?.kind === "ssl") return handleSsl(admin, orderId);

  // Only the first delivery wins: Stripe may send the same event again, and we must not register twice.
  const { data: claimed } = await admin.from("domain_orders")
    .update({ status: "paid", paid_at: new Date().toISOString() })
    .eq("id", orderId).eq("status", "pending").select("id, user_id, tenant_id, currency").maybeSingle();
  if (!claimed) return new Response("already handled");

  const live = Deno.env.get("DOMAIN_REGISTRATION_LIVE") === "true";
  const { data: items } = await admin.from("domain_order_items").select("id, domain, years, price").eq("order_id", orderId);
  for (const item of (items ?? []) as (Item & { price: number })[]) {
    let status: "test_registered" | "registered" | "failed";
    let note: string | null = null;
    if (!live) {
      console.log(`TEST MODE: would register ${item.domain} for ${item.years} year(s) for user ${claimed.user_id}`);
      status = "test_registered";
      note = "test mode: not sent to 20i";
    } else {
      try {
        await registerWith20i(admin, claimed.user_id, session.customer_details?.email ?? session.customer_email ?? null, item);
        status = "registered";
      } catch (e) {
        console.error("registration failed", item.domain, e);
        status = "failed";
        note = String((e as Error).message ?? e).slice(0, 300);
      }
    }
    await admin.from("domain_order_items").update({ status, note }).eq("id", item.id);
    // The reseller's company now owns this domain: it shows under Purchased Domains, ready to assign to a client.
    // (Orders made before tenant_id existed have none, so they get no row.)
    if (claimed.tenant_id) {
      const { error } = await admin.from("purchased_domains").insert({
        tenant_id: claimed.tenant_id, order_item_id: item.id, domain: item.domain, years: item.years,
        unit_price: item.price, currency: claimed.currency, status, note,
      });
      if (error) console.error("purchased_domains insert failed", item.domain, error.message);
    }
  }

  // The basket has been turned into an order, so empty the bought domains from it.
  await admin.from("domain_cart_items").delete().eq("user_id", claimed.user_id).in("domain", (items ?? []).map((i) => i.domain));
  return new Response("ok");
});
