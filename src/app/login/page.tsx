"use client";

import { useState, Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { signIn } from "next-auth/react";
import Link from "next/link";

const ROLE_LABEL: Record<string, string> = {
  client: "claimant environment",
  processor: "processor environment",
  admin: "admin environment",
};

const ROLE_REDIRECT: Record<string, string> = {
  client: "/claimant",
  processor: "/processor",
  admin: "/admin",
};

function LoginForm() {
  const router = useRouter();
  const params = useSearchParams();
  const role = params.get("role") || "client";

  const [email, setEmail] = useState(`${role}@claimspro.dev`);
  const [password, setPassword] = useState("Passw0rd!");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleLogin() {
    setLoading(true);
    setError(null);
    const res = await signIn("credentials", { email, password, redirect: false });
    setLoading(false);

    if (res?.error) {
      setError("Invalid credentials. Please check your email and password.");
      return;
    }
    router.push(ROLE_REDIRECT[role] ?? "/claimant");
  }

  return (
    <div className="bg-white p-12 rounded-3xl shadow-2xl w-full max-w-md relative overflow-hidden">
      <div className="absolute top-0 left-0 w-full h-2 bg-teal" />
      <div className="text-center mb-10">
        <h2 className="inline-block px-3 py-1 bg-teal-50 text-teal text-[10px] font-black uppercase tracking-widest rounded-full mb-4">
          {ROLE_LABEL[role] ?? "secure access"}
        </h2>
        <h1 className="text-3xl font-bold text-slate-800">Welcome Back</h1>
      </div>

      <div className="space-y-6">
        <div>
          <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Email</label>
          <div className="relative mt-1">
            <i className="fa-solid fa-user absolute left-4 top-4 text-slate-300" />
            <input
              type="text"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full pl-12 pr-4 py-4 border border-slate-100 rounded-xl outline-none focus:border-teal bg-slate-50"
            />
          </div>
        </div>
        <div>
          <label className="text-[10px] font-black text-slate-400 uppercase ml-1">Password</label>
          <div className="relative mt-1">
            <i className="fa-solid fa-lock absolute left-4 top-4 text-slate-300" />
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full pl-12 pr-4 py-4 border border-slate-100 rounded-xl outline-none focus:border-teal bg-slate-50"
            />
          </div>
        </div>

        {error && <p className="text-red-500 text-xs font-bold text-center">{error}</p>}

        <button
          onClick={handleLogin}
          disabled={loading}
          className="w-full bg-navy text-white py-4 rounded-xl font-bold hover:bg-teal transition duration-300 shadow-xl shadow-slate-200 disabled:opacity-50"
        >
          {loading ? "Authenticating..." : "Authenticate System"}
        </button>
        <Link href="/" className="block text-center text-xs text-slate-400 hover:text-teal transition mt-4">
          Return to Gateway
        </Link>
      </div>
    </div>
  );
}

export default function LoginPage() {
  return (
    <div className="bg-navy flex items-center justify-center min-h-screen">
      <Suspense fallback={null}>
        <LoginForm />
      </Suspense>
    </div>
  );
}
