"use client";
import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { useSession } from "next-auth/react";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DecisionModal, DecisionStatus } from "@/components/ui/DecisionModal";
import { buildLoaHtml } from "@/lib/loaDocument";
import { ClaimDTO } from "@/types";

const CATEGORY_LABEL: Record<string, string> = {
  MEDICAL: "Hospitalization Coverage",
  AUTOMOTIVE: "Accidental Damage",
  HOMEOWNERS: "Homeowners Protection",
};

const DECISION_LABEL: Record<string, { label: string; className: string }> = {
  VERIFIED: { label: "Verified", className: "bg-blue-100 text-blue-700" },
  APPROVED: { label: "Approved", className: "bg-teal-100 text-teal-700" },
  REJECTED: { label: "Rejected", className: "bg-red-100 text-red-600" },
};

const ROLE_LABEL: Record<string, string> = { PROCESSOR: "Processor", ADMIN: "Admin" };

const PROVIDERS: { key: "GCASH" | "MAYA" | "PAYPAL" | "BANK_TRANSFER"; label: string; color: string }[] = [
  { key: "GCASH", label: "GCash", color: "bg-[#007cff]" },
  { key: "MAYA", label: "Maya", color: "bg-[#00c56d]" },
  { key: "PAYPAL", label: "PayPal", color: "bg-[#003087]" },
  { key: "BANK_TRANSFER", label: "Bank Transfer", color: "bg-slate-700" },
];

const PH_BANKS = [
  "BDO Unibank",
  "Bank of the Philippine Islands (BPI)",
  "Metrobank",
  "Landbank",
  "Philippine National Bank (PNB)",
  "Security Bank",
  "UnionBank",
  "RCBC",
  "China Bank",
  "EastWest Bank",
  "Other Bank",
];

const PROVIDER_LABEL: Record<string, string> = {
  GCASH: "GCash",
  MAYA: "Maya",
  PAYPAL: "PayPal",
  BANK_TRANSFER: "Bank Transfer",
};

export default function ClaimDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { data: session } = useSession();
  const [claim, setClaim] = useState<ClaimDTO | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [pendingDecision, setPendingDecision] = useState<DecisionStatus | null>(null);
  const [payoutAmount, setPayoutAmount] = useState("500");
  const [showBankForm, setShowBankForm] = useState(false);
  const [bankChoice, setBankChoice] = useState(PH_BANKS[0]);
  const [otherBankName, setOtherBankName] = useState("");
  const [accountName, setAccountName] = useState("");
  const [accountNumber, setAccountNumber] = useState("");
  const [submittingBank, setSubmittingBank] = useState(false);

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
    // Same as above: fetching this claim's data can only happen after mount.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  useEffect(() => {
    // Only claimants have a saved payout preference (set from Settings) â€”
    // staff viewing someone else's claim have nothing to pre-fill from.
    // This is a convenience pre-fill, not critical, so failures are silent.
    if (session?.user?.role !== "CLIENT") return;
    fetch("/api/settings/payout-preference")
      .then((r) => (r.ok ? r.json() : null))
      .then((pref) => {
        if (pref?.provider === "BANK_TRANSFER" && pref.bankName) {
          const isKnownBank = PH_BANKS.slice(0, -1).includes(pref.bankName);
          setBankChoice(isKnownBank ? pref.bankName : "Other Bank");
          if (!isKnownBank) setOtherBankName(pref.bankName);
          setAccountName(pref.accountName ?? "");
          setAccountNumber(pref.accountNumber ?? "");
        }
      })
      .catch(() => {});
  }, [session?.user?.role]);

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

  // Called by the reason pop-up. Throwing keeps the pop-up open and shows the
  // message inside it (e.g. the server's "unresolved issues" explanation).
  async function submitDecision(reason: string) {
    if (!pendingDecision) return;
    const res = await fetch(`/api/claims/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: pendingDecision, reason }),
    });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      throw new Error(typeof body.error === "string" ? body.error : "Update failed.");
    }
    setPendingDecision(null);
    load();
  }

  async function claimPayout(provider: "GCASH" | "MAYA" | "PAYPAL" | "BANK_TRANSFER", bankDetails?: { bankName: string; accountName: string; accountNumber: string }) {
    const amount = parseFloat(payoutAmount);
    if (!Number.isFinite(amount) || amount <= 0) {
      setError("Enter a valid payout amount before claiming.");
      return;
    }
    const res = await fetch(`/api/claims/${id}/payments`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ provider, amount, ...bankDetails }),
    });
    if (!res.ok) {
      const body = await res.json();
      setError(body.error ?? "Could not start checkout.");
      return;
    }
    const { redirectUrl } = await res.json();
    // This is a page navigation via the browser's Location API, not a
    // mutation of a captured variable â€” the rule's static analysis can't
    // distinguish the two.
    // eslint-disable-next-line react-hooks/immutability
    window.location.href = redirectUrl;
  }

  async function submitBankTransfer() {
    const bankName = bankChoice === "Other Bank" ? otherBankName.trim() : bankChoice;
    if (!bankName || !accountName.trim() || !accountNumber.trim()) {
      setError("Please fill in the bank name, account name, and account number.");
      return;
    }
    setSubmittingBank(true);
    setError(null);
    await claimPayout("BANK_TRANSFER", { bankName, accountName: accountName.trim(), accountNumber: accountNumber.trim() });
    setSubmittingBank(false);
  }

  async function viewLoa() {
    // Open the window synchronously, in direct response to the click, before
    // any await â€” otherwise browsers treat the later window.open() as a
    // non-user-initiated popup and silently block it. Also: pass NO features
    // string here â€” even "noopener" as the 3rd arg makes Chrome/Firefox treat
    // this as a popup-style window request instead of a plain tab, which
    // triggers much stricter blocking. Sever window.opener via the property
    // instead, right after opening, for the same protection without that cost.
    const w = window.open("", "_blank");
    if (w) {
      w.opener = null;
      w.document.write("<p style='font-family:sans-serif;padding:40px;color:#64748b;'>Generating your Letter of Authorizationâ€¦</p>");
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
    w.document.write(buildLoaHtml(loa.content, loa.qrCodeDataUrl, loa.payoutUrl, loa.providerLabel));
    w.document.close();
  }

  if (loading && !claim) return <div className="p-12 text-slate-400">Loading claimâ€¦</div>;
  if (!claim) return <div className="p-12 text-slate-400">{loadError ?? "Claim not found."}</div>;

  const role = session?.user?.role;
  const isOwner = role === "CLIENT" && claim.user.id === session?.user?.id;
  const isStaff = role === "PROCESSOR" || role === "ADMIN";
  const hasBlockingIssue = !!claim.issues?.some((i) => i.severity === "blocking");

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

          {claim.issues && claim.issues.length > 0 && (
            <div className="mb-8 space-y-2">
              {claim.issues.map((issue) => (
                <div
                  key={issue.code}
                  className={`flex items-start gap-3 p-4 rounded-xl text-sm ${
                    issue.severity === "blocking" ? "bg-red-50 text-red-700" : "bg-amber-50 text-amber-700"
                  }`}
                >
                  <i className={`fa-solid ${issue.severity === "blocking" ? "fa-circle-exclamation" : "fa-triangle-exclamation"} mt-0.5`} />
                  <span>{issue.message}</span>
                </div>
              ))}
            </div>
          )}

          {isStaff && (
            <div className="flex gap-3 mb-8">
              {claim.status === "PENDING" && (
                <>
                  <button onClick={() => setPendingDecision("VERIFIED")} className="bg-navy text-white px-6 py-2 rounded-lg text-sm font-bold">Verify</button>
                  <button onClick={() => setPendingDecision("REJECTED")} className="bg-red-500 text-white px-6 py-2 rounded-lg text-sm font-bold">Reject</button>
                </>
              )}
              {claim.status === "VERIFIED" && (
                <>
                  <button
                    onClick={() => setPendingDecision("APPROVED")}
                    disabled={hasBlockingIssue}
                    title={hasBlockingIssue ? "Resolve the red flags above before approving." : undefined}
                    className="bg-teal text-white px-6 py-2 rounded-lg text-sm font-bold disabled:opacity-40 disabled:cursor-not-allowed"
                  >
                    Approve
                  </button>
                  <button onClick={() => setPendingDecision("REJECTED")} className="bg-red-500 text-white px-6 py-2 rounded-lg text-sm font-bold">Reject</button>
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

        {claim.decisions && claim.decisions.length > 0 && (
          <div className="bg-white rounded-[2rem] shadow-sm border border-slate-100 p-10 mb-8">
            <h2 className="text-xl font-bold text-navy mb-6">Decision History</h2>
            <ul className="space-y-5">
              {claim.decisions.map((d) => {
                const meta = DECISION_LABEL[d.status] ?? { label: d.status, className: "bg-slate-100 text-slate-600" };
                return (
                  <li key={d.id} className="border-l-4 border-slate-100 pl-5">
                    <div className="flex items-center gap-3 mb-1">
                      <span className={`text-[10px] font-black uppercase px-3 py-1 rounded-full ${meta.className}`}>{meta.label}</span>
                      <span className="text-xs text-slate-400">
                        {d.decidedByName} ({ROLE_LABEL[d.decidedByRole] ?? d.decidedByRole}) &middot; {new Date(d.createdAt).toLocaleString()}
                      </span>
                    </div>
                    <p className="text-sm text-slate-700 whitespace-pre-wrap">{d.reason}</p>
                  </li>
                );
              })}
            </ul>
          </div>
        )}

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
              <p className="text-sm font-bold">{uploading ? "Uploadingâ€¦" : "Click to upload a document"}</p>
              <p className="text-xs mt-1 italic">Maximum file size: 10MB (PDF, PNG, JPG)</p>
              <input type="file" accept=".pdf,.png,.jpg,.jpeg" className="hidden" onChange={handleUpload} disabled={uploading} />
            </label>
          )}
        </div>

        {isOwner && claim.status === "APPROVED" && (
          <div className="bg-white rounded-[2rem] shadow-sm border border-slate-100 p-10">
            <h2 className="text-xl font-bold text-navy mb-2">Claim Your Payout</h2>
            <p className="text-slate-500 text-sm mb-6">Your claim was approved for disbursement - choose how you&apos;d like to receive it.</p>

            <div className="mb-6 max-w-xs">
              <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">Amount (PHP)</label>
              <input
                type="number"
                value={payoutAmount}
                onChange={(e) => setPayoutAmount(e.target.value)}
                className="w-full p-3 border border-slate-100 rounded-xl bg-slate-50 outline-none focus:border-teal"
              />
            </div>

            <div className="flex gap-4 flex-wrap">
              {PROVIDERS.map((p) => (
                <button
                  key={p.key}
                  onClick={() => (p.key === "BANK_TRANSFER" ? setShowBankForm((v) => !v) : claimPayout(p.key))}
                  className={`${p.color} text-white px-6 py-3 rounded-xl font-bold text-sm hover:opacity-90 transition`}
                >
                  Claim via {p.label}
                </button>
              ))}
            </div>

            {showBankForm && (
              <div className="mt-6 max-w-md bg-slate-50 border border-slate-100 rounded-2xl p-6">
                <p className="text-[10px] font-black text-slate-400 uppercase mb-4">Bank Details</p>
                <div className="space-y-4">
                  <div>
                    <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">Bank</label>
                    <select
                      value={bankChoice}
                      onChange={(e) => setBankChoice(e.target.value)}
                      className="w-full p-3 border border-slate-200 rounded-xl bg-white outline-none focus:border-teal"
                    >
                      {PH_BANKS.map((b) => (
                        <option key={b} value={b}>{b}</option>
                      ))}
                    </select>
                  </div>
                  {bankChoice === "Other Bank" && (
                    <div>
                      <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">Bank Name</label>
                      <input
                        type="text"
                        value={otherBankName}
                        onChange={(e) => setOtherBankName(e.target.value)}
                        placeholder="Enter your bank's name"
                        className="w-full p-3 border border-slate-200 rounded-xl bg-white outline-none focus:border-teal"
                      />
                    </div>
                  )}
                  <div>
                    <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">Account Name</label>
                    <input
                      type="text"
                      value={accountName}
                      onChange={(e) => setAccountName(e.target.value)}
                      placeholder="Full name on the account"
                      className="w-full p-3 border border-slate-200 rounded-xl bg-white outline-none focus:border-teal"
                    />
                  </div>
                  <div>
                    <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">Account Number</label>
                    <input
                      type="text"
                      value={accountNumber}
                      onChange={(e) => setAccountNumber(e.target.value)}
                      placeholder="Bank account number"
                      className="w-full p-3 border border-slate-200 rounded-xl bg-white outline-none focus:border-teal"
                    />
                  </div>
                  <button
                    onClick={submitBankTransfer}
                    disabled={submittingBank}
                    className="w-full bg-navy text-white py-3 rounded-xl font-bold text-sm hover:bg-teal transition disabled:opacity-50"
                  >
                    {submittingBank ? "Submittingâ€¦" : "Submit Bank Transfer Request"}
                  </button>
                  <p className="text-slate-400 text-xs italic">Payouts by bank transfer are verified manually by our team and may take 1â€“3 business days.</p>
                </div>
              </div>
            )}

            {claim.payments && claim.payments.length > 0 && (
              <div className="mt-8">
                <h3 className="text-[10px] font-black text-slate-400 uppercase mb-3">Payout History</h3>
                <ul className="space-y-2">
                  {claim.payments.map((p) => (
                    <li key={p.id} className="flex justify-between text-sm border-b border-slate-50 pb-2">
                      <span>
                        {PROVIDER_LABEL[p.provider] ?? p.provider} &middot; PHP {parseFloat(p.amount).toLocaleString()}
                        {p.provider === "BANK_TRANSFER" && p.bankName && (
                          <span className="text-slate-400"> ({p.bankName} - {p.accountNumber})</span>
                        )}
                      </span>
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

      {pendingDecision && (
        <DecisionModal
          status={pendingDecision}
          referenceId={claim.referenceId}
          onCancel={() => setPendingDecision(null)}
          onConfirm={submitDecision}
        />
      )}
    </div>
  );
}
