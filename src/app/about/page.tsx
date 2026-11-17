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
      <header className="sticky top-0 z-50 border-b border-gray-100 bg-white/80 px-6 py-5 backdrop-blur sm:px-12">
        <nav className="mx-auto flex max-w-7xl items-center justify-between" aria-label="Main navigation">
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

      <main className="flex-1">
        <section className="bg-slate-50 px-6 py-20 sm:px-12 sm:py-28">
          <div className="mx-auto max-w-7xl">
            <span className="mb-5 block text-sm font-black uppercase tracking-[0.3em] text-teal">
              About ClaimsPro
            </span>
            <h1 className="max-w-4xl text-5xl font-black leading-tight text-navy sm:text-7xl">
              A clearer path from claim to resolution.
            </h1>
            <p className="mt-7 max-w-2xl text-lg leading-relaxed text-slate-600 sm:text-xl">
              ClaimsPro brings claimants and processing teams together in one digital workspace.
              Submit a claim, keep its documents organized, and follow its progress through review.
            </p>
            <Link
              href="/login"
              className="mt-9 inline-flex rounded-lg bg-navy px-7 py-4 font-bold text-white shadow-lg shadow-slate-200 transition hover:bg-teal"
            >
              Enter the Portal
            </Link>
          </div>
        </section>

        <section className="px-6 py-20 sm:px-12 sm:py-24">
          <div className="mx-auto max-w-7xl">
            <div className="mb-10 max-w-2xl">
              <span className="text-sm font-black uppercase tracking-[0.25em] text-teal">
                What we support
              </span>
              <h2 className="mt-3 text-3xl font-black text-navy sm:text-4xl">
                Coverage for life’s important moments.
              </h2>
              <p className="mt-4 leading-relaxed text-slate-600">
                The platform organizes claims across three coverage categories, with a consistent
                workflow for information, documents, and updates.
              </p>
            </div>

            <div className="grid gap-6 md:grid-cols-3">
              {coverageTypes.map((coverage) => (
                <article
                  key={coverage.title}
                  className="rounded-2xl border border-slate-100 bg-white p-8 shadow-lg shadow-slate-100"
                >
                  <span
                    className="mb-6 flex h-12 w-12 items-center justify-center rounded-xl bg-teal-50 text-xl text-teal"
                    aria-hidden="true"
                  >
                    <i className={`fa-solid ${coverage.icon}`} />
                  </span>
                  <h3 className="text-xl font-bold text-navy">{coverage.title}</h3>
                  <p className="mt-3 leading-relaxed text-slate-600">{coverage.description}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section className="bg-navy px-6 py-16 text-white sm:px-12">
          <div className="mx-auto flex max-w-7xl flex-col gap-6 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2 className="text-2xl font-bold">Your claim, all in one place.</h2>
              <p className="mt-2 max-w-2xl leading-relaxed text-slate-300">
                Sign in to submit and track claims, share supporting documents, and stay up to date
                as your claim moves through the process.
              </p>
            </div>
            <Link
              href="/login"
              className="shrink-0 rounded-lg bg-teal px-7 py-4 text-center font-bold text-white transition hover:bg-teal-600"
            >
              Portal Login
            </Link>
          </div>
        </section>
      </main>

      <footer className="border-t border-white/10 bg-navy px-6 py-6 text-center text-sm text-slate-400 sm:px-12">
        <p>ClaimsPro | Claims management made clearer.</p>
      </footer>
    </div>
  );
}
