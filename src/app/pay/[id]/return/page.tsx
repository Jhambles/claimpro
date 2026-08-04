"use client";
import { useEffect, useState } from "react";
import { useParams, useSearchParams } from "next/navigation";
import Link from "next/link";

// Redirect target for real gateways (PayMongo/PayPal) after the customer
// completes or cancels checkout on the provider's hosted page.
export default function PaymentReturnPage() {
  const { id } = useParams<{ id: string }>();
  const params = useSearchParams();
  const status = params.get("status");
  const [confirmed, setConfirmed] = useState(false);

  useEffect(() => {
    // If a real gateway redirected here directly (skipping the mock page's
    // own confirm call), reconcile the result now.
    fetch(`/api/payments/${id}/confirm`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ success: status === "success" }),
    }).finally(() => setConfirmed(true));
  }, [id, status]);

  const success = status === "success";

  return (
    <div className="bg-navy min-h-screen flex items-center justify-center">
      <div className="bg-white rounded-3xl shadow-2xl p-12 max-w-md w-full text-center">
        <div className={`w-16 h-16 rounded-full flex items-center justify-center mx-auto mb-6 ${success ? "bg-teal-50" : "bg-red-50"}`}>
          <i className={`fa-solid ${success ? "fa-check text-teal" : "fa-xmark text-red-500"} text-2xl`} />
        </div>
        <h1 className="text-2xl font-bold text-slate-800 mb-2">{success ? "Payout Claimed" : "Payout Failed"}</h1>
        <p className="text-slate-400 text-sm mb-8">
          {confirmed ? "Your claim record has been updated." : "Finalizing…"}
        </p>
        <Link href="/claimant/claims" className="text-teal font-bold text-sm hover:underline">
          Return to Claims History &rarr;
        </Link>
      </div>
    </div>
  );
}
