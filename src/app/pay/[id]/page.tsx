"use client";
import { useState } from "react";
import { useParams, useRouter, useSearchParams } from "next/navigation";

// In-app mock checkout screen. Used automatically when no real gateway
// credentials (PAYMONGO_SECRET_KEY / PAYPAL_CLIENT_ID) are configured, so the
// full payout flow — including notifications — is testable without a live
// merchant account. Swap in the real gateway's hosted checkout by configuring
// the env vars documented in README.md; this page then simply isn't reached.
const PROVIDER_LABEL: Record<string, string> = { GCASH: "GCash", MAYA: "Maya", PAYPAL: "PayPal" };

export default function MockCheckoutPage() {
  const { id } = useParams<{ id: string }>();
  const params = useSearchParams();
  const router = useRouter();
  const provider = params.get("provider") ?? "GCASH";
  const [loading, setLoading] = useState(false);

  async function resolve(success: boolean) {
    setLoading(true);
    await fetch(`/api/payments/${id}/confirm`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ success }),
    });
    router.push(`/pay/${id}/return?status=${success ? "success" : "failed"}`);
  }

  return (
    <div className="bg-navy min-h-screen flex items-center justify-center">
      <div className="bg-white rounded-3xl shadow-2xl p-12 max-w-md w-full text-center">
        <span className="inline-block px-3 py-1 bg-teal-50 text-teal text-[10px] font-black uppercase tracking-widest rounded-full mb-4">
          Sandbox Checkout
        </span>
        <h1 className="text-2xl font-bold text-slate-800 mb-2">Claim via {PROVIDER_LABEL[provider] ?? provider}</h1>
        <p className="text-slate-400 text-sm mb-10">
          This is a local sandbox screen shown because no live gateway credentials are configured.
        </p>
        <div className="space-y-3">
          <button
            onClick={() => resolve(true)}
            disabled={loading}
            className="w-full bg-navy text-white py-4 rounded-xl font-bold hover:bg-teal transition disabled:opacity-50"
          >
            {loading ? "Processing…" : "Simulate Successful Payout"}
          </button>
          <button
            onClick={() => resolve(false)}
            disabled={loading}
            className="w-full border border-slate-200 text-slate-500 py-4 rounded-xl font-bold hover:bg-slate-50 transition disabled:opacity-50"
          >
            Simulate Failed Payout
          </button>
        </div>
      </div>
    </div>
  );
}
