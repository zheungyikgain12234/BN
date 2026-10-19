// User management that needs the service role, so it can't run in the app.
// A user can belong to several companies, each with its own role (member | admin).
//   body: { action: "list" }
//         { action: "create", email, password, full_name?, memberships: [{ company_id, role }] }
//         { action: "update", user_id, full_name?, password?, suspended?, memberships? }
//         { action: "delete", user_id }
// Who may call it:
//   super admin (public.app_admins)            -> every user and company
//   company admin (tenant_members.role=admin)  -> only the companies they administer:
//       they see/edit just those memberships; account-wide changes (name, password, suspend, delete the
//       account) are allowed only for users who belong to no other company.
// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are injected automatically.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const fail = (error: string, status = 400) => json({ error }, status);

const BAN_FOREVER = "876000h";

type Membership = { company_id: string; role: string };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const caller = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return fail("unauthorized", 401);

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: superRow } = await admin.from("app_admins").select("user_id").eq("user_id", user.id).maybeSingle();
    const isSuper = !!superRow;

    // companies this caller administers (a super admin administers all of them)
    const { data: adminRows } = await admin.from("tenant_members").select("tenant_id").eq("user_id", user.id).eq("role", "admin");
    const myTenants = new Set((adminRows ?? []).map((r) => r.tenant_id as string));
    if (!isSuper && myTenants.size === 0) return fail("admin only", 403);

    const mayManageTenant = (t?: string | null) => !!t && (isSuper || myTenants.has(t));

    async function membershipsOf(userId: string): Promise<{ tenant_id: string; role: string }[]> {
      const { data } = await admin.from("tenant_members").select("tenant_id, role").eq("user_id", userId);
      return (data ?? []) as { tenant_id: string; role: string }[];
    }
    async function isSuperAdmin(userId: string): Promise<boolean> {
      const { data } = await admin.from("app_admins").select("user_id").eq("user_id", userId).maybeSingle();
      return !!data;
    }

    // A company admin may touch a user only if the user belongs to one of their companies (never a super admin).
    async function mayManageUser(userId: string): Promise<boolean> {
      if (isSuper) return true;
      if (await isSuperAdmin(userId)) return false;
      return (await membershipsOf(userId)).some((m) => myTenants.has(m.tenant_id));
    }
    // Account-wide changes (name, password, suspend, delete) need the user to belong to no company outside the caller's.
    async function mayEditAccount(userId: string): Promise<boolean> {
      if (isSuper) return true;
      return (await membershipsOf(userId)).every((m) => myTenants.has(m.tenant_id));
    }

    const cleanMemberships = (list: unknown): Membership[] | string => {
      if (!Array.isArray(list)) return "memberships must be a list";
      const seen = new Set<string>();
      const out: Membership[] = [];
      for (const m of list as Membership[]) {
        if (!m?.company_id) return "every membership needs a company";
        if (!mayManageTenant(m.company_id)) return "You can only use companies you administer";
        if (seen.has(m.company_id)) continue; // one row per company
        seen.add(m.company_id);
        out.push({ company_id: m.company_id, role: m.role === "admin" ? "admin" : "member" });
      }
      return out;
    };

    const b = await req.json();

    if (b.action === "list") {
      const { data: users, error } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
      if (error) return fail(error.message);
      const { data: members } = await admin.from("tenant_members").select("tenant_id, user_id, role");
      const { data: admins } = await admin.from("app_admins").select("user_id");
      const adminIds = new Set((admins ?? []).map((a) => a.user_id as string));
      const byUser = new Map<string, { tenant_id: string; role: string }[]>();
      for (const m of members ?? []) {
        const list = byUser.get(m.user_id as string) ?? [];
        list.push({ tenant_id: m.tenant_id as string, role: m.role as string });
        byUser.set(m.user_id as string, list);
      }
      const rows = [];
      for (const u of users.users) {
        const all = byUser.get(u.id) ?? [];
        const visible = isSuper ? all : all.filter((m) => myTenants.has(m.tenant_id));
        if (!isSuper && (visible.length === 0 || adminIds.has(u.id))) continue;
        rows.push({
          id: u.id,
          email: u.email,
          full_name: u.user_metadata?.full_name ?? "",
          memberships: visible.map((m) => ({ company_id: m.tenant_id, role: m.role })),
          can_edit_account: isSuper || all.every((m) => myTenants.has(m.tenant_id)),
          suspended: !!u.banned_until && new Date(u.banned_until) > new Date(),
          is_admin: adminIds.has(u.id),
          last_sign_in_at: u.last_sign_in_at,
        });
      }
      return json({ users: rows });
    }

    if (b.action === "create") {
      if (!b.email || !b.password) return fail("email and password are required");
      const memberships = cleanMemberships(b.memberships);
      if (typeof memberships === "string") return fail(memberships, 403);
      if (memberships.length === 0) return fail("add at least one company");
      const { data, error } = await admin.auth.admin.createUser({
        email: b.email,
        password: b.password,
        email_confirm: true,
        user_metadata: { full_name: b.full_name ?? "" },
      });
      if (error) return fail(error.message);
      const { error: mErr } = await admin.from("tenant_members").insert(
        memberships.map((m) => ({ tenant_id: m.company_id, user_id: data.user.id, role: m.role })),
      );
      if (mErr) {
        await admin.auth.admin.deleteUser(data.user.id); // don't leave a user with no company
        return fail(mErr.message);
      }
      return json({ id: data.user.id });
    }

    if (b.action === "update") {
      if (!b.user_id) return fail("user_id is required");
      if (!(await mayManageUser(b.user_id))) return fail("You can't manage this user", 403);

      const accountChange = b.password || b.suspended !== undefined || b.full_name !== undefined;
      if (accountChange && !(await mayEditAccount(b.user_id))) {
        return fail("This user also belongs to other companies, so only their company access can be changed here", 403);
      }
      if (b.user_id === user.id && b.suspended === true) return fail("You can't suspend yourself");

      if (accountChange) {
        const attrs: Record<string, unknown> = {};
        if (b.password) attrs.password = b.password;
        if (b.suspended !== undefined) attrs.ban_duration = b.suspended ? BAN_FOREVER : "none";
        if (b.full_name !== undefined) attrs.user_metadata = { full_name: b.full_name };
        const { error } = await admin.auth.admin.updateUserById(b.user_id, attrs);
        if (error) return fail(error.message);
        if (b.full_name !== undefined) await admin.from("profiles").update({ full_name: b.full_name }).eq("id", b.user_id);
      }

      if (b.memberships !== undefined) {
        const memberships = cleanMemberships(b.memberships);
        if (typeof memberships === "string") return fail(memberships, 403);
        // replace only the memberships the caller is allowed to manage; others stay untouched
        const existing = await membershipsOf(b.user_id);
        const managed = existing.filter((m) => mayManageTenant(m.tenant_id)).map((m) => m.tenant_id);
        const keepAtLeastOne = existing.length - managed.length + memberships.length;
        if (keepAtLeastOne === 0) return fail("A user needs at least one company. Delete the user instead.");
        if (managed.length) await admin.from("tenant_members").delete().eq("user_id", b.user_id).in("tenant_id", managed);
        if (memberships.length) {
          const { error } = await admin.from("tenant_members").insert(
            memberships.map((m) => ({ tenant_id: m.company_id, user_id: b.user_id, role: m.role })),
          );
          if (error) return fail(error.message);
        }
      }
      return json({ ok: true });
    }

    if (b.action === "delete") {
      if (!b.user_id) return fail("user_id is required");
      if (b.user_id === user.id) return fail("You can't delete your own account");
      if (!(await mayManageUser(b.user_id))) return fail("You can't manage this user", 403);
      if (!(await mayEditAccount(b.user_id))) {
        // belongs to other companies too: only take them out of this admin's companies
        await admin.from("tenant_members").delete().eq("user_id", b.user_id).in("tenant_id", [...myTenants]);
        return json({ ok: true, removed_from_company_only: true });
      }
      const { error } = await admin.auth.admin.deleteUser(b.user_id);
      if (error) return fail(error.message);
      return json({ ok: true });
    }

    return fail("unknown action");
  } catch (e) {
    return fail(String(e), 500);
  }
});
