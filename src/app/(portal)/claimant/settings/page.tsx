"use client";
import { useEffect, useState } from "react";
import { Sidebar } from "@/components/ui/Sidebar";
import { CLAIMANT_NAV } from "@/lib/claimantNav";

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

interface PayoutPreference {
  provider: "GCASH" | "MAYA" | "PAYPAL" | "BANK_TRANSFER";
  bankName: string | null;
  accountName: string | null;
  accountNumber: string | null;
}

export default function SettingsPage() {
  const [loading, setLoading] = useState(true);
  const [provider, setProvider] = useState<"GCASH" | "MAYA" | "PAYPAL" | "BANK_TRANSFER">("GCASH");
  const [bankChoice, setBankChoice] = useState(PH_BANKS[0]);
  const [otherBankName, setOtherBankName] = useState("");
  const [accountName, setAccountName] = useState("");
  const [accountNumber, setAccountNumber] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    fetch("/api/settings/payout-preference")
      .then((r) => (r.ok ? r.json() : null))
      .then((pref: PayoutPreference | null) => {
        if (pref) {
          setProvider(pref.provider);
          if (pref.bankName) {
            const isKnownBank = PH_BANKS.slice(0, -1).includes(pref.bankName);
            setBankChoice(isKnownBank ? pref.bankName : "Other Bank");
            if (!isKnownBank) setOtherBankName(pref.bankName);
          }
          setAccountName(pref.accountName ?? "");
          setAccountNumber(pref.accountNumber ?? "");
        }
      })
      .catch((err) => console.error("Failed to load payout preference:", err))
      .finally(() => setLoading(false));
  }, []);

  async function handleSave() {
    setError(null);
    setSaved(false);

    const bankDetails =
      provider === "BANK_TRANSFER"
        ? {
            bankName: bankChoice === "Other Bank" ? otherBankName.trim() : bankChoice,
            accountName: accountName.trim(),
            accountNumber: accountNumber.trim(),
          }
        : {};

    if (provider === "BANK_TRANSFER" && (!bankDetails.bankName || !bankDetails.accountName || !bankDetails.accountNumber)) {
      setError("Please fill in the bank name, account name, and account number.");
      return;
    }

    setSaving(true);
    const res = await fetch("/api/settings/payout-preference", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ provider, ...bankDetails }),
    });
    setSaving(false);

    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      setError(typeof body.error === "string" ? body.error : "Could not save your payout preference.");
      return;
    }

    setSaved(true);
    setTimeout(() => setSaved(false), 3000);
  }

  return (
    <div className="flex bg-slate-50 min-h-screen">
      <Sidebar brand="CLAIMS PRO" items={CLAIMANT_NAV} active="Settings" dark={false} />

      <main className="flex-1 p-12">
        <header className="mb-12">
          <h1 className="text-4xl font-black text-navy">Settings</h1>
          <p className="text-slate-400 mt-2 italic">Manage your default payout method</p>
        </header>

        <div className="bg-white p-10 rounded-3xl shadow-sm border border-slate-100 max-w-3xl">
          <p className="text-[10px] font-black text-slate-400 uppercase mb-2">Default Payout Method</p>
          <p className="text-slate-400 text-sm mb-6">
            Set your preferred way to receive claim payouts. You can always choose a different method when actually claiming a specific payout.
          </p>

          {loading ? (
            <p className="text-slate-400 text-sm">Loadingâ€¦</p>
          ) : (
            <>
              <div className="flex gap-4 flex-wrap mb-8">
                {PROVIDERS.map((p) => (
                  <button
                    key={p.key}
                    onClick={() => setProvider(p.key)}
                    className={`px-6 py-3 rounded-xl font-bold text-sm transition ${
                      provider === p.key ? `${p.color} text-white` : "bg-slate-50 text-slate-500 border border-slate-100 hover:bg-slate-100"
                    }`}
                  >
                    {p.label}
                  </button>
                ))}
              </div>

              {provider === "BANK_TRANSFER" && (
                <div className="space-y-4 mb-8 max-w-md">
                  <div>
                    <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">Bank</label>
                    <select
                      value={bankChoice}
                      onChange={(e) => setBankChoice(e.target.value)}
                      className="w-full p-3 border border-slate-200 rounded-xl bg-slate-50 outline-none focus:border-teal"
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
                        className="w-full p-3 border border-slate-200 rounded-xl bg-slate-50 outline-none focus:border-teal"
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
                      className="w-full p-3 border border-slate-200 rounded-xl bg-slate-50 outline-none focus:border-teal"
                    />
                  </div>
                  <div>
                    <label className="text-[10px] font-black text-slate-400 uppercase block mb-2">Account Number</label>
                    <input
                      type="text"
                      value={accountNumber}
                      onChange={(e) => setAccountNumber(e.target.value)}
                      placeholder="Bank account number"
                      className="w-full p-3 border border-slate-200 rounded-xl bg-slate-50 outline-none focus:border-teal"
                    />
                  </div>
                </div>
              )}

              {error && <p className="text-red-500 text-xs font-bold mb-4">{error}</p>}
              {saved && <p className="text-teal text-xs font-bold mb-4">Saved!</p>}

              <button
                onClick={handleSave}
                disabled={saving}
                className="bg-navy text-white px-8 py-4 rounded-2xl font-bold hover:bg-teal transition-all disabled:opacity-50"
              >
                {saving ? "Savingâ€¦" : "Save Preference"}
              </button>
            </>
          )}
        </div>
      </main>
    </div>
  );
}
