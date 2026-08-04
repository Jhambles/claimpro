"use client";

export function Toast({ show, title, message }: { show: boolean; title: string; message: string }) {
  return (
    <div
      className={`fixed bottom-10 right-10 bg-navy text-white px-8 py-5 rounded-2xl shadow-2xl transition-all duration-500 border-l-8 border-teal flex items-center space-x-6 ${
        show ? "translate-y-0 opacity-100" : "translate-y-40 opacity-0"
      }`}
    >
      <div className="w-10 h-10 bg-teal-500/20 rounded-full flex items-center justify-center">
        <i className="fa-solid fa-check text-teal-400" />
      </div>
      <div>
        <p className="text-sm font-bold uppercase tracking-widest">{title}</p>
        <p className="text-xs text-slate-400 italic">{message}</p>
      </div>
    </div>
  );
}
