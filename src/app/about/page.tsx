import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "About Us | ClaimsPro",
  description: "Learn about ClaimsPro and the coverage categories supported by the platform.",
};

const coverageTypes = [
  {
    icon: "fa-heart-pulse",
    title: "Medical Expense Coverage",
    description:
      "Keep medical expense claims and their supporting documents organized through the claims process.",
  },
  {
    icon: "fa-car",
    title: "Automotive Damage",
    description:
      "Bring vehicle damage claims, evidence, and review updates together in one place.",
  },
  {
    icon: "fa-house",
    title: "Homeowners Protection",
    description:
      "Manage property claims with a clear record of submitted information and supporting documents.",
  },
];

export default function AboutPage() {
  return (
    <div className="min-h-screen flex flex-col">
      <header className="sticky top-0 z-50 border-b border-gray-100 bg-white/80 px-12 py-6 backdrop-blur">
        <nav className="flex items-center justify-between" aria-label="Main navigation">
          <Link href="/" className="flex items-center space-x-2">
            <span className="h-8 w-8 rounded-sm bg-teal" aria-hidden="true" />
            <span className="text-2xl font-bold tracking-tighter text-navy">
              CLAIMS<span className="text-teal">PRO</span>
            </span>
          </Link>
          <div className="flex items-center gap-6">
            <Link href="/" className="font-semibold text-slate-600 transition hover:text-teal">
              Home
            </Link>
            <Link
              href="/login"
              className="rounded-lg bg-navy px-5 py-3 font-bold text-white shadow-lg shadow-slate-200 transition hover:bg-teal"
            >
              Portal Login
            </Link>
          </div>
        </nav>
      </header>

      <main className="relative flex min-h-[600px] flex-1 items-center overflow-hidden bg-slate-50 px-6 py-12 sm:px-12">
        <div className="mx-auto grid w-full max-w-7xl gap-12 lg:grid-cols-[0.9fr_1.1fr] lg:items-center">
          <section>
            <span className="mb-5 block text-sm font-black uppercase tracking-[0.3em] text-teal">
              About ClaimsPro
            </span>
            <h1 className="max-w-2xl text-5xl font-black leading-tight text-navy sm:text-6xl">
              A clearer path from claim to resolution.
            </h1>
            <p className="mt-5 max-w-xl text-lg leading-relaxed text-slate-600">
              ClaimsPro brings claimants and processing teams together in one digital workspace.
              Submit a claim, keep its documents organized, and follow its progress through review.
            </p>
            <Link
              href="/login"
              className="mt-7 inline-flex rounded-lg bg-navy px-7 py-4 font-bold text-white shadow-lg shadow-slate-200 transition hover:bg-teal"
            >
              Enter the Portal
            </Link>
          </section>

          <section>
            <div className="mb-6">
              <span className="text-sm font-black uppercase tracking-[0.25em] text-teal">
                What we support
              </span>
              <h2 className="mt-2 text-3xl font-black text-navy">
                Coverage for life’s important moments.
              </h2>
              <p className="mt-3 leading-relaxed text-slate-600">
                The platform organizes claims across three coverage categories, with a consistent
                workflow for information, documents, and updates.
              </p>
            </div>

            <div className="grid gap-4 sm:grid-cols-3">
              {coverageTypes.map((coverage) => (
                <article
                  key={coverage.title}
                  className="rounded-2xl border border-slate-100 bg-white p-5 shadow-lg shadow-slate-100"
                >
                  <span
                    className="mb-4 flex h-10 w-10 items-center justify-center rounded-xl bg-teal-50 text-lg text-teal"
                    aria-hidden="true"
                  >
                    <i className={`fa-solid ${coverage.icon}`} />
                  </span>
                  <h3 className="text-lg font-bold text-navy">{coverage.title}</h3>
                  <p className="mt-2 text-sm leading-relaxed text-slate-600">{coverage.description}</p>
                </article>
              ))}
            </div>
          </section>
        </div>
      </main>

      <footer className="bg-navy py-8 px-12 text-center border-t border-white/10">
        <p className="text-slate-500 text-xs tracking-widest uppercase">
          ClaimsPro | Claims management made clearer.
        </p>
      </footer>
    </div>
  );
}
