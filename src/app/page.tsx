import Image from "next/image";
import Link from "next/link";

// Converted 1:1 from the original index.html hero + role-select sections.
export default function LandingPage() {
  return (
    <>
      <nav className="flex justify-between items-center px-12 py-6 border-b border-gray-100 sticky top-0 bg-white/80 backdrop-blur z-50">
        <div className="flex items-center space-x-2">
          <div className="w-8 h-8 bg-teal rounded-sm" />
          <span className="text-2xl font-bold tracking-tighter text-navy">
            CLAIMS<span className="text-teal">PRO</span>
          </span>
        </div>
        <Link
          href="/login"
          className="bg-navy text-white px-8 py-3 rounded-lg hover:bg-teal transition font-bold shadow-lg shadow-slate-200"
        >
          Portal Login
        </Link>
      </nav>

      <section className="relative h-[600px] flex items-center overflow-hidden">
        <div className="absolute inset-0 z-0">
          <Image
            src="https://images.unsplash.com/photo-1450101499163-c8848c66ca85?auto=format&fit=crop&q=80&w=1470"
            alt=""
            fill
            className="object-cover opacity-10"
          />
          <div className="absolute inset-0 bg-gradient-to-r from-white via-white/40 to-transparent" />
        </div>
        <div className="relative z-10 px-12 max-w-4xl">
          <span className="text-teal font-black tracking-[0.3em] text-sm uppercase mb-4 block">
            Next-Gen Insurance Platform
          </span>
          <h1 className="text-7xl font-black leading-tight text-navy mb-6">
            Efficiency in every <span className="text-teal">Claim.</span>
          </h1>
          <p className="text-xl text-slate-600 mb-10 leading-relaxed max-w-2xl">
            A cloud-native solution for real-time document verification, automated LOA logic, and
            enterprise-grade claims lifecycle management.
          </p>
          <div className="flex space-x-4">
            <a
              href="#roles"
              className="bg-teal text-white px-10 py-5 rounded-xl font-bold hover:scale-105 transition shadow-xl shadow-teal-100"
            >
              Get Started
            </a>
            <button className="border border-slate-300 px-10 py-5 rounded-xl font-bold hover:bg-slate-50 transition">
              Watch Demo
            </button>
          </div>
        </div>
      </section>

      <section id="roles" className="py-24 px-12 bg-slate-50">
        <div className="text-center mb-20">
          <h2 className="text-4xl font-black text-navy">Access Portals</h2>
          <p className="text-slate-500 mt-2">Select your designated interface to manage the claims lifecycle.</p>
        </div>

        <div className="grid md:grid-cols-3 gap-10 max-w-7xl mx-auto">
          <RoleCard
            icon="fa-user-tag"
            title="Claimant"
            desc="Submit claims, upload medical/property evidence, and track approval status."
            href="/login?role=client"
            cta="Enter Portal"
          />
          <RoleCard
            icon="fa-clipboard-check"
            title="Processor"
            desc="Verify document authenticity and evaluate claim eligibility requirements."
            href="/login?role=processor"
            cta="Staff Login"
          />
          <RoleCard
            icon="fa-gears"
            title="Admin"
            desc="Configure system parameters, manage users, and monitor LOA analytics."
            href="/login?role=admin"
            cta="Admin Panel"
          />
        </div>
      </section>

      <footer className="bg-navy py-8 px-12 text-center border-t border-white/10">
        <p className="text-slate-500 text-xs tracking-widest uppercase">
          System Core v3.1 | Protected by Enterprise Encryption
        </p>
      </footer>
    </>
  );
}

function RoleCard({ icon, title, desc, href, cta }: { icon: string; title: string; desc: string; href: string; cta: string }) {
  return (
    <div className="group bg-white p-12 rounded-3xl shadow-sm border border-slate-100 hover:shadow-2xl transition-all">
      <div className="w-16 h-16 bg-slate-50 rounded-2xl flex items-center justify-center mb-8 group-hover:bg-teal-50 transition">
        <i className={`fa-solid ${icon} text-3xl text-slate-300 group-hover:text-teal`} />
      </div>
      <h3 className="text-2xl font-bold mb-3 text-navy">{title}</h3>
      <p className="text-slate-500 mb-8 text-sm leading-relaxed">{desc}</p>
      <Link href={href} className="text-teal font-bold flex items-center group-hover:translate-x-2 transition">
        {cta} <i className="fa-solid fa-arrow-right ml-2" />
      </Link>
    </div>
  );
}
