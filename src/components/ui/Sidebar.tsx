"use client";
import Link from "next/link";
import { signOut } from "next-auth/react";

export function Sidebar({
  brand,
  items,
  active,
  dark = true,
}: {
  brand: string;
  items: { icon: string; label: string; href: string; disabled?: boolean }[];
  active: string;
  dark?: boolean;
}) {
  return (
    <aside
      className={`w-72 ${dark ? "bg-black/30 border-white/5" : "bg-navy"} border-r flex flex-col py-10 px-8 sticky top-0 h-screen text-white`}
    >
      <div className="flex items-center space-x-3 mb-16">
        <div className="w-8 h-8 bg-teal rounded-lg shadow-lg shadow-teal-500/20" />
        <span className="text-xl font-black tracking-tighter">{brand}</span>
      </div>

      <nav className="flex-1 space-y-8">
        {items.map((item) =>
          item.disabled ? (
            <div key={item.label} className="flex items-center justify-between text-slate-600 cursor-not-allowed">
              <span className="flex items-center space-x-4 font-bold">
                <i className={`fa-solid ${item.icon} w-5`} />
                <span>{item.label}</span>
              </span>
              <span className="text-[9px] bg-white/5 px-2 py-0.5 rounded-full uppercase tracking-widest">Soon</span>
            </div>
          ) : (
            <Link
              key={item.href}
              href={item.href}
              className={`flex items-center space-x-4 font-bold transition ${
                item.label === active ? "text-teal-400" : "text-slate-400 hover:text-white"
              }`}
            >
              <i className={`fa-solid ${item.icon} w-5`} />
              <span>{item.label}</span>
            </Link>
          )
        )}
      </nav>

      <button
        onClick={() => signOut({ callbackUrl: "/" })}
        className="flex items-center space-x-4 text-red-500 font-black text-sm uppercase tracking-widest hover:text-red-400 transition"
      >
        <i className="fa-solid fa-power-off" />
        <span>Sign Out</span>
      </button>
    </aside>
  );
}
