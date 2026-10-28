// Starts a Stripe Checkout payment for the signed-in user's SSL basket.
//   body: { returnUrl: "https://app.biznesthub.net/cart", tenantId }
//   returns: { url }  (the Stripe-hosted payment page; the app redirects the browser to it)
//
// Same flow as domain-checkout and hosting-checkout: read the basket -> save it as a pending order -> create a
// Stripe Checkout Session. The order only becomes "paid" in stripe-webhook (which tells SSL from the rest by
// metadata[kind]), never from the browser.
//
// The price saved in the basket is never trusted: every line is re-priced from ssl_plan_prices here.
// Only a reseller admin of the company may buy for it.
//
// TEST MODE: STRIPE_SECRET_KEY must start with sk_test_ unless STRIPE_ALLOW_LIVE=true.
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

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: adminRow } = await admin.from("app_admins").select("user_id").eq("user_id", user.id).maybeSingle();
    if (adminRow) return json({ error: "Super admins cannot purchase" }, 403);

    const { returnUrl, tenantId } = await req.json().catch(() => ({}));
    if (typeof returnUrl !== "string" || !/^https?:\/\//.test(returnUrl)) return json({ error: "returnUrl required" }, 400);
    if (typeof tenantId !== "string") return json({ error: "tenantId required" }, 400);
    const { data: allowed } = await supabase.rpc("can_buy_for_tenant", { t: tenantId });
    if (allowed !== true) return json({ error: "Only a reseller admin can purchase SSL" }, 403);

    // The basket is read with the caller's own token, so row-level security limits it to their rows.
    const { data: basket, error: cartErr } = await supabase.from("ssl_cart_items")
      .select("class_code, months, hostname, verification, contact");
    if (cartErr) throw cartErr;
    if (!basket?.length) return json({ error: "Your SSL basket is empty" }, 400);

    const { data: prices, error: priceErr } = await admin.from("ssl_plan_prices").select("class_code, plan_name, months, price, currency");
    if (priceErr) throw priceErr;
    const cart: { class_code: string; plan_name: string; months: number; hostname: string; verification: string; contact: unknown; price: number; currency: string }[] = [];
    for (const b of basket) {
      const p = prices?.find((x) => x.class_code === b.class_code && x.months === b.months);
      if (!p) return json({ error: `No price is set for the certificate for ${b.hostname} (${b.months} months). Remove it from the basket.` }, 400);
      cart.push({ ...b, plan_name: p.plan_name, price: Number(p.price), currency: p.currency });
    }
    const currency = cart[0].currency;
    if (cart.some((i) => i.currency !== currency)) return json({ error: "Basket mixes currencies; pay for them separately" }, 400);
    const total = cart.reduce((s, i) => s + i.price, 0);

    const { data: order, error: orderErr } = await admin.from("ssl_orders")
      .insert({ user_id: user.id, tenant_id: tenantId, currency, total }).select("id").single();
    if (orderErr) throw orderErr;
    const { error: itemsErr } = await admin.from("ssl_order_items").insert(cart.map((i) => ({
      order_id: order.id, class_code: i.class_code, plan_name: i.plan_name, months: i.months, hostname: i.hostname,
      verification: i.verification, contact: i.contact, price: i.price,
    })));
    if (itemsErr) throw itemsErr;

    const sep = returnUrl.includes("?") ? "&" : "?";
    const form = new URLSearchParams({
      mode: "payment",
      success_url: `${returnUrl}${sep}checkout=success&order=${order.id}`,
      cancel_url: `${returnUrl}${sep}checkout=cancelled`,
      client_reference_id: order.id,
      customer_email: user.email ?? "",
      "metadata[order_id]": order.id,
      "metadata[kind]": "ssl",
    });
    if (!user.email) form.delete("customer_email");
    cart.forEach((i, n) => {
      form.set(`line_items[${n}][quantity]`, "1");
      form.set(`line_items[${n}][price_data][currency]`, currency.toLowerCase());
      form.set(`line_items[${n}][price_data][unit_amount]`, String(Math.round(i.price * 100)));
      form.set(`line_items[${n}][price_data][product_data][name]`, `${i.plan_name} - ${i.hostname} (${i.months} ${i.months === 1 ? "month" : "months"})`);
    });

    const res = await fetch("https://api.stripe.com/v1/checkout/sessions", {
      method: "POST",
      headers: { Authorization: `Bearer ${stripeKey}`, "Content-Type": "application/x-www-form-urlencoded" },
      body: form,
    });
    const session = await res.json();
    if (!res.ok) {
      console.error("ssl-checkout: stripe replied", res.status, JSON.stringify(session).slice(0, 500));
      await admin.from("ssl_orders").update({ status: "failed" }).eq("id", order.id);
      return json({ error: `Stripe: ${session?.error?.message ?? res.status}` }, 502);
    }
    await admin.from("ssl_orders").update({ stripe_session_id: session.id }).eq("id", order.id);
    return json({ url: session.url });
  } catch (e) {
    console.error("ssl-checkout", e);
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
