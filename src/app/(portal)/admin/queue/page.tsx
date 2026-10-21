"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { useSession } from "next-auth/react";
import { Sidebar } from "@/components/ui/Sidebar";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DecisionModal, DecisionStatus } from "@/components/ui/DecisionModal";
import { getAdminNav } from "@/lib/adminNav";
import { ClaimDTO } from "@/types";

const hasBlocking = (c: ClaimDTO) => !!c.issues?.some((i) => i.severity === "blocking");

export default function VerificationQueuePage() {
  const { data: session } = useSession();
  const [claims, setClaims] = useState<ClaimDTO[]>([]);
  const [loading, setLoading] = useState(true);
  const [pending, setPending] = useState<{ id: string; referenceId: string; status: DecisionStatus } | null>(null);

  async function load() {
    setLoading(true);
    const res = await fetch("/api/claims");
    setClaims(res.ok ? await res.json() : []);
    setLoading(false);
  }

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, []);

  async function submitDecision(reason: string) {
    if (!pending) return;
    const res = await fetch(`/api/claims/${pending.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: pending.status, reason }),
    });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      throw new Error(typeof body.error === "string" ? body.error : "Update failed.");
    }
    setPending(null);
    load();
  }

  return (
    <div className="bg-navy min-h-screen text-white flex">
      <Sidebar brand="ADMIN CORE" items={getAdminNav(session?.user?.role)} active="Verification Queue" />

      <main className="flex-1 p-16">
        <h1 className="text-5xl font-black mb-2 tracking-tighter">Verification Queue</h1>
        <p className="text-slate-400 uppercase text-[10px] tracking-[0.5em] mb-12">Claim Review &amp; Approval</p>

        <div className="bg-white/5 rounded-[2rem] border border-white/10 overflow-hidden">
          <table className="w-full text-left">
            <thead className="text-[10px] text-slate-400 uppercase tracking-widest">
              <tr>
                <th className="p-6">Submission Date</th>
                <th className="p-6">Claimant</th>
                <th className="p-6">Reference</th>
                <th className="p-6">Status</th>
                <th className="p-6">Flags</th>
                <th className="p-6 text-center">Action</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white/5">
              {claims.map((c) => (
                <tr key={c.id}>
                  <td className="p-6 text-slate-400 text-sm">{new Date(c.createdAt).toLocaleDateString("en-US", { year: "numeric", month: "long", day: "2-digit" })}</td>
                  <td className="p-6 font-bold">{c.user?.name}</td>
                  <td className="p-6 font-mono text-sm"><Link href={`/claims/${c.id}`} className="text-teal-400 hover:underline">{c.referenceId}</Link></td>
                  <td className="p-6"><StatusBadge status={c.status} /></td>
                  <td className="p-6">
                    {c.issues && c.issues.length > 0 ? (
                      <span
                        className={`text-[10px] font-black uppercase px-2 py-1 rounded-full ${
                          hasBlocking(c) ? "bg-red-500/20 text-red-400" : "bg-amber-500/20 text-amber-400"
                        }`}
                        title={c.issues.map((i) => i.message).join("\n")}
                      >
                        {c.issues.length} flag{c.issues.length > 1 ? "s" : ""}
                      </span>
                    ) : (
                      <span className="text-slate-600 text-xs">N/A</span>
                    )}
                  </td>
                  <td className="p-6 text-center space-x-2">
                    {c.status === "PENDING" && (
                      <>
                        <button onClick={() => setPending({ id: c.id, referenceId: c.referenceId, status: "VERIFIED" })} className="bg-teal-500/20 text-teal-400 px-4 py-1.5 rounded-full text-xs font-black uppercase hover:bg-teal-500/30 transition">Verify</button>
                        <button onClick={() => setPending({ id: c.id, referenceId: c.referenceId, status: "REJECTED" })} className="bg-red-500/20 text-red-400 px-4 py-1.5 rounded-full text-xs font-black uppercase hover:bg-red-500/30 transition">Reject</button>
                      </>
                    )}
                    {c.status === "VERIFIED" && (
                      <>
                        <button
                          onClick={() => setPending({ id: c.id, referenceId: c.referenceId, status: "APPROVED" })}
                          disabled={hasBlocking(c)}
                          title={hasBlocking(c) ? "Resolve the red flags on this claim before approving." : undefined}
                          className="bg-teal-500/20 text-teal-400 px-4 py-1.5 rounded-full text-xs font-black uppercase hover:bg-teal-500/30 transition disabled:opacity-40 disabled:cursor-not-allowed"
                        >
                          Approve
                        </button>
                        <button onClick={() => setPending({ id: c.id, referenceId: c.referenceId, status: "REJECTED" })} className="bg-red-500/20 text-red-400 px-4 py-1.5 rounded-full text-xs font-black uppercase hover:bg-red-500/30 transition">Reject</button>
                      </>
                    )}
                    {(c.status === "APPROVED" || c.status === "REJECTED") && (
                      <span className="text-slate-500 text-xs italic">Closed</span>
                    )}
                  </td>
                </tr>
              ))}
              {!loading && claims.length === 0 && (
                <tr><td colSpan={6} className="p-10 text-center text-slate-400 font-bold">Queue is empty.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </main>

      {pending && (
        <DecisionModal
          status={pending.status}
          referenceId={pending.referenceId}
          onCancel={() => setPending(null)}
          onConfirm={submitDecision}
        />
      )}
    </div>
  );
}
