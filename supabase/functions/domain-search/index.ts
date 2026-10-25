// Domain availability lookup through the 20i reseller API, so the app can show its own UI.
//   body: { term: "mybusiness" | "mybusiness.com", tlds?: ["com","net"] }
//   returns: { results: [{ domain, available, price?, currency? }] }
// Calls GET /domain-search/{term} on api.20i.com. The reply shape isn't formally documented here, so the
// result is normalised defensively; the raw reply is logged when nothing could be parsed.
// Secrets: TWENTYI_API_KEY (same one stackcp-sso uses).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const API = "https://api.20i.com";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

type Result = { domain: string; available: boolean; price?: number; currency?: string };

// 20i replies {"name":"x.com","can":"register"} when the domain is free to register ("transfer" when taken).
const isAvail = (v: unknown) => v === true || v === 1 || v === "1" || (typeof v === "string" && /^(available|free|true|register)$/i.test(v));

function normalise(raw: unknown): Result[] {
  const out: Result[] = [];
  const visit = (key: string | null, v: any) => {
    if (v == null) return;
    if (Array.isArray(v)) return v.forEach((x) => visit(null, x));
    if (typeof v === "object") {
      const name = v.name ?? v.domain ?? v.domainName ?? key;
      const status = v.can ?? v.result ?? v.available ?? v.status ?? v.availability;
      if (typeof name === "string" && name.includes(".") && status !== undefined) {
        const price = Number(v.price ?? v.cost ?? v.registerPrice ?? v.register);
        out.push({ domain: name.toLowerCase(), available: isAvail(status), ...(isFinite(price) && v.price != null ? { price, currency: v.currency } : {}) });
        return;
      }
      for (const [k, x] of Object.entries(v)) visit(k, x);
      return;
    }
    // { "example.com": 1 } style
    if (key && key.includes(".")) out.push({ domain: key.toLowerCase(), available: isAvail(v) });
  };
  visit(null, raw);
  return [...new Map(out.map((r) => [r.domain, r])).values()];
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return json({ error: "unauthorized" }, 401);
    if (!Deno.env.get("TWENTYI_API_KEY")) return json({ error: "domain search not configured" }, 500);

    const { term } = await req.json();
    const q = String(term ?? "").trim().toLowerCase().replace(/^https?:\/\//, "").replace(/^www\./, "").split("/")[0];
    if (!/^[a-z0-9][a-z0-9.-]{0,62}$/.test(q)) return json({ error: "Enter a valid domain name" }, 400);

    // One call only: a bare name ("mybusiness") is searched by 20i on every TLD it supports, and the
    // endpoint is rate limited (exceeding it blocks the key for up to 24h), so never fan out per TLD.
    const res = await fetch(`${API}/domain-search/${encodeURIComponent(q)}`, {
      headers: { Authorization: `Bearer ${btoa(Deno.env.get("TWENTYI_API_KEY")!)}` },
    });
    const text = await res.text();
    if (!res.ok) {
      console.error("domain-search: 20i replied", res.status, text.slice(0, 500));
      return json({ error: `Domain lookup failed (${res.status}): ${text.slice(0, 200)}` }, 502);
    }
    // The reply is newline-delimited JSON, so parse each line on its own.
    const raws = text.split("\n").map((l) => l.trim().replace(/^,|,$/g, "").trim()).filter((l) => l && l !== "[" && l !== "]")
      .map((l) => { try { return JSON.parse(l); } catch { return null; } });
    const found = normalise(raws);
    if (found.length === 0) console.error("domain-search: unparsed reply", text.slice(0, 500));
    console.log("domain-search sample", text.slice(0, 800));
    const results = found;
    return json({ results });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
