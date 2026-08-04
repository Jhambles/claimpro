"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useSession } from "next-auth/react";
import { NotificationDTO } from "@/types";

const ICON: Record<string, string> = {
  STATUS_UPDATE: "fa-file-invoice",
  RENEWAL: "fa-rotate",
  PAYMENT: "fa-credit-card",
};

function homeForRole(role?: string) {
  if (role === "PROCESSOR") return "/processor";
  if (role === "ADMIN") return "/admin";
  return "/claimant/claims";
}

export function NotificationBell() {
  const { data: session } = useSession();
  const [open, setOpen] = useState(false);
  const [items, setItems] = useState<NotificationDTO[]>([]);
  const [unread, setUnread] = useState(0);
  const boxRef = useRef<HTMLDivElement>(null);

  async function load() {
    const res = await fetch("/api/notifications");
    if (!res.ok) return;
    const data = await res.json();
    setItems(data.items);
    setUnread(data.unread);
  }

  useEffect(() => {
    load();
    const interval = setInterval(load, 30000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    function onClickOutside(e: MouseEvent) {
      if (boxRef.current && !boxRef.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", onClickOutside);
    return () => document.removeEventListener("mousedown", onClickOutside);
  }, []);

  async function markRead(id: string) {
    await fetch(`/api/notifications/${id}`, { method: "PATCH" });
    load();
  }

  return (
    <div className="fixed top-6 right-6 z-40" ref={boxRef}>
      <button
        onClick={() => setOpen((o) => !o)}
        className="relative w-11 h-11 rounded-full bg-white shadow-lg border border-slate-100 flex items-center justify-center hover:shadow-xl transition"
      >
        <i className="fa-solid fa-bell text-slate-600" />
        {unread > 0 && (
          <span className="absolute -top-1 -right-1 bg-red-500 text-white text-[10px] font-black w-5 h-5 rounded-full flex items-center justify-center">
            {unread > 9 ? "9+" : unread}
          </span>
        )}
      </button>

      {open && (
        <div className="absolute right-0 mt-3 w-80 bg-white rounded-2xl shadow-2xl border border-slate-100 overflow-hidden">
          <div className="px-5 py-4 border-b border-slate-50 font-bold text-navy text-sm">Notifications</div>
          <div className="max-h-96 overflow-y-auto divide-y divide-slate-50">
            {items.length === 0 && <p className="p-6 text-center text-slate-400 text-sm">You're all caught up.</p>}
            {items.map((n) => (
              <button
                key={n.id}
                onClick={() => !n.read && markRead(n.id)}
                className={`w-full text-left px-5 py-4 flex items-start gap-3 hover:bg-slate-50 transition ${!n.read ? "bg-teal-50/40" : ""}`}
              >
                <i className={`fa-solid ${ICON[n.type] ?? "fa-bell"} text-teal mt-0.5`} />
                <div>
                  <p className="text-sm text-slate-700">{n.message}</p>
                  <p className="text-[10px] text-slate-400 mt-1 uppercase font-bold">
                    {new Date(n.createdAt).toLocaleString()}
                  </p>
                </div>
              </button>
            ))}
          </div>
          <Link href={homeForRole(session?.user?.role)} className="block text-center text-xs font-bold text-teal py-3 hover:underline border-t border-slate-50">
            {session?.user?.role === "CLIENT" ? "View My Claims" : "Back to Dashboard"}
          </Link>
        </div>
      )}
    </div>
  );
}
