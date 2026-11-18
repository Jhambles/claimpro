"use client";
import { useEffect, useState } from "react";
import { useSession } from "next-auth/react";
import { Sidebar } from "@/components/ui/Sidebar";
import { getAdminNav } from "@/lib/adminNav";

interface AdminUser {
  id: string;
  name: string;
  email: string;
  role: "CLIENT" | "PROCESSOR" | "ADMIN";
  createdAt: string;
  verificationStatus: "PENDING" | "APPROVED" | "REJECTED";
  idDocumentName: string | null;
}

export default function IdentityManagerPage() {
  const { data: session } = useSession();
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [form, setForm] = useState({ name: "", email: "", password: "", role: "CLIENT" as AdminUser["role"] });
  const [error, setError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [reviewError, setReviewError] = useState<string | null>(null);

  async function load() {
    setLoading(true);
    const res = await fetch("/api/admin/users");
    setUsers(res.ok ? await res.json() : []);
    setLoading(false);
  }

  useEffect(() => {
    // Standard client-side data fetch on mount â€” this rule targets state
    // that could be computed synchronously during render instead; there's
    // no way to have this data (a server response) at render time, so an
    // effect + setState is the correct, unavoidable pattern here.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, []);

  async function createUser() {
    setError(null);
    setCreating(true);
    const res = await fetch("/api/admin/users", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(form),
    });
    setCreating(false);
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      setError(typeof body.error === "string" ? body.error : "Could not create user.");
      return;
    }
    setForm({ name: "", email: "", password: "", role: "CLIENT" });
    load();
  }

  async function reviewUser(id: string, status: "APPROVED" | "REJECTED") {
    setReviewError(null);
    const res = await fetch(`/api/admin/users/${id}/verification`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status }),
    });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      setReviewError(typeof body.error === "string" ? body.error : "Could not update ID verification.");
      return;
    }
    await load();
  }

  return (
    <div className="bg-navy min-h-screen text-white flex">
      <Sidebar brand="ADMIN CORE" items={getAdminNav(session?.user?.role)} active="Identity Manager" />

      <main className="flex-1 p-16">
        <h1 className="text-5xl font-black mb-2 tracking-tighter">Identity Manager</h1>
        <p className="text-slate-400 uppercase text-[10px] tracking-[0.5em] mb-12">User Provisioning &amp; Roles</p>

        <div className="bg-white/5 p-8 rounded-[2rem] border border-white/10 mb-10 max-w-3xl">
          <h3 className="text-lg font-bold mb-6">Provision New Account</h3>
          <div className="grid grid-cols-2 gap-4 mb-4">
            <input
              placeholder="Full name"
              value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
              className="bg-white/5 border border-white/10 rounded-xl px-4 py-3 outline-none focus:border-teal placeholder:text-slate-500"
            />
            <input
              placeholder="Email"
              value={form.email}
              onChange={(e) => setForm({ ...form, email: e.target.value })}
              className="bg-white/5 border border-white/10 rounded-xl px-4 py-3 outline-none focus:border-teal placeholder:text-slate-500"
            />
            <input
              placeholder="Temporary password"
              type="password"
              value={form.password}
              onChange={(e) => setForm({ ...form, password: e.target.value })}
              className="bg-white/5 border border-white/10 rounded-xl px-4 py-3 outline-none focus:border-teal placeholder:text-slate-500"
            />
            <select
              value={form.role}
              onChange={(e) => setForm({ ...form, role: e.target.value as AdminUser["role"] })}
              className="bg-white/5 border border-white/10 rounded-xl px-4 py-3 outline-none focus:border-teal"
            >
              <option value="CLIENT" className="text-black">Claimant</option>
              <option value="PROCESSOR" className="text-black">Processor</option>
              <option value="ADMIN" className="text-black">Admin</option>
            </select>
          </div>
          {error && <p className="text-red-400 text-xs font-bold mb-3">{error}</p>}
          <button
            onClick={createUser}
            disabled={creating}
            className="bg-teal text-white px-6 py-3 rounded-xl font-bold hover:opacity-90 transition disabled:opacity-50"
          >
            {creating ? "Creatingâ€¦" : "Create Account"}
          </button>
        </div>

        {reviewError && <p role="alert" className="text-red-400 text-sm font-bold mb-4">{reviewError}</p>}
        <div className="bg-white/5 rounded-[2rem] border border-white/10 overflow-x-auto">
          <table className="w-full text-left">
            <thead className="text-[10px] text-slate-400 uppercase tracking-widest">
              <tr>
                <th className="p-6">Name</th>
                <th className="p-6">Email</th>
                <th className="p-6">Role</th>
                <th className="p-6">Joined</th>
                <th className="p-6">ID Verification</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {users.map((u) => (
                <tr key={u.id}>
                  <td className="p-6 font-bold">{u.name}</td>
                  <td className="p-6 text-slate-400">{u.email}</td>
                  <td className="p-6"><span className="text-[10px] bg-teal-500/20 text-teal-400 px-3 py-1 rounded-full font-black uppercase">{u.role}</span></td>
                  <td className="p-6 text-slate-400 text-sm">{new Date(u.createdAt).toLocaleDateString()}</td>
                  <td className="p-6">
                    {u.idDocumentName && (
                      <a href={`/api/admin/users/${u.id}/id-document`} target="_blank" rel="noreferrer"
                        className="text-teal-400 underline text-sm">View ID</a>
                    )}
                    <span className="block text-xs text-slate-400 mt-1">{u.verificationStatus}</span>
                    {u.verificationStatus === "PENDING" && (
                      <div className="flex gap-2 mt-3">
                        <button onClick={() => reviewUser(u.id, "APPROVED")}
                          className="bg-teal-600 text-white px-3 py-2 rounded-lg text-xs font-bold hover:bg-teal-500">
                          Approve
                        </button>
                        <button onClick={() => reviewUser(u.id, "REJECTED")}
                          className="bg-red-600 text-white px-3 py-2 rounded-lg text-xs font-bold hover:bg-red-500">
                          Reject
                        </button>
                      </div>
                    )}
                  </td>
                </tr>
              ))}
              {!loading && users.length === 0 && (
                <tr><td colSpan={5} className="p-10 text-center text-slate-400">No users yet.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </main>
    </div>
  );
}
