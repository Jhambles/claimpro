"use client";
import { useEffect, useState } from "react";
import { useSession } from "next-auth/react";
import { Sidebar } from "@/components/ui/Sidebar";
import { getAdminNav } from "@/lib/adminNav";

interface AuditLogEntry {
  id: string;
  actorId: string | null;
  actorName: string;
  actorRole: string;
  action: string;
  detail: string | null;
  createdAt: string;
}

const ACTION_LABEL: Record<string, string> = {
  USER_PROVISIONED: "Account Created",
  CLAIM_STATUS_CHANGED: "Claim Status Changed",
  PAYOUT_INITIATED: "Payout Initiated",
};

export default function SecurityLogsPage() {
  const { data: session } = useSession();
  const [logs, setLogs] = useState<AuditLogEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch("/api/admin/security-logs")
      .then(async (r) => {
        if (!r.ok) throw new Error((await r.json().catch(() => ({}))).error ?? "Could not load logs.");
        return r.json();
      })
      .then(setLogs)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="bg-navy min-h-screen text-white flex">
      <Sidebar brand="ADMIN CORE" items={getAdminNav(session?.user?.role)} active="Security Logs" />

      <main className="flex-1 p-16">
        <h1 className="text-5xl font-black mb-2 tracking-tighter">Security Logs</h1>
        <p className="text-slate-400 uppercase text-[10px] tracking-[0.5em] mb-12">Account &amp; Claim Activity Audit Trail</p>

        {error && <p className="text-red-400 text-sm font-bold mb-6">{error}</p>}

        <div className="bg-white/5 rounded-[2rem] border border-white/10 overflow-hidden max-w-5xl">
          <table className="w-full text-left">
            <thead className="text-[10px] text-slate-400 uppercase tracking-widest">
              <tr>
                <th className="p-6">When</th>
                <th className="p-6">Actor</th>
                <th className="p-6">Action</th>
                <th className="p-6">Detail</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {logs.map((log) => (
                <tr key={log.id}>
                  <td className="p-6 text-slate-400 text-sm whitespace-nowrap">{new Date(log.createdAt).toLocaleString()}</td>
                  <td className="p-6">
                    <div className="font-bold">{log.actorName}</div>
                    <div className="text-[10px] text-slate-500 uppercase font-black">{log.actorRole}</div>
                  </td>
                  <td className="p-6">
                    <span className="text-[10px] bg-teal-500/20 text-teal-400 px-3 py-1 rounded-full font-black uppercase">
                      {ACTION_LABEL[log.action] ?? log.action}
                    </span>
                  </td>
                  <td className="p-6 text-slate-300 text-sm">{log.detail ?? "N/A"}</td>
                </tr>
              ))}
              {!loading && logs.length === 0 && !error && (
                <tr><td colSpan={4} className="p-10 text-center text-slate-400">No activity recorded yet.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </main>
    </div>
  );
}
