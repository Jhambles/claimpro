import Image from "next/image";
import Link from "next/link";

export default function LandingPage() {
  return (
    <div className="min-h-screen flex flex-col">
      <nav className="flex justify-between items-center px-12 py-6 border-b border-gray-100 sticky top-0 bg-white/80 backdrop-blur z-50">
        <div className="flex items-center space-x-2">
          <div className="w-8 h-8 bg-teal rounded-sm" />
          <span className="text-2xl font-bold tracking-tighter text-navy">
            CLAIMS<span className="text-teal">PRO</span>
          </span>
        </div>
        <div className="flex items-center gap-6">
          <Link href="/about" className="font-semibold text-slate-600 hover:text-teal transition">
            About Us
          </Link>
          <Link
            href="/login"
            className="bg-navy text-white px-8 py-3 rounded-lg hover:bg-teal transition font-bold shadow-lg shadow-slate-200"
          >
            Portal Login
          </Link>
        </div>
      </nav>

      <section className="relative flex flex-1 min-h-[600px] items-center overflow-hidden">
        <div className="absolute inset-0 z-0">
          <Image
            src="https://images.unsplash.com/photo-1450101499163-c8848c66ca85?auto=format&fit=crop&q=80&w=1470"
            alt=""
            fill
            priority
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
          <p className="text-xl text-slate-600 leading-relaxed max-w-2xl">
            A cloud-native solution for real-time document verification, automated LOA logic, and
            enterprise-grade claims lifecycle management.
          </p>
        </div>
      </section>

      <footer className="bg-navy py-8 px-12 text-center border-t border-white/10">
        <div className="flex flex-col items-center gap-3 sm:flex-row sm:justify-between">
          <p className="text-slate-500 text-xs tracking-widest uppercase">
            System Core v3.1 | Protected by Enterprise Encryption
          </p>
          <Link href="/about" className="text-sm text-white/70 hover:text-white transition">
            About Us
          </Link>
        </div>
      </footer>
    </div>
  );
}
