"use client";
import { useState } from "react";
import Link from "next/link";
import { Sidebar } from "@/components/ui/Sidebar";
import { Toast } from "@/components/ui/Toast";

const NAV = [
  { icon: "fa-house", label: "Dashboard", href: "/claimant" },
  { icon: "fa-file-invoice", label: "My Claims", href: "/claimant/claims" },
];

export default function NewClaimPage() {
  const [category, setCategory] = useState("MEDICAL");
  const [estimate, setEstimate] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [showToast, setShowToast] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  function handleFileSelect(e: React.ChangeEvent<HTMLInputElement>) {
    setFile(e.target.files?.[0] ?? null);
  }

  async function handleSubmit() {
    setError(null);
    setSubmitting(true);
    try {
      const res = await fetch("/api/claims", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ category, estimate: parseFloat(estimate) || 0 }),
      });
      if (!res.ok) {
        const body = await res.json();
        throw new Error(typeof body.error === "string" ? body.error : "Submission failed.");
      }
      const claim = await res.json();

      // Claim exists now — attach the selected evidence file, if any. A failed
      // upload here shouldn't be reported as a failed submission (the claim
      // itself is already saved); surface it as a distinct warning instead.
      if (file) {
        const form = new FormData();
        form.append("file", file);
        const uploadRes = await fetch(`/api/claims/${claim.id}/documents`, { method: "POST", body: form });
        if (!uploadRes.ok) {
          const body = await uploadRes.json();
          setError(
            `Claim ${claim.referenceId} was submitted, but the attached file didn't upload: ${
              typeof body.error === "string" ? body.error : "unknown error"
            }. You can attach it later from the claim's detail page.`
          );
        }
      }

      setShowToast(true);
      setEstimate("");
      setFile(null);
      setTimeout(() => setShowToast(false), 4000);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="flex bg-slate-50 min-h-screen">
      <Sidebar brand="CLAIMS PRO" items={NAV} active="Dashboard" dark={false} />

      <main className="flex-1 p-12">
        <header className="mb-12">
          <h1 className="text-4xl font-black text-navy">New Claim Request</h1>
          <p className="text-slate-400 mt-2 italic">Submit a claim for verification</p>
        </header>

        <div className="mb-12 max-w-4xl">
          <div className="flex items-center justify-between relative px-2">
            <div className="absolute top-1/2 left-0 w-full h-0.5 bg-slate-200 -z-10" />
            <Step n={1} label="INTAKE" active />
            <Step n={2} label="VERIFICATION" />
            <Step n={3} label="APPROVAL" />
          </div>
        </div>

        <div className="bg-white p-10 rounded-3xl shadow-sm border border-slate-100 max-w-4xl">
          <div className="grid md:grid-cols-2 gap-8 mb-8">
            <div>
              <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">Policy Category</label>
              <select
                value={category}
                onChange={(e) => setCategory(e.target.value)}
                className="w-full p-4 border border-slate-100 rounded-xl bg-slate-50 outline-none focus:border-teal"
              >
                <option value="MEDICAL">Medical Expense Coverage</option>
                <option value="AUTOMOTIVE">Automotive Damage</option>
                <option value="HOMEOWNERS">Homeowners Protection</option>
              </select>
            </div>
            <div>
              <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">Claim Estimate (PHP)</label>
              <input
                type="number"
                value={estimate}
                onChange={(e) => setEstimate(e.target.value)}
                placeholder="5,000.00"
                className="w-full p-4 border border-slate-100 rounded-xl bg-slate-50 outline-none focus:border-teal"
              />
            </div>
          </div>

          <div className="mb-10">
            <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">
              Supporting Evidence (Medical Records/Receipts)
            </label>
            <label className="border-2 border-dashed border-slate-200 rounded-2xl py-16 flex flex-col items-center justify-center text-slate-400 bg-slate-50 hover:bg-white hover:border-teal cursor-pointer transition-all">
              <i className="fa-solid fa-cloud-arrow-up text-4xl mb-4" />
              <p className="text-sm font-bold">{file ? file.name : "Click to attach a document"}</p>
              <p className="text-xs mt-1 italic">Maximum file size: 10MB (PDF, PNG, JPG)</p>
              <input type="file" accept=".pdf,.png,.jpg,.jpeg" className="hidden" onChange={handleFileSelect} />
            </label>
          </div>

          {error && <p className="text-red-500 text-xs font-bold text-center mb-4">{error}</p>}

          <button
            onClick={handleSubmit}
            disabled={submitting}
            className="w-full bg-navy text-white py-5 rounded-2xl font-bold hover:bg-teal transition-all shadow-xl shadow-slate-100 disabled:opacity-50"
          >
            {submitting ? "Submitting..." : "Submit for Verification"}
          </button>
          <Link href="/claimant/claims" className="block text-center text-xs text-teal font-bold mt-6 hover:underline">
            View my claims history &rarr;
          </Link>
        </div>
      </main>

      <Toast show={showToast} title="Submission Successful" message="Your claim has been assigned to a processor." />
    </div>
  );
}

function Step({ n, label, active = false }: { n: number; label: string; active?: boolean }) {
  return (
    <div className="flex flex-col items-center">
      <div
        className={`w-10 h-10 rounded-full flex items-center justify-center font-bold ring-4 ring-white ${
          active ? "bg-teal text-white shadow-lg shadow-teal-100" : "bg-white border-2 border-slate-200 text-slate-400"
        }`}
      >
        {n}
      </div>
      <span className={`text-[10px] font-bold mt-2 uppercase ${active ? "text-navy" : "text-slate-400"}`}>{label}</span>
    </div>
  );
}
