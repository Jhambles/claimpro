"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import { Sidebar } from "@/components/ui/Sidebar";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { buildLoaHtml } from "@/lib/loaDocument";
import { ClaimDTO } from "@/types";

const NAV = [
  { icon: "fa-house", label: "Dashboard", href: "/claimant" },
  { icon: "fa-file-invoice", label: "My Claims", href: "/claimant/claims" },
];

export default function ClaimsHistoryPage() {
  const [claims, setClaims] = useState<ClaimDTO[]>([]);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch("/api/claims")
      .then((r) => (r.ok ? r.json() : []))
      .then((data) => setClaims(data))
      .finally(() => setLoading(false));
  }, []);

  async function viewLoa(claimId: string) {
    // Open the window synchronously, in direct response to the click, before
    // any await — otherwise browsers treat the later window.open() as a
    // non-user-initiated popup and silently block it. Also: pass NO features
    // string here — even "noopener" as the 3rd arg makes Chrome/Firefox treat
    // this as a popup-style window request instead of a plain tab, which
    // triggers much stricter blocking. Sever window.opener via the property
    // instead, right after opening, for the same protection without that cost.
    const w = window.open("", "_blank");
    if (w) {
      w.opener = null;
      w.document.write("<p style='font-family:sans-serif;padding:40px;color:#64748b;'>Generating your Letter of Authorization…</p>");
    }

    const res = await fetch(`/api/claims/${claimId}/loa`, { method: "POST" });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      w?.close();
      alert(body.error ?? "Unable to generate LOA.");
      return;
    }
    const loa = await res.json();
    if (!w) {
      alert("Your browser blocked the popup. Please allow popups for this site and try again.");
      return;
    }
    w.document.open();
    w.document.write(buildLoaHtml(loa.content, loa.qrCodeDataUrl, loa.payoutUrl));
    w.document.close();
  }

  const filtered = claims.filter((c) => `${c.referenceId} ${c.category} ${c.status}`.toUpperCase().includes(search.toUpperCase()));

  return (
    <div className="flex bg-slate-50 min-h-screen">
      <Sidebar brand="CLAIMS PRO" items={NAV} active="My Claims" dark={false} />

      <main className="flex-1 p-12">
        <header className="flex justify-between items-end mb-12">
          <div>
            <Link href="/claimant" className="text-teal text-xs font-black uppercase tracking-widest hover:underline block mb-2">
              <i className="fa-solid fa-arrow-left mr-2" /> Return to Portal
            </Link>
            <h1 className="text-5xl font-black text-navy tracking-tighter">Claims History</h1>
          </div>
          <div className="relative w-80">
            <i className="fa-solid fa-search absolute left-4 top-4 text-slate-300" />
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search Reference ID..."
              className="w-full pl-12 pr-4 py-4 rounded-2xl border-none shadow-sm focus:ring-2 focus:ring-teal outline-none"
            />
          </div>
        </header>

        <div className="bg-white rounded-[2rem] shadow-sm border border-slate-100 overflow-hidden">
          <table className="w-full text-left">
            <thead className="bg-slate-50/50">
              <tr className="text-[10px] font-black text-slate-400 uppercase tracking-widest">
                <th className="p-8 border-b">Record Identifier</th>
                <th className="p-8 border-b">Classification</th>
                <th className="p-8 border-b">Date Logs</th>
                <th className="p-8 border-b">Lifecycle Status</th>
                <th className="p-8 border-b text-center">Outcome</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-50">
              {filtered.map((claim) => (
                <tr key={claim.id} className="hover:bg-slate-50 transition">
                  <td className="p-8 font-mono text-sm font-bold text-slate-600">
                    <Link href={`/claims/${claim.id}`} className="hover:text-teal hover:underline">{claim.referenceId}</Link>
                  </td>
                  <td className="p-8 text-slate-800 font-medium">{formatCategory(claim.category)}</td>
                  <td className="p-8 text-sm text-slate-400">{new Date(claim.createdAt).toLocaleDateString("en-US", { year: "numeric", month: "long", day: "2-digit" })}</td>
                  <td className="p-8"><StatusBadge status={claim.status} /></td>
                  <td className="p-8 text-center">
                    {claim.status === "APPROVED" ? (
                      <button onClick={() => viewLoa(claim.id)} className="text-teal-600 font-bold text-xs underline decoration-teal-200">
                        View LOA
                      </button>
                    ) : claim.status === "REJECTED" ? (
                      <span className="text-red-400 font-bold text-xs italic">Not approved</span>
                    ) : (
                      <span className="text-slate-300 font-bold text-xs italic">Awaiting...</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>

          {!loading && filtered.length === 0 && (
            <div className="p-20 text-center">
              <i className="fa-solid fa-magnifying-glass text-5xl text-slate-100 mb-4" />
              <p className="text-slate-400 font-bold">No matching records found.</p>
            </div>
          )}
        </div>
      </main>
    </div>
  );
}

function formatCategory(category: string) {
  return { MEDICAL: "Hospitalization Coverage", AUTOMOTIVE: "Accidental Damage", HOMEOWNERS: "Homeowners Protection" }[category] ?? category;
}