// Starts a Stripe Checkout payment for the signed-in user's hosting basket.
//   body: { returnUrl: "https://app.biznesthub.net/cart" }
//   returns: { url }  (the Stripe-hosted payment page; the app redirects the browser to it)
//
// Same flow as domain-checkout: read the basket -> save it as a pending order -> create a Stripe Checkout
// Session. The order only becomes "paid" in stripe-webhook (which tells hosting from domains by
// metadata[kind]), never from the browser.
//
// The price saved in the basket is never trusted: every line is re-priced from hosting_plan_prices here.
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

    const { returnUrl } = await req.json().catch(() => ({}));
    if (typeof returnUrl !== "string" || !/^https?:\/\//.test(returnUrl)) return json({ error: "returnUrl required" }, 400);

    // The basket is read with the caller's own token, so row-level security limits it to their rows.
    const { data: basket, error: cartErr } = await supabase.from("hosting_cart_items").select("package_type_id, months, domain");
    if (cartErr) throw cartErr;
    if (!basket?.length) return json({ error: "Your hosting basket is empty" }, 400);

    const { data: prices, error: priceErr } = await admin.from("hosting_plan_prices").select("package_type_id, plan_name, months, price, currency");
    if (priceErr) throw priceErr;
    const cart: { domain: string; package_type_id: string; plan_name: string; months: number; price: number; currency: string }[] = [];
    for (const b of basket) {
      const p = prices?.find((x) => x.package_type_id === b.package_type_id && x.months === b.months);
      if (!p) return json({ error: `No price is set for the plan on ${b.domain} (${b.months} months). Remove it from the basket.` }, 400);
      cart.push({ domain: b.domain, package_type_id: p.package_type_id, plan_name: p.plan_name, months: b.months, price: Number(p.price), currency: p.currency });
    }
    const currency = cart[0].currency;
    if (cart.some((i) => i.currency !== currency)) return json({ error: "Basket mixes currencies; pay for them separately" }, 400);
    const total = cart.reduce((s, i) => s + i.price, 0);

    const { data: order, error: orderErr } = await admin.from("hosting_orders")
      .insert({ user_id: user.id, currency, total }).select("id").single();
    if (orderErr) throw orderErr;
    const { error: itemsErr } = await admin.from("hosting_order_items")
      .insert(cart.map((i) => ({ order_id: order.id, package_type_id: i.package_type_id, plan_name: i.plan_name, months: i.months, domain: i.domain, price: i.price })));
    if (itemsErr) throw itemsErr;

    const sep = returnUrl.includes("?") ? "&" : "?";
    const form = new URLSearchParams({
      mode: "payment",
      success_url: `${returnUrl}${sep}checkout=success&order=${order.id}`,
      cancel_url: `${returnUrl}${sep}checkout=cancelled`,
      client_reference_id: order.id,
      customer_email: user.email ?? "",
      "metadata[order_id]": order.id,
      "metadata[kind]": "hosting",
    });
    if (!user.email) form.delete("customer_email");
    cart.forEach((i, n) => {
      form.set(`line_items[${n}][quantity]`, "1");
      form.set(`line_items[${n}][price_data][currency]`, currency.toLowerCase());
      form.set(`line_items[${n}][price_data][unit_amount]`, String(Math.round(i.price * 100)));
      form.set(`line_items[${n}][price_data][product_data][name]`, `${i.plan_name} for ${i.domain} (${i.months} ${i.months === 1 ? "month" : "months"})`);
    });

    const res = await fetch("https://api.stripe.com/v1/checkout/sessions", {
      method: "POST",
      headers: { Authorization: `Bearer ${stripeKey}`, "Content-Type": "application/x-www-form-urlencoded" },
      body: form,
    });
    const session = await res.json();
    if (!res.ok) {
      console.error("hosting-checkout: stripe replied", res.status, JSON.stringify(session).slice(0, 500));
      await admin.from("hosting_orders").update({ status: "failed" }).eq("id", order.id);
      return json({ error: `Stripe: ${session?.error?.message ?? res.status}` }, 502);
    }
    await admin.from("hosting_orders").update({ stripe_session_id: session.id }).eq("id", order.id);
    return json({ url: session.url });
  } catch (e) {
    console.error("hosting-checkout", e);
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
