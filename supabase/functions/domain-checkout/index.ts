// Starts a Stripe Checkout payment for the signed-in user's domain cart.
//   body: { returnUrl: "https://app.biznesthub.net/cart" }
//   returns: { url }  (the Stripe-hosted payment page; the app redirects the browser to it)
//
//   body also carries tenantId: the company buying (must be a reseller admin of it).
// Flow: read the cart -> save it as a pending order -> create a Stripe Checkout Session.
// The order only becomes "paid" in stripe-webhook, never from the browser.
//
// TEST MODE: STRIPE_SECRET_KEY must start with sk_test_ unless STRIPE_ALLOW_LIVE=true, so no real
// card can be charged by accident. Use Stripe's test card 4242 4242 4242 4242.
//
// Secrets (supabase secrets set ...):
//   STRIPE_SECRET_KEY   sk_test_...
//   STRIPE_ALLOW_LIVE   leave unset until you really go live
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!stripeKey) return json({ error: "payments not configured" }, 500);
    if (!stripeKey.startsWith("sk_test_") && Deno.env.get("STRIPE_ALLOW_LIVE") !== "true") {
      return json({ error: "Stripe is in test mode only: use an sk_test_ key" }, 500);
    }

    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return json({ error: "unauthorized" }, 401);

    // A super admin belongs to no company and never buys.
    const guard = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: adminRow } = await guard.from("app_admins").select("user_id").eq("user_id", user.id).maybeSingle();
    if (adminRow) return json({ error: "Super admins cannot purchase" }, 403);

    const { returnUrl, tenantId } = await req.json().catch(() => ({}));
    if (typeof returnUrl !== "string" || !/^https?:\/\//.test(returnUrl)) return json({ error: "returnUrl required" }, 400);
    // Only a reseller admin of the company may buy for it (same rule as software checkout).
    if (typeof tenantId !== "string") return json({ error: "tenantId required" }, 400);
    const { data: allowed } = await supabase.rpc("can_buy_for_tenant", { t: tenantId });
    if (allowed !== true) return json({ error: "Only a reseller admin can purchase domains" }, 403);

    // The cart is read with the caller's own token, so row-level security limits it to their rows.
    const { data: basket, error: cartErr } = await supabase.from("domain_cart_items").select("domain, years, panel_item_id");
    if (cartErr) throw cartErr;
    if (!basket?.length) return json({ error: "Your domain basket is empty" }, 400);

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // The price saved in the basket is never trusted (it can be stale or edited by the browser).
    // Every line is re-priced from Master Data (domain_prices view: SGD per year x years) right now.
    const { data: prices, error: priceErr } = await admin.from("domain_prices").select("tld, price_per_year");
    if (priceErr) throw priceErr;
    const cart: { domain: string; years: number; price: number; panel_item_id: string | null }[] = [];
    for (const b of basket) {
      const tld = String(b.domain).toLowerCase().split(".").slice(1).join("."); // mysite.co.uk -> co.uk
      const p = prices?.find((x) => x.tld === tld);
      if (!p) return json({ error: `No price is set for .${tld}. Remove ${b.domain} from the basket.` }, 400);
      if (!Number.isInteger(b.years) || b.years < 1 || b.years > 10) return json({ error: `${b.domain}: choose 1 to 10 years` }, 400);
      cart.push({ domain: b.domain, years: b.years, price: Math.round(Number(p.price_per_year) * b.years * 100) / 100, panel_item_id: b.panel_item_id ?? null });
    }
    const currency = "SGD";
    const total = cart.reduce((s, i) => s + i.price, 0);

    const { data: order, error: orderErr } = await admin.from("domain_orders")
      .insert({ user_id: user.id, tenant_id: tenantId, currency, total }).select("id").single();
    if (orderErr) throw orderErr;
    const { error: itemsErr } = await admin.from("domain_order_items")
      .insert(cart.map((i) => ({ order_id: order.id, domain: i.domain, years: i.years, price: i.price, panel_item_id: i.panel_item_id })));
    if (itemsErr) throw itemsErr;

    const sep = returnUrl.includes("?") ? "&" : "?";
    const form = new URLSearchParams({
      mode: "payment",
      success_url: `${returnUrl}${sep}checkout=success&order=${order.id}`,
      cancel_url: `${returnUrl}${sep}checkout=cancelled`,
      client_reference_id: order.id,
      customer_email: user.email ?? "",
      "metadata[order_id]": order.id,
    });
    if (!user.email) form.delete("customer_email");
    cart.forEach((i, n) => {
      form.set(`line_items[${n}][quantity]`, "1");
      form.set(`line_items[${n}][price_data][currency]`, currency.toLowerCase());
      // Stripe wants the smallest currency unit (cents)
      form.set(`line_items[${n}][price_data][unit_amount]`, String(Math.round(Number(i.price) * 100)));
      form.set(`line_items[${n}][price_data][product_data][name]`, `${i.domain} (${i.years} ${i.years === 1 ? "year" : "years"})`);
    });

    const res = await fetch("https://api.stripe.com/v1/checkout/sessions", {
      method: "POST",
      headers: { Authorization: `Bearer ${stripeKey}`, "Content-Type": "application/x-www-form-urlencoded" },
      body: form,
    });
    const session = await res.json();
    if (!res.ok) {
      console.error("domain-checkout: stripe replied", res.status, JSON.stringify(session).slice(0, 500));
      await admin.from("domain_orders").update({ status: "failed" }).eq("id", order.id);
      return json({ error: `Stripe: ${session?.error?.message ?? res.status}` }, 502);
    }
    await admin.from("domain_orders").update({ stripe_session_id: session.id }).eq("id", order.id);
    return json({ url: session.url });
  } catch (e) {
    console.error("domain-checkout", e);
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
