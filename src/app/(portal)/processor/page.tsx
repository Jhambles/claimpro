"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { Sidebar } from "@/components/ui/Sidebar";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { ClaimDTO } from "@/types";

const NAV = [{ icon: "fa-clipboard-check", label: "Verification Queue", href: "/processor" }];

export default function ProcessorQueuePage() {
  const [claims, setClaims] = useState<ClaimDTO[]>([]);
  const [loading, setLoading] = useState(true);

  async function load() {
    setLoading(true);
    const res = await fetch("/api/claims");
    setClaims(res.ok ? await res.json() : []);
    setLoading(false);
  }

  useEffect(() => {
    load();
  }, []);

  async function transition(id: string, status: string) {
    const res = await fetch(`/api/claims/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status }),
    });
    if (!res.ok) {
      const body = await res.json();
      alert(body.error ?? "Update failed.");
      return;
    }
    load();
  }

  return (
    <div className="flex bg-slate-50 min-h-screen">
      <Sidebar brand="CLAIMS PRO" items={NAV} active="Verification Queue" dark={false} />

      <main className="flex-1 p-10">
        <header className="flex justify-between items-center mb-8">
          <h1 className="text-2xl font-extrabold text-navy">
            Verification Queue <span className="text-teal font-light italic">/ Staff Interface</span>
          </h1>
        </header>

        <div className="bg-white rounded shadow-sm overflow-hidden border border-gray-100">
          <table className="w-full text-left">
            <thead className="bg-navy text-white uppercase text-xs">
              <tr>
                <th className="p-4">Submission Date</th>
                <th className="p-4">Claimant</th>
                <th className="p-4">Reference</th>
                <th className="p-4">Status</th>
                <th className="p-4 text-center">Action</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {claims.map((c) => (
                <tr key={c.id}>
                  <td className="p-4 text-slate-500 text-sm">{new Date(c.createdAt).toLocaleDateString("en-US", { year: "numeric", month: "long", day: "2-digit" })}</td>
                  <td className="p-4 font-bold">{c.user?.name}</td>
                  <td className="p-4 font-mono text-sm"><Link href={`/claims/${c.id}`} className="hover:text-teal hover:underline">{c.referenceId}</Link></td>
                  <td className="p-4"><StatusBadge status={c.status} /></td>
                  <td className="p-4 text-center space-x-2">
                    {c.status === "PENDING" && (
                      <>
                        <button onClick={() => transition(c.id, "VERIFIED")} className="bg-navy text-white px-4 py-1 rounded text-xs">Verify</button>
                        <button onClick={() => transition(c.id, "REJECTED")} className="bg-red-500 text-white px-4 py-1 rounded text-xs">Reject</button>
                      </>
                    )}
                    {c.status === "VERIFIED" && (
                      <>
                        <button onClick={() => transition(c.id, "APPROVED")} className="bg-teal text-white px-4 py-1 rounded text-xs">Approve</button>
                        <button onClick={() => transition(c.id, "REJECTED")} className="bg-red-500 text-white px-4 py-1 rounded text-xs">Reject</button>
                      </>
                    )}
                    {(c.status === "APPROVED" || c.status === "REJECTED") && (
                      <span className="text-slate-300 text-xs italic">Closed</span>
                    )}
                  </td>
                </tr>
              ))}
              {!loading && claims.length === 0 && (
                <tr><td colSpan={5} className="p-10 text-center text-slate-400 font-bold">Queue is empty.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </main>
    </div>
  );
}
