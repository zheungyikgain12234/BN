// Lists the hosting plans (package types) the reseller can sell, straight from the 20i API.
//   returns: { plans: [{ id, name }] }
// Used by Master Data > Hosting prices so an admin picks a real 20i plan instead of typing its id.
// Calls GET /reseller/*/packageTypes. The reply shape isn't formally documented here, so it is
// read defensively and the raw reply is logged.
// Secrets: TWENTYI_API_KEY (same one the other functions use), TWENTYI_RESELLER_ID (default "*").
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
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return json({ error: "unauthorized" }, 401);
    const key = Deno.env.get("TWENTYI_API_KEY");
    if (!key) return json({ error: "20i not configured" }, 500);

    const reseller = Deno.env.get("TWENTYI_RESELLER_ID") ?? "*";
    const res = await fetch(`https://api.20i.com/reseller/${reseller}/packageTypes`, {
      headers: { Authorization: `Bearer ${btoa(key)}` },
    });
    const text = await res.text();
    console.log("hosting-plans sample", res.status, text.slice(0, 800));
    if (!res.ok) return json({ error: `20i replied ${res.status}: ${text.slice(0, 200)}` }, 502);

    // Either an array of plans or an object keyed by id; each plan has an id and a label/name.
    const raw = JSON.parse(text);
    const entries: [string | null, any][] = Array.isArray(raw) ? raw.map((p) => [null, p]) : Object.entries(raw);
    const plans = entries
      .map(([k, p]) => ({ id: String(p?.id ?? k ?? ""), name: String(p?.label ?? p?.name ?? p?.id ?? k ?? "") }))
      .filter((p) => p.id);
    if (plans.length === 0) console.error("hosting-plans: nothing parsed", text.slice(0, 500));
    return json({ plans });
  } catch (e) {
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
