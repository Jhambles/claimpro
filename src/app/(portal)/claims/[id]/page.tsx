"use client";
import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { useSession } from "next-auth/react";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { buildLoaHtml } from "@/lib/loaDocument";
import { ClaimDTO } from "@/types";

const CATEGORY_LABEL: Record<string, string> = {
  MEDICAL: "Hospitalization Coverage",
  AUTOMOTIVE: "Accidental Damage",
  HOMEOWNERS: "Homeowners Protection",
};

const PROVIDERS: { key: "GCASH" | "MAYA" | "PAYPAL"; label: string; color: string }[] = [
  { key: "GCASH", label: "GCash", color: "bg-[#007cff]" },
  { key: "MAYA", label: "Maya", color: "bg-[#00c56d]" },
  { key: "PAYPAL", label: "PayPal", color: "bg-[#003087]" },
];

export default function ClaimDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { data: session } = useSession();
  const [claim, setClaim] = useState<ClaimDTO | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [payoutAmount, setPayoutAmount] = useState("500");

  async function load() {
    setLoading(true);
    const res = await fetch(`/api/claims/${id}`);
    if (res.ok) {
      const data = await res.json();
      setClaim(data);
      setPayoutAmount((prev) => (prev === "500" ? data.estimate : prev));
    } else if (res.status === 403) {
      setLoadError("You don't have access to this claim.");
    } else {
      setLoadError("Claim not found.");
    }
    setLoading(false);
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  async function handleUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    setError(null);
    const form = new FormData();
    form.append("file", file);
    const res = await fetch(`/api/claims/${id}/documents`, { method: "POST", body: form });
    setUploading(false);
    if (!res.ok) {
      const body = await res.json();
      setError(typeof body.error === "string" ? body.error : "Upload failed.");
      return;
    }
    load();
  }

  async function transition(status: string) {
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

  async function claimPayout(provider: "GCASH" | "MAYA" | "PAYPAL") {
    const amount = parseFloat(payoutAmount);
    if (!Number.isFinite(amount) || amount <= 0) {
      setError("Enter a valid payout amount before claiming.");
      return;
    }
    const res = await fetch(`/api/claims/${id}/payments`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ provider, amount }),
    });
    if (!res.ok) {
      const body = await res.json();
      setError(body.error ?? "Could not start checkout.");
      return;
    }
    const { redirectUrl } = await res.json();
    window.location.href = redirectUrl;
  }

  async function viewLoa() {
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

    const res = await fetch(`/api/claims/${id}/loa`, { method: "POST" });
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

  if (loading) return <div className="p-12 text-slate-400">Loading claim…</div>;
  if (!claim) return <div className="p-12 text-slate-400">{loadError ?? "Claim not found."}</div>;

  const role = session?.user?.role;
  const isOwner = role === "CLIENT" && claim.user.id === session?.user?.id;
  const isStaff = role === "PROCESSOR" || role === "ADMIN";

  return (
    <div className="min-h-screen bg-slate-50 p-12">
      <div className="max-w-4xl mx-auto">
        <button onClick={() => router.back()} className="text-teal text-xs font-black uppercase tracking-widest hover:underline mb-6 block">
          <i className="fa-solid fa-arrow-left mr-2" /> Back
        </button>

        <div className="bg-white rounded-[2rem] shadow-sm border border-slate-100 p-10 mb-8">
          <div className="flex justify-between items-start mb-8">
            <div>
              <p className="font-mono text-sm text-slate-400">{claim.referenceId}</p>
              <h1 className="text-3xl font-black text-navy">{CATEGORY_LABEL[claim.category] ?? claim.category}</h1>
              <p className="text-slate-500 mt-1">Filed by {claim.user.name} &middot; {claim.user.email}</p>
            </div>
            <StatusBadge status={claim.status} />
          </div>

          <div className="grid grid-cols-2 gap-6 text-sm mb-8">
            <div>
              <p className="text-[10px] font-black text-slate-400 uppercase mb-1">Estimate</p>
              <p className="font-bold text-navy">PHP {parseFloat(claim.estimate).toLocaleString()}</p>
            </div>
            <div>
              <p className="text-[10px] font-black text-slate-400 uppercase mb-1">Filed On</p>
              <p className="font-bold text-navy">{new Date(claim.createdAt).toLocaleDateString("en-US", { year: "numeric", month: "long", day: "2-digit" })}</p>
            </div>
          </div>

          {isStaff && (
            <div className="flex gap-3 mb-8">
              {claim.status === "PENDING" && (
                <>
                  <button onClick={() => transition("VERIFIED")} className="bg-navy text-white px-6 py-2 rounded-lg text-sm font-bold">Verify</button>
                  <button onClick={() => transition("REJECTED")} className="bg-red-500 text-white px-6 py-2 rounded-lg text-sm font-bold">Reject</button>
                </>
              )}
              {claim.status === "VERIFIED" && (
                <>
                  <button onClick={() => transition("APPROVED")} className="bg-teal text-white px-6 py-2 rounded-lg text-sm font-bold">Approve</button>
                  <button onClick={() => transition("REJECTED")} className="bg-red-500 text-white px-6 py-2 rounded-lg text-sm font-bold">Reject</button>
                </>
              )}
            </div>
          )}

          {claim.status === "APPROVED" && (
            <button onClick={viewLoa} className="text-teal-600 font-bold text-sm underline decoration-teal-200 mb-4 block">
              View / Generate Letter of Authorization
            </button>
          )}
        </div>

        <div className="bg-white rounded-[2rem] shadow-sm border border-slate-100 p-10 mb-8">
          <h2 className="text-xl font-bold text-navy mb-6">Supporting Documents</h2>
          <ul className="space-y-2 mb-6">
            {claim.documents?.map((d) => (
              <li key={d.id} className="flex justify-between text-sm border-b border-slate-50 pb-2">
                <a href={`/api/claims/${id}/documents/${d.id}`} target="_blank" rel="noreferrer" className="text-teal-600 underline">{d.fileName}</a>
                <span className="text-slate-400">{(d.sizeBytes / 1024).toFixed(0)} KB</span>
              </li>
            ))}
            {(!claim.documents || claim.documents.length === 0) && <p className="text-slate-400 text-sm italic">No documents uploaded yet.</p>}
          </ul>

          {isOwner && (
            <label className="border-2 border-dashed border-slate-200 rounded-2xl py-10 flex flex-col items-center justify-center text-slate-400 bg-slate-50 hover:bg-white hover:border-teal cursor-pointer transition-all">
              <i className="fa-solid fa-cloud-arrow-up text-3xl mb-2" />
              <p className="text-sm font-bold">{uploading ? "Uploading…" : "Click to upload a document"}</p>
              <p className="text-xs mt-1 italic">Maximum file size: 10MB (PDF, PNG, JPG)</p>
              <input type="file" accept=".pdf,.png,.jpg,.jpeg" className="hidden" onChange={handleUpload} disabled={uploading} />
            </label>
          )}
        </div>

        {isOwner && claim.status === "APPROVED" && (
          <div className="bg-white rounded-[2rem] shadow-sm border border-slate-100 p-10">
            <h2 className="text-xl font-bold text-navy mb-2">Claim Your Payout</h2>
            <p className="text-slate-500 text-sm mb-6">Your claim was approved for disbursement — choose how you'd like to receive it.</p>

            <div className="mb-6 max-w-xs">
              <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">Amount (PHP)</label>
              <input
                type="number"
                value={payoutAmount}
                onChange={(e) => setPayoutAmount(e.target.value)}
                className="w-full p-3 border border-slate-100 rounded-xl bg-slate-50 outline-none focus:border-teal"
              />
            </div>

            <div className="flex gap-4">
              {PROVIDERS.map((p) => (
                <button key={p.key} onClick={() => claimPayout(p.key)} className={`${p.color} text-white px-6 py-3 rounded-xl font-bold text-sm hover:opacity-90 transition`}>
                  Claim via {p.label}
                </button>
              ))}
            </div>

            {claim.payments && claim.payments.length > 0 && (
              <div className="mt-8">
                <h3 className="text-[10px] font-black text-slate-400 uppercase mb-3">Payout History</h3>
                <ul className="space-y-2">
                  {claim.payments.map((p) => (
                    <li key={p.id} className="flex justify-between text-sm border-b border-slate-50 pb-2">
                      <span>{p.provider} &middot; PHP {parseFloat(p.amount).toLocaleString()}</span>
                      <StatusBadge status={p.status} />
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        )}

        {error && <p className="text-red-500 text-sm font-bold text-center mt-6">{error}</p>}
      </div>
    </div>
  );
}