"use client";

import { useState, type FormEvent } from "react";
import Link from "next/link";

const MAX_FILE_SIZE = 4 * 1024 * 1024;

export default function SignupPage() {
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [idPhoto, setIdPhoto] = useState<File | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitted, setSubmitted] = useState(false);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    if (!idPhoto) {
      setError("Please upload a photo of your valid ID.");
      return;
    }

    const formData = new FormData();
    formData.set("name", name);
    formData.set("email", email);
    formData.set("password", password);
    formData.set("idPhoto", idPhoto);
    setLoading(true);

    try {
      const response = await fetch("/api/auth/signup", { method: "POST", body: formData });
      const result = await response.json();
      if (!response.ok) {
        setError(typeof result.error === "string" ? result.error : "Could not create your account.");
        return;
      }
      setSubmitted(true);
    } catch {
      setError("Could not submit your registration. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="bg-navy flex items-center justify-center min-h-screen px-4 py-10">
      <section className="bg-white p-8 sm:p-12 rounded-3xl shadow-2xl w-full max-w-md relative overflow-hidden">
        <div className="absolute top-0 left-0 w-full h-2 bg-teal" />
        {submitted ? (
          <div className="text-center py-8">
            <h1 className="text-3xl font-bold text-slate-800 mb-4">Registration submitted</h1>
            <p className="text-slate-500 mb-8">
              Your ID is awaiting admin review. You can sign in once your account is approved.
            </p>
            <Link href="/login" className="text-teal font-bold hover:underline">Return to Log In</Link>
          </div>
        ) : (
          <>
            <div className="text-center mb-8">
              <h1 className="text-3xl font-bold text-slate-800">Create Account</h1>
              <p className="text-slate-500 text-sm mt-2">Submit a valid ID for admin verification.</p>
            </div>
            <form onSubmit={handleSubmit} className="space-y-5">
              <div>
                <label htmlFor="signup-name" className="text-xs font-bold text-slate-500">Full name</label>
                <input id="signup-name" required maxLength={120} autoComplete="name" value={name}
                  onChange={(event) => setName(event.target.value)}
                  className="w-full mt-1 px-4 py-3 border border-slate-200 rounded-xl outline-none focus:border-teal" />
              </div>
              <div>
                <label htmlFor="signup-email" className="text-xs font-bold text-slate-500">Email</label>
                <input id="signup-email" required type="email" autoComplete="email" value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  className="w-full mt-1 px-4 py-3 border border-slate-200 rounded-xl outline-none focus:border-teal" />
              </div>
              <div>
                <label htmlFor="signup-password" className="text-xs font-bold text-slate-500">Password</label>
                <input id="signup-password" required type="password" minLength={8} autoComplete="new-password" value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  className="w-full mt-1 px-4 py-3 border border-slate-200 rounded-xl outline-none focus:border-teal" />
              </div>
              <div>
                <label htmlFor="signup-id" className="text-xs font-bold text-slate-500">Photo of valid ID</label>
                <input id="signup-id" required type="file" accept="image/jpeg,image/png" onChange={(event) => {
                  const file = event.target.files?.[0] ?? null;
                  if (file && (file.size > MAX_FILE_SIZE || !["image/jpeg", "image/png"].includes(file.type))) {
                    setIdPhoto(null);
                    setError("Choose a JPG or PNG image up to 4 MB.");
                    event.target.value = "";
                    return;
                  }
                  setError(null);
                  setIdPhoto(file);
                }}
                  className="w-full mt-1 text-sm text-slate-600 file:mr-3 file:rounded-lg file:border-0 file:bg-slate-100 file:px-4 file:py-2" />
                <p className="text-xs text-slate-400 mt-1">JPG or PNG, up to 4 MB. Only admins can view it.</p>
              </div>
              {error && <p role="alert" className="text-red-500 text-sm font-bold">{error}</p>}
              <button type="submit" disabled={loading}
                className="w-full bg-navy text-white py-4 rounded-xl font-bold hover:bg-teal transition disabled:opacity-50">
                {loading ? "Submitting..." : "Create Account"}
              </button>
            </form>
            <p className="text-center text-sm text-slate-500 mt-6">
              Already registered? <Link href="/login" className="text-teal font-bold hover:underline">Log In</Link>
            </p>
          </>
        )}
      </section>
    </main>
  );
}
