"use client";
import { useEffect, useState } from "react";
import { Sidebar } from "@/components/ui/Sidebar";
import { StatCard } from "@/components/ui/StatCard";
import { SystemStats } from "@/types";

const NAV = [
  { icon: "fa-chart-line", label: "Analytics Engine", href: "/admin" },
  { icon: "fa-users", label: "Identity Manager", href: "/admin/users" },
  { icon: "fa-shield-halved", label: "Security Logs", href: "#", disabled: true },
  { icon: "fa-code-branch", label: "API Endpoints", href: "#", disabled: true },
];

export default function AdminDashboardPage() {
  const [stats, setStats] = useState<SystemStats | null>(null);

  useEffect(() => {
    fetch("/api/admin/stats")
      .then((r) => (r.ok ? r.json() : null))
      .then(setStats)
      .catch(() => setStats(null));
  }, []);

  const categoryBars = stats
    ? Object.entries(stats.claimsByCategory)
    : [];
  const maxCategoryCount = Math.max(1, ...categoryBars.map(([, v]) => v));

  return (
    <div className="bg-navy min-h-screen text-white flex">
      <Sidebar brand="ADMIN CORE" items={NAV} active="Analytics Engine" />

      <main className="flex-1 p-16">
        <div className="flex justify-between items-start mb-16">
          <div>
            <h1 className="text-5xl font-black mb-2 tracking-tighter">System Health</h1>
            <p className="text-slate-400 uppercase text-[10px] tracking-[0.5em]">Real-Time Operational Monitoring</p>
          </div>
          <div className="bg-white/5 px-6 py-4 rounded-2xl border border-white/10 flex items-center space-x-4">
            <div className="w-3 h-3 bg-green-500 rounded-full animate-pulse" />
            <span className="text-sm font-bold uppercase tracking-widest">Server: Online</span>
          </div>
        </div>

        <div className="grid grid-cols-3 gap-8 mb-16">
          <StatCard label="Total Requests" value={stats ? stats.totalRequests.toLocaleString() : "—"} />
          <StatCard label="Approval Rate" value={stats ? `${stats.approvalRate}%` : "—"} sub="Of all submitted claims" />
          <StatCard label="LOA Gen Rate" value={stats ? `${stats.loaGenerationRate}%` : "—"} sub="Of approved claims" subClass="text-green-500" />
        </div>

        <div className="bg-white/5 p-12 rounded-[3rem] border border-white/10">
          <h3 className="text-2xl font-bold mb-8">Claims by Policy Category</h3>
          <div className="flex items-end space-x-4 h-40">
            {categoryBars.map(([category, count]) => (
              <div key={category} className="flex-1 flex flex-col items-center justify-end h-full">
                <div
                  className="bg-teal-600/20 border-t-4 border-teal-500 w-full hover:bg-teal-600 transition duration-500 rounded-t-xl"
                  style={{ height: `${Math.max(6, (count / maxCategoryCount) * 100)}%` }}
                />
                <span className="text-[10px] mt-2 text-slate-400 uppercase font-black">{category}</span>
              </div>
            ))}
          </div>
        </div>
      </main>
    </div>
  );
}
