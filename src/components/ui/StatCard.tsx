export function StatCard({ label, value, sub, subClass = "text-slate-500" }: { label: string; value: string; sub?: string; subClass?: string }) {
  return (
    <div className="bg-white/5 p-8 rounded-[2rem] border border-white/10">
      <p className="text-slate-400 text-xs font-bold uppercase tracking-widest mb-4">{label}</p>
      <p className="text-5xl font-mono">{value}</p>
      {sub && <p className={`text-[10px] mt-4 uppercase font-black ${subClass}`}>{sub}</p>}
    </div>
  );
}
