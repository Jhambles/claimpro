"use client";
import { useSession } from "next-auth/react";
import { Sidebar } from "@/components/ui/Sidebar";
import { getAdminNav } from "@/lib/adminNav";

// This is a static manifest, not something introspected at runtime â€” if you
// add or remove a route under src/app/api, update this list to match. Kept
// deliberately simple (no reflection over the filesystem) since this is an
// internal reference page, not a source of truth for routing itself.
const ENDPOINTS: { method: string; path: string; auth: string; description: string }[] = [
  { method: "GET/POST", path: "/api/claims", auth: "Session", description: "List claims (scoped to the caller's role) / submit a new claim" },
  { method: "GET/PATCH", path: "/api/claims/:id", auth: "Session", description: "Fetch a claim's detail / transition its status" },
  { method: "GET/POST", path: "/api/claims/:id/documents", auth: "Session", description: "List / upload supporting documents for a claim" },
  { method: "GET", path: "/api/claims/:id/documents/:docId", auth: "Session", description: "Download a specific document" },
  { method: "POST", path: "/api/claims/:id/loa", auth: "Session", description: "Generate the Letter of Authorization + GCash checkout QR" },
  { method: "POST", path: "/api/claims/:id/payments", auth: "Session", description: "Start a payout checkout (GCash, Maya, PayPal, or Bank Transfer)" },
  { method: "POST", path: "/api/payments/:id/confirm", auth: "Public (sandbox)", description: "Mark a sandbox payment PAID or FAILED" },
  { method: "GET", path: "/api/notifications", auth: "Session", description: "List the caller's notifications" },
  { method: "PATCH", path: "/api/notifications/:id", auth: "Session", description: "Mark a notification as read" },
  { method: "GET", path: "/api/notifications/renewals", auth: "Session", description: "Upcoming policy renewal reminders" },
  { method: "GET/POST", path: "/api/chat", auth: "Session", description: "Fetch / send support-chat messages" },
  { method: "GET", path: "/api/admin/stats", auth: "Admin/Processor", description: "System-wide claims & LOA metrics" },
  { method: "GET/POST", path: "/api/admin/users", auth: "Admin", description: "List accounts / provision a new account" },
  { method: "GET", path: "/api/admin/security-logs", auth: "Admin", description: "Audit trail of account and claim activity" },
  { method: "*", path: "/api/auth/[...nextauth]", auth: "Public", description: "NextAuth sign-in/session endpoints" },
];

export default function ApiEndpointsPage() {
  const { data: session } = useSession();
  return (
    <div className="bg-navy min-h-screen text-white flex">
      <Sidebar brand="ADMIN CORE" items={getAdminNav(session?.user?.role)} active="API Endpoints" />

      <main className="flex-1 p-16">
        <h1 className="text-5xl font-black mb-2 tracking-tighter">API Endpoints</h1>
        <p className="text-slate-400 uppercase text-[10px] tracking-[0.5em] mb-12">Internal Route Reference</p>

        <div className="bg-white/5 rounded-[2rem] border border-white/10 overflow-hidden max-w-5xl">
          <table className="w-full text-left">
            <thead className="text-[10px] text-slate-400 uppercase tracking-widest">
              <tr>
                <th className="p-6">Method</th>
                <th className="p-6">Path</th>
                <th className="p-6">Auth</th>
                <th className="p-6">Description</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {ENDPOINTS.map((e) => (
                <tr key={e.path + e.method}>
                  <td className="p-6"><span className="text-[10px] bg-teal-500/20 text-teal-400 px-3 py-1 rounded-full font-black uppercase">{e.method}</span></td>
                  <td className="p-6 font-mono text-sm">{e.path}</td>
                  <td className="p-6 text-slate-400 text-sm">{e.auth}</td>
                  <td className="p-6 text-slate-300 text-sm">{e.description}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </main>
    </div>
  );
}
