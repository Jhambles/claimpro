"use client";
import { useState } from "react";
import { useParams, useRouter, useSearchParams } from "next/navigation";
import { useSession } from "next-auth/react";

// In-app mock checkout screen. Used automatically when no real gateway
// credentials (PAYMONGO_SECRET_KEY / PAYPAL_CLIENT_ID) are configured, so the
// full payout flow â€” including notifications â€” is testable without a live
// merchant account. Swap in the real gateway's hosted checkout by configuring
// the env vars documented in README.md; this page then simply isn't reached.
// BANK_TRANSFER is the one exception: it never has a "live gateway" mode â€”
// there's no gateway for a bank deposit, so staff verify it here for real.
const PROVIDER_LABEL: Record<string, string> = { GCASH: "GCash", MAYA: "Maya", PAYPAL: "PayPal", BANK_TRANSFER: "Bank Transfer" };

export default function MockCheckoutPage() {
  const { id } = useParams<{ id: string }>();
  const params = useSearchParams();
  const router = useRouter();
  const { data: session, status: sessionStatus } = useSession();
  const provider = params.get("provider") ?? "GCASH";
  const isBankTransfer = provider === "BANK_TRANSFER";
  const isStaff = session?.user?.role === "PROCESSOR" || session?.user?.role === "ADMIN";
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function resolve(success: boolean) {
    setLoading(true);
    setError(null);
    const res = await fetch(`/api/payments/${id}/confirm`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ success }),
    });
    setLoading(false);
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      setError(body.error ?? "Could not update this payment.");
      return;
    }
    router.push(`/pay/${id}/return?status=${success ? "success" : "failed"}`);
  }

  // A claimant landing here for their own bank transfer can't self-confirm
  // it (see payment.service.ts) â€” show them what's actually happening
  // instead of buttons that would just fail with a permissions error.
  if (isBankTransfer && sessionStatus !== "loading" && !isStaff) {
    return (
      <div className="bg-navy min-h-screen flex items-center justify-center">
        <div className="bg-white rounded-3xl shadow-2xl p-12 max-w-md w-full text-center">
          <span className="inline-block px-3 py-1 bg-amber-50 text-amber-600 text-[10px] font-black uppercase tracking-widest rounded-full mb-4">
            Pending Verification
          </span>
          <h1 className="text-2xl font-bold text-slate-800 mb-2">Bank Transfer Submitted</h1>
          <p className="text-slate-400 text-sm">
            Your bank details have been recorded. Our team will verify the deposit and update your claim â€” you&apos;ll get a notification once it&apos;s processed.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-navy min-h-screen flex items-center justify-center">
      <div className="bg-white rounded-3xl shadow-2xl p-12 max-w-md w-full text-center">
        <span className="inline-block px-3 py-1 bg-teal-50 text-teal text-[10px] font-black uppercase tracking-widest rounded-full mb-4">
          {isBankTransfer ? "Staff Verification" : "Sandbox Checkout"}
        </span>
        <h1 className="text-2xl font-bold text-slate-800 mb-2">Claim via {PROVIDER_LABEL[provider] ?? provider}</h1>
        <p className="text-slate-400 text-sm mb-10">
          {isBankTransfer
            ? "Confirm whether the deposit for this claim has cleared."
            : "This is a local sandbox screen shown because no live gateway credentials are configured."}
        </p>
        {error && <p className="text-red-500 text-xs font-bold mb-4">{error}</p>}
        <div className="space-y-3">
          <button
            onClick={() => resolve(true)}
            disabled={loading}
            className="w-full bg-navy text-white py-4 rounded-xl font-bold hover:bg-teal transition disabled:opacity-50"
          >
            {loading ? "Processingâ€¦" : isBankTransfer ? "Confirm Deposit Received" : "Simulate Successful Payout"}
          </button>
          <button
            onClick={() => resolve(false)}
            disabled={loading}
            className="w-full border border-slate-200 text-slate-500 py-4 rounded-xl font-bold hover:bg-slate-50 transition disabled:opacity-50"
          >
            {isBankTransfer ? "Reject â€” No Deposit Found" : "Simulate Failed Payout"}
          </button>
        </div>
      </div>
    </div>
  );
}
